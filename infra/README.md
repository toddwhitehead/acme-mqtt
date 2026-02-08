# ACME MQTT Infrastructure as Code

This directory contains Infrastructure as Code (IaC) templates and scripts to provision Azure resources required for the ACME MQTT solution.

## Overview

The infrastructure consists of the following Azure resources:

1. **Event Grid Namespace** - With MQTT broker enabled for IoT device connectivity
2. **Storage Account** - For storing MQTT message data in blob containers
3. **Function App** - Serverless function triggered by Event Grid events
4. **Event Grid Topic** - For routing MQTT messages to the Function App
5. **Event Grid Subscription** - Connects the topic to the Function App

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (version 2.50.0 or later)
- An active Azure subscription
- Appropriate permissions to create resources in Azure
- `jq` command-line JSON processor (for parsing deployment outputs)

### Install Azure CLI

**Linux/macOS:**
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

**Windows:**
Download and install from: https://aka.ms/installazurecliwindows

### Login to Azure

```bash
az login
```

To use a specific subscription:
```bash
az account set --subscription "<subscription-id>"
```

## Quick Start

### 1. Deploy Infrastructure

Deploy the development environment:

```bash
cd infra
./deploy.sh --environment dev
```

Deploy to a custom resource group and location:

```bash
./deploy.sh \
  --environment prod \
  --resource-group my-custom-rg \
  --location eastus
```

### 2. Configure Environment Variables

After deployment completes, generate a SAS token for MQTT authentication:

```bash
# Get the Event Grid namespace name
NAMESPACE_NAME=$(az eventgrid namespace list \
  --resource-group acme-mqtt-dev-rg \
  --query '[0].name' -o tsv)

# Generate SAS token (valid until 2025-12-31)
az eventgrid namespace client generate-sas-token \
  --resource-group acme-mqtt-dev-rg \
  --namespace-name $NAMESPACE_NAME \
  --client-name mqtt-proxy \
  --expiry-time-utc "2025-12-31T23:59:59Z"
```

Update your `.env` file in the project root with the generated values:

```env
EVENTGRID_MQTT_HOSTNAME=<your-namespace>.<region>.ts.eventgrid.azure.net
MQTT_CLIENT_ID=mqtt-proxy
MQTT_USERNAME=mqtt-proxy
MQTT_PASSWORD=<sas-token-from-above>
```

### 3. Deploy the Azure Function

```bash
cd ../azure-function

# Install Azure Functions Core Tools if not already installed
npm install -g azure-functions-core-tools@4

# Deploy the function
func azure functionapp publish <function-app-name>
```

Replace `<function-app-name>` with the name from deployment outputs.

### 4. Start On-Premises Services

```bash
cd ..
docker-compose up -d
```

## Directory Structure

```
infra/
├── bicep/
│   ├── main.bicep                        # Main Bicep template
│   ├── parameters.dev.json               # Development parameters
│   ├── parameters.prod.json              # Production parameters
│   └── modules/
│       ├── eventgrid-namespace.bicep     # Event Grid namespace with MQTT
│       ├── storage-account.bicep         # Storage account
│       ├── function-app.bicep            # Function app with consumption plan
│       ├── eventgrid-topic.bicep         # Event Grid topic
│       └── eventgrid-subscription.bicep  # Event Grid subscription
├── deploy.sh                             # Deployment script
├── cleanup.sh                            # Cleanup script
└── README.md                             # This file
```

## Deployment Scripts

### deploy.sh

Deploys the complete Azure infrastructure using Bicep templates.

**Usage:**
```bash
./deploy.sh [OPTIONS]

Options:
  -e, --environment ENV    Environment name (dev, staging, prod). Default: dev
  -r, --resource-group RG  Resource group name. Default: acme-mqtt-<environment>-rg
  -l, --location LOC       Azure region. Default: westus2
  -s, --subscription ID    Azure subscription ID (optional)
  -h, --help               Display help message
```

