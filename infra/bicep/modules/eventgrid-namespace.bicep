// Event Grid Namespace with MQTT broker module
@description('The name of the Event Grid namespace')
param namespaceName string

@description('The location for the Event Grid namespace')
param location string

@description('Tags to apply to the namespace')
param tags object = {}

@description('MQTT client ID for the proxy')
param mqttClientId string

resource eventGridNamespace 'Microsoft.EventGrid/namespaces@2024-06-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    capacity: 1
  }
  properties: {
    topicSpacesConfiguration: {
      state: 'Enabled'
      routeTopicResourceId: null
      maximumSessionExpiryInHours: 8
      maximumClientSessionsPerAuthenticationName: 1
      clientAuthentication: {
        alternativeAuthenticationNameSources: []
      }
      routingEnrichments: {
        dynamic: []
        static: []
      }
      routingIdentityInfo: null
    }
    isZoneRedundant: false
    publicNetworkAccess: 'Enabled'
  }
  identity: {
    type: 'None'
  }
}

// Create MQTT client for the proxy
resource mqttClient 'Microsoft.EventGrid/namespaces/clients@2024-06-01-preview' = {
  parent: eventGridNamespace
  name: mqttClientId
  properties: {
    state: 'Enabled'
    authenticationName: mqttClientId
    description: 'MQTT proxy client for on-premises bridge'
    attributes: {}
  }
}

// Create topic space for sensor data
resource topicSpace 'Microsoft.EventGrid/namespaces/topicSpaces@2024-06-01-preview' = {
  parent: eventGridNamespace
  name: 'sensor-data'
  properties: {
    description: 'Topic space for sensor data from on-premises devices'
    topicTemplates: [
      'sensor/#'
    ]
  }
}

// Create permission binding for publish
resource publisherPermissionBinding 'Microsoft.EventGrid/namespaces/permissionBindings@2024-06-01-preview' = {
  parent: eventGridNamespace
  name: '${mqttClientId}-publisher'
  properties: {
    clientGroupName: '$all'
    permission: 'Publisher'
    topicSpaceName: topicSpace.name
    description: 'Allow all clients to publish to sensor data topics'
  }
  dependsOn: [
    mqttClient
  ]
}

// Create permission binding for subscribe
resource subscriberPermissionBinding 'Microsoft.EventGrid/namespaces/permissionBindings@2024-06-01-preview' = {
  parent: eventGridNamespace
  name: '${mqttClientId}-subscriber'
  properties: {
    clientGroupName: '$all'
    permission: 'Subscriber'
    topicSpaceName: topicSpace.name
    description: 'Allow all clients to subscribe to sensor data topics'
  }
  dependsOn: [
    mqttClient
  ]
}

output namespaceName string = eventGridNamespace.name
output namespaceId string = eventGridNamespace.id
output hostname string = eventGridNamespace.properties.topicsConfiguration.hostname
output mqttClientName string = mqttClient.name
output topicSpaceName string = topicSpace.name
