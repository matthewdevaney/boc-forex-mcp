targetScope = 'resourceGroup'

@description('Name of the azd environment (used in resource names)')
@minLength(1)
param environmentName string

@description('Primary location for all resources')
param location string = resourceGroup().location

@description('Principal ID to grant ACR push/pull (for azd pipeline or your user)')
@minLength(0)
param principalId string = ''

@description('Full container image reference to deploy (registry/name:tag)')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

module fastmcp './resources.bicep' = {
  name: 'fastmcp-resources'
  params: {
    environmentName: environmentName
    location: location
    principalId: principalId
    containerImage: containerImage
  }
}

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = fastmcp.outputs.registryEndpoint
output FASTMCP_CONTAINER_APP_ID string = fastmcp.outputs.containerAppId
output FASTMCP_URL string = fastmcp.outputs.containerAppUrl
