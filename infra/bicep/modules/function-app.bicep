// Function App module (Consumption tier - pay per execution, zero idle cost)
@description('The name of the function app')
param functionAppName string

@description('The location for the function app')
param location string

@description('Tags to apply to the function app')
param tags object = {}

@description('The name of the storage account')
param storageAccountName string

@description('The connection string for the storage account')
@secure()
param storageAccountConnectionString string

// Create App Service Plan (Consumption - Y1 Dynamic, pay-per-execution)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

// Create Function App (Consumption)
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: storageAccountConnectionString
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: storageAccountConnectionString
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'BLOB_CONTAINER_NAME'
          value: 'mqtt-data'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
}

// Grant Function App Storage Blob Data Contributor role
resource storageAccountRef 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource blobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountRef.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccountRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
output functionAppPrincipalId string = functionApp.identity.principalId
