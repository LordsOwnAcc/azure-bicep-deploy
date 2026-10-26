# Azure Deployment with Bicep

Bicep deploys a resource group, Log Analytics, Azure Container Registry, a managed identity with AcrPull,
a Container Apps environment + app, and Azure Monitor alerts (5xx and crash-loop) with email action group.

Run: `./deploy.sh you@example.com`. See `docs/runbook.md`.

**Cost note:** Basic ACR + small Container App is cheap; delete with `az group delete -n bicepdemo-rg --yes`.
