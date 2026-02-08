// Event Grid Subscription module
@description('The name of the Event Grid subscription')
param subscriptionName string

@description('The name of the Event Grid topic')
param topicName string

@description('The name of the function app')
param functionAppName string

@description('The name of the function')
param functionName string

resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' existing = {
  name: topicName
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' existing = {
  name: functionAppName
}

resource eventGridSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: subscriptionName
  scope: eventGridTopic
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/${functionName}'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.EventGrid.SubscriptionValidationEvent'
        'Microsoft.EventGrid.SubscriptionDeletedEvent'
      ]
      enableAdvancedFilteringOnArrays: true
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}

output subscriptionName string = eventGridSubscription.name
output subscriptionId string = eventGridSubscription.id
