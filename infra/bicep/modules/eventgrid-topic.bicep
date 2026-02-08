// Event Grid Topic module
@description('The name of the Event Grid topic')
param topicName string

@description('The location for the Event Grid topic')
param location string

@description('Tags to apply to the topic')
param tags object = {}

resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: topicName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
  }
}

output topicName string = eventGridTopic.name
output topicId string = eventGridTopic.id
output endpoint string = eventGridTopic.properties.endpoint