**Examples:**
```bash
# Deploy to development environment (default)
./deploy.sh

# Deploy to production with custom resource group
./deploy.sh --environment prod --resource-group acme-mqtt-prod-rg

# Deploy to a specific Azure region
./deploy.sh --environment staging --location eastus2

# Deploy using a specific subscription
./deploy.sh --subscription "00000000-0000-0000-0000-000000000000"
```

### cleanup.sh

Deletes the resource group and all resources within it.

**Usage:**
```bash
./cleanup.sh [OPTIONS]

Options:
  -e, --environment ENV    Environment name (dev, staging, prod). Default: dev
  -r, --resource-group RG  Resource group name. Default: acme-mqtt-<environment>-rg
  -s, --subscription ID    Azure subscription ID (optional)
  -f, --force              Skip confirmation prompt
  -h, --help               Display help message
```

**Examples:**
```bash
# Delete development environment (with confirmation)
./cleanup.sh

# Force delete without confirmation
./cleanup.sh --environment dev --force

# Delete custom resource group
./cleanup.sh --resource-group my-custom-rg
```

## Bicep Templates

### main.bicep

The main template orchestrates the deployment of all resources. It uses modular approach with separate modules for each resource type.

**Parameters:**
- `location` - Azure region (default: resource group location)
- `environmentName` - Environment name: dev, staging, or prod (default: dev)
- `projectName` - Base name for resources (default: acme-mqtt)
- `eventGridNamespaceName` - Event Grid namespace name
- `storageAccountName` - Storage account name (must be globally unique)
- `functionAppName` - Function app name
- `eventGridTopicName` - Event Grid topic name
- `mqttClientId` - MQTT client ID (default: mqtt-proxy)

**Outputs:**
- `eventGridNamespaceName` - Name of the Event Grid namespace
- `eventGridNamespaceHostname` - MQTT broker hostname
- `storageAccountName` - Name of the storage account
- `functionAppName` - Name of the function app
- `eventGridTopicName` - Name of the Event Grid topic
- `eventGridTopicEndpoint` - Event Grid topic endpoint URL
- `resourceGroupName` - Name of the resource group

### Module Templates

Each module is responsible for a specific Azure resource:

1. **eventgrid-namespace.bicep** - Creates Event Grid namespace with:
   - MQTT broker enabled
   - MQTT client registration
   - Topic space for sensor data
   - Permission bindings for publish/subscribe

2. **storage-account.bicep** - Creates Storage Account with:
   - Standard LRS replication
   - Blob container for MQTT data
   - TLS 1.2 minimum version
   - 7-day blob retention policy

3. **function-app.bicep** - Creates Function App with:
   - Consumption (serverless) plan
   - Python 3.11 runtime
   - System-assigned managed identity
   - Storage Blob Data Contributor role

4. **eventgrid-topic.bicep** - Creates Event Grid Topic with:
   - Event Grid schema
   - Public network access

5. **eventgrid-subscription.bicep** - Creates Event Grid Subscription with:
   - Azure Function endpoint
   - Retry policy (30 attempts, 24h TTL)
   - Event filtering

## Parameters Files

Parameter files allow you to customize the deployment for different environments:

- `parameters.dev.json` - Development environment settings
- `parameters.prod.json` - Production environment settings

### Customizing Parameters

Edit the appropriate parameters file to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": {
      "value": "dev"
    },
    "projectName": {
      "value": "acme-mqtt"
    },
    "location": {
      "value": "westus2"
    },
    "mqttClientId": {
      "value": "mqtt-proxy"
    }
  }
}
```

## Manual Deployment

If you prefer to deploy manually using Azure CLI:

```bash
# Create resource group
az group create \
  --name acme-mqtt-dev-rg \
  --location westus2

# Deploy Bicep template
az deployment group create \
  --name acme-mqtt-deployment \
  --resource-group acme-mqtt-dev-rg \
  --template-file bicep/main.bicep \
  --parameters bicep/parameters.dev.json

