// Main Bicep template for ACME MQTT Azure infrastructure
targetScope = 'resourceGroup'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The environment name (e.g., dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environmentName string = 'dev'

@description('The base name for all resources')
param projectName string = 'acme-mqtt'

@description('Event Grid namespace name')
param eventGridNamespaceName string = '${projectName}-${environmentName}-egns-${substring(uniqueString(resourceGroup().name), 0, 4)}'

@description('Storage account name (must be globally unique)')
@maxLength(24)
param storageAccountName string = toLower(replace('${projectName}${environmentName}${substring(uniqueString(resourceGroup().name), 0, 4)}sa', '-', ''))

@description('Function app name')
param functionAppName string = '${projectName}-${environmentName}-func-${substring(uniqueString(resourceGroup().name), 0, 4)}'

@description('Event Grid topic name')
param eventGridTopicName string = '${projectName}-${environmentName}-topic-${substring(uniqueString(resourceGroup().name), 0, 4)}'

@description('MQTT client ID for proxy')
param mqttClientId string = 'mqtt-proxy'

@description('Tags to apply to all resources')
param tags object = {
  project: 'acme-mqtt'
  environment: environmentName
  managedBy: 'bicep'
}

// Deploy Event Grid namespace with MQTT broker
module eventGridNamespace 'modules/eventgrid-namespace.bicep' = {
  name: 'eventGridNamespace-deployment'
  params: {
    namespaceName: eventGridNamespaceName
    location: location
    tags: tags
    mqttClientId: mqttClientId
  }
}

// Deploy Storage Account
module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccount-deployment'
  params: {
    storageAccountName: storageAccountName
    location: location
    tags: tags
  }
}

// Deploy Function App
module functionApp 'modules/function-app.bicep' = {
  name: 'functionApp-deployment'
  params: {
    functionAppName: functionAppName
    location: location
    tags: tags
    storageAccountName: storageAccount.outputs.storageAccountName
    storageAccountConnectionString: storageAccount.outputs.connectionString
  }
}

// Deploy Event Grid Topic
module eventGridTopic 'modules/eventgrid-topic.bicep' = {
  name: 'eventGridTopic-deployment'
  params: {
    topicName: eventGridTopicName
    location: location
    tags: tags
  }
}

@description('Whether to deploy Event Grid subscription (set to false if function code not yet deployed)')
param deployEventGridSubscription bool = false

// Deploy Event Grid Subscription (conditionally deployed after function app is ready)
module eventGridSubscription 'modules/eventgrid-subscription.bicep' = if (deployEventGridSubscription) {
  name: 'eventGridSubscription-deployment'
  params: {
    subscriptionName: '${projectName}-${environmentName}-subscription'
    topicName: eventGridTopic.outputs.topicName
    functionAppName: functionApp.outputs.functionAppName
    functionName: 'EventGridTrigger'
  }
  dependsOn: [
    functionApp
    eventGridTopic
  ]
}

// Outputs
output eventGridNamespaceName string = eventGridNamespace.outputs.namespaceName
output eventGridNamespaceHostname string = eventGridNamespace.outputs.hostname
output storageAccountName string = storageAccount.outputs.storageAccountName
output functionAppName string = functionApp.outputs.functionAppName
output eventGridTopicName string = eventGridTopic.outputs.topicName
output eventGridTopicEndpoint string = eventGridTopic.outputs.endpoint
output eventGridSubscriptionName string = deployEventGridSubscription ? eventGridSubscription.outputs.subscriptionName : 'Not deployed'
output resourceGroupName string = resourceGroup().name
