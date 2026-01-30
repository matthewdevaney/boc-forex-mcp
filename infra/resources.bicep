targetScope = 'resourceGroup'

@description('Name of the azd environment (used in resource names)')
@minLength(1)
param environmentName string

@description('Primary location for all resources')
param location string

@description('Principal ID to grant ACR push/pull access (azd pipeline or user)')
@minLength(0)
param principalId string

@description('Full container image reference to deploy (registry/name:tag)')
param containerImage string

var nameToken = toLower(replace(environmentName, ' ', '-'))
var uniqueToken = toLower(uniqueString(resourceGroup().id, environmentName))
var tags = {
  'azd-env-name': environmentName
}

var acrName = take(replace('acr${nameToken}${uniqueToken}', '-', ''), 50)
var logAnalyticsName = take('la-${nameToken}-${uniqueToken}', 63)
var managedEnvName = take('cae-${nameToken}', 80)
var containerAppName = take('fastmcp-${nameToken}', 80)
var identityName = take('uai-${nameToken}', 128)

resource acr 'Microsoft.ContainerRegistry/registries@2023-06-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
    }
  }
  tags: tags
}

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identityName
  location: location
  tags: tags
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  sku: {
    name: 'PerGB2018'
  }
  properties: {
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: tags
}

var logAnalyticsSharedKey = listKeys(logAnalytics.id, '2023-09-01').primarySharedKey

resource containerEnv 'Microsoft.App/managedEnvironments@2024-02-02-preview' = {
  name: managedEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalyticsSharedKey
      }
    }
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'fastmcp' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        transport: 'auto'
      }
      secrets: []
      registries: [
        {
          server: acr.properties.loginServer
          identity: appIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'fastmcp'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'PORT'
              value: '8000'
            }
            {
              name: 'MCP_ENTRY'
              value: 'deployed_mcp'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
}

resource appIdentityPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, 'AcrPull', appIdentity.id)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource pipelinePushRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(acr.id, 'AcrPush', principalId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output registryEndpoint string = acr.properties.loginServer
output containerAppId string = containerApp.id
output containerAppUrl string = format('https://{0}', containerApp.properties.configuration.ingress.fqdn)
