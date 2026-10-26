param location string
param prefix string
param image string
param targetPort int
param alertEmail string

var suffix = uniqueString(resourceGroup().id)
// Built-in role: AcrPull
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// ---------- Observability backend ----------
resource logs 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${prefix}-logs'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ---------- Container registry ----------
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: '${prefix}acr${suffix}'
  location: location
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false // no shared admin password; use identities
  }
}

// ---------- Identity that is allowed to pull images ----------
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${prefix}-id'
  location: location
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, identity.id, acrPullRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------- App hosting: Container Apps ----------
resource env 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${prefix}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
  }
}

resource app 'Microsoft.App/containerApps@2023-05-01' = {
  name: '${prefix}-api'
  location: location
  dependsOn: [ acrPull ] // role must exist before first pull
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'auto'
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: identity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: image
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
}

// ---------- Azure Monitor alerting ----------
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${prefix}-alerts-ag'
  location: 'global'
  properties: {
    groupShortName: 'bicepalert'
    enabled: true
    emailReceivers: [
      {
        name: 'owner'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource http5xx 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${prefix}-http-5xx'
  location: 'global'
  properties: {
    description: 'More than 5 server errors (5xx) in 5 minutes'
    severity: 2
    enabled: true
    scopes: [ app.id ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xx'
          metricNamespace: 'microsoft.app/containerapps'
          metricName: 'Requests'
          dimensions: [
            { name: 'statusCodeCategory', operator: 'Include', values: [ '5xx' ] }
          ]
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [ { actionGroupId: actionGroup.id } ]
  }
}

resource restarts 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${prefix}-restarts'
  location: 'global'
  properties: {
    description: 'Container restarted more than 3 times in 15 minutes (crash loop)'
    severity: 1
    enabled: true
    scopes: [ app.id ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Restarts'
          metricNamespace: 'microsoft.app/containerapps'
          metricName: 'RestartCount'
          operator: 'GreaterThan'
          threshold: 3
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [ { actionGroupId: actionGroup.id } ]
  }
}

output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output appUrl string = 'https://${app.properties.configuration.ingress.fqdn}'
