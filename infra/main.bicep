targetScope = 'subscription'

@description('Azure region')
param location string = 'centralindia'

@description('Short alphanumeric prefix, lowercase (used in ACR name)')
@minLength(3)
@maxLength(12)
param prefix string = 'bicepdemo'

@description('Container image. Phase 1 uses a public placeholder; phase 2 uses your ACR image')
param image string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Port the container listens on (80 for placeholder, 8080 for our API)')
param targetPort int = 80

@description('Email for Azure Monitor alerts')
param alertEmail string

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: '${prefix}-rg'
  location: location
}

module resources 'modules/resources.bicep' = {
  name: 'resources'
  scope: rg
  params: {
    location: location
    prefix: prefix
    image: image
    targetPort: targetPort
    alertEmail: alertEmail
  }
}

output resourceGroupName string = rg.name
output acrName string = resources.outputs.acrName
output acrLoginServer string = resources.outputs.acrLoginServer
output appUrl string = resources.outputs.appUrl