# View deployment outputs
az deployment group show \
  --name acme-mqtt-deployment \
  --resource-group acme-mqtt-dev-rg \
  --query properties.outputs
```

## Post-Deployment Configuration

### 1. Generate MQTT Client SAS Token

```bash
az eventgrid namespace client generate-sas-token \
  --resource-group acme-mqtt-dev-rg \
  --namespace-name <namespace-name> \
  --client-name mqtt-proxy \
  --expiry-time-utc "2025-12-31T23:59:59Z"
```

### 2. Configure Function App Settings

The following settings are automatically configured during deployment:
- `AzureWebJobsStorage` - Storage connection string
- `BLOB_CONTAINER_NAME` - mqtt-data
- `FUNCTIONS_WORKER_RUNTIME` - python
- `FUNCTIONS_EXTENSION_VERSION` - ~4

### 3. Deploy Function Code

```bash
cd ../azure-function
func azure functionapp publish <function-app-name>
```

## Cost Considerations

The deployed infrastructure uses the following pricing tiers:

- **Event Grid Namespace**: Standard tier
- **Storage Account**: Standard LRS (Locally Redundant Storage)
- **Function App**: Consumption (pay-per-execution) plan
- **Event Grid Topic**: Basic tier

Estimated monthly costs (for development):
- Event Grid Namespace: ~$10-20
- Storage Account: ~$1-5 (depending on data volume)
- Function App: ~$0-5 (consumption plan, first 1M executions free)
- Event Grid Topic: ~$0-5

**Total estimated cost: $12-35/month for light development usage**

Production costs will vary based on:
- Number of MQTT connections
- Message volume
- Data retention requirements
- Geographic region

## Troubleshooting

### Deployment Fails

1. **Check Azure CLI version:**
   ```bash
   az --version
   ```
   Ensure you're using version 2.50.0 or later.

2. **Verify subscription permissions:**
   ```bash
   az account show
   ```
   Ensure you have Contributor or Owner role.

3. **Check resource name availability:**
   Storage account names must be globally unique. If deployment fails due to name conflict, modify the `storageAccountName` parameter.

4. **Review deployment logs:**
   ```bash
   az deployment group show \
     --name <deployment-name> \
     --resource-group <resource-group> \
     --query properties.error
   ```

### MQTT Connection Issues

1. **Verify MQTT client is registered:**
   ```bash
   az eventgrid namespace client show \
     --resource-group acme-mqtt-dev-rg \
     --namespace-name <namespace-name> \
     --client-name mqtt-proxy
   ```

2. **Check SAS token expiration:**
   Generate a new token if expired.

3. **Verify hostname format:**
   Should be: `<namespace>.<region>.ts.eventgrid.azure.net`

### Function App Issues

1. **Check function logs:**
   ```bash
   az functionapp log tail \
     --name <function-app-name> \
     --resource-group acme-mqtt-dev-rg
   ```

2. **Verify Event Grid subscription:**
   ```bash
   az eventgrid event-subscription list \
     --source-resource-id $(az eventgrid topic show \
       --name <topic-name> \
       --resource-group acme-mqtt-dev-rg \
       --query id -o tsv)
   ```

## Security Best Practices

1. **Use Managed Identities**: The Function App uses system-assigned managed identity to access Storage Account.

2. **Enable HTTPS Only**: All resources are configured with HTTPS/TLS encryption.

3. **Restrict Network Access**: Consider using Private Endpoints for production deployments.

4. **Rotate SAS Tokens**: Regularly regenerate MQTT client SAS tokens.

5. **Monitor Access**: Enable diagnostic logging for all resources.

6. **Use Azure Key Vault**: Store sensitive configuration values in Key Vault (optional enhancement).

## Support

For issues or questions:
1. Check the [main README](../README.md) for general project information
2. Review the [Azure Event Grid documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
3. Review the [Azure Functions documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)

## License

See [LICENSE](../LICENSE) file for details.
