# ACME MQTT Infrastructure as Code

This directory contains Infrastructure as Code (IaC) templates and scripts to provision Azure resources required for the ACME MQTT solution.

## Overview

The infrastructure consists of the following Azure resources:

| Resource | SKU / Tier | Purpose |
|---|---|---|
| **Event Grid Namespace** | Standard (1 CU) | MQTT broker for IoT device connectivity |
| **Storage Account** | Standard LRS | Blob storage for MQTT message data |
| **Function App** | Consumption (Y1) | Serverless event processing (pay-per-execution) |
| **Event Grid Topic** | Basic | Routes MQTT messages to the Function App |
| **Event Grid Subscription** | — | Connects the topic to the Function App (optional) |

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) v2.50.0+
- An active Azure subscription with Contributor/Owner role
- [Azure Functions Core Tools](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local) v4 (for deploying the function)

## Quick Start

### 1. Login to Azure

```bash
az login
az account set --subscription "<subscription-id>"
```

### 2. Deploy Infrastructure

**Bash:**
```bash
cd infra
chmod +x deploy.sh
./deploy.sh --environment dev --location australiaeast
```

**PowerShell:**
```powershell
cd infra
.\deploy.ps1 -Environment dev -Location australiaeast
```

To deploy into an existing resource group:

**Bash:**
```bash
./deploy.sh --environment dev --resource-group sandpit-todd --location australiaeast
```

**PowerShell:**
```powershell
.\deploy.ps1 -Environment dev -ResourceGroup sandpit-todd -Location australiaeast
```

### 3. Generate a SAS Token for MQTT Authentication

The `az eventgrid namespace` CLI commands require a preview extension that may not install cleanly. A PowerShell helper script is provided that calls the ARM REST API directly.

**PowerShell (recommended):**
```powershell
cd infra/bicep
.\generate-sas-mqtt.ps1
```

Edit the variables at the top of the script to match your deployment (resource group, namespace name, client name, expiry).

**Bash (using curl + REST API):**
```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TOKEN=$(az account get-access-token --query accessToken -o tsv)
RESOURCE_GROUP="sandpit-todd"
NAMESPACE_NAME="acme-mqtt-dev-egns"

# Fetch namespace shared key
KEY=$(curl -s -X POST \
  "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/namespaces/$NAMESPACE_NAME/listKeys?api-version=2024-06-01-preview" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | jq -r '.key1')

echo "Shared key retrieved. Use it to build a SAS token or pass it to your MQTT client."
```

> **Note:** The full SAS token construction in Bash requires HMAC-SHA256 signing. Use the PowerShell script or build the token in Python/Node if you need a complete SAS string from Bash.

### 4. Update the .env File

After generating the SAS token, update `.env` in the project root:

```env
EVENTGRID_MQTT_HOSTNAME=<namespace-name>.<region>-1.eventgrid.azure.net
MQTT_CLIENT_ID=mqtt-proxy
MQTT_USERNAME=mqtt-proxy
MQTT_PASSWORD=SharedAccessSignature sr=...
```

### 5. Deploy the Azure Function

**Bash / PowerShell:**
```bash
cd azure-function
func azure functionapp publish <function-app-name> --python
```

Replace `<function-app-name>` with the value from the deployment outputs (e.g. `acme-mqtt-dev-func-zie5`).

If you don't have `func` on your PATH:

| Platform | Install Command |
|---|---|
| Windows (winget) | `winget install Microsoft.Azure.FunctionsCoreTools` |
| macOS (brew) | `brew tap azure/functions && brew install azure-functions-core-tools@4` |
| npm | `npm install -g azure-functions-core-tools@4` |

> On Windows, if `func` is not found after install, add it to PATH: `$env:PATH += ";C:\Program Files\Microsoft\Azure Functions Core Tools"`

### 6. (Optional) Deploy the Event Grid Subscription

The Event Grid subscription that connects the topic to the Function App is **not** deployed by default — the function code must be published first.

**Bash:**
```bash
./deploy.sh --environment dev --resource-group sandpit-todd --location australiaeast
# When prompted, the same template is re-applied. Override the parameter:
# Or run directly:
az deployment group create \
  --resource-group sandpit-todd \
  --template-file bicep/main.bicep \
  --parameters bicep/parameters.dev.json \
  --parameters deployEventGridSubscription=true location=australiaeast
```

**PowerShell:**
```powershell
az deployment group create `
  --resource-group sandpit-todd `
  --template-file bicep/main.bicep `
  --parameters bicep/parameters.dev.json `
  --parameters deployEventGridSubscription=true location=australiaeast
```

### 7. Start On-Premises Services

```bash
docker-compose up -d
```

## Directory Structure

```
infra/
├── bicep/
│   ├── main.bicep                        # Main orchestration template
│   ├── parameters.dev.json               # Development parameters
│   ├── parameters.prod.json              # Production parameters
│   ├── generate-sas-mqtt.ps1             # SAS token generator (REST API)
│   └── modules/
│       ├── eventgrid-namespace.bicep     # Event Grid namespace + MQTT broker
│       ├── eventgrid-topic.bicep         # Event Grid topic
│       ├── eventgrid-subscription.bicep  # Event Grid subscription
│       ├── function-app.bicep            # Function App (Consumption plan)
│       └── storage-account.bicep         # Storage account
├── deploy.sh                             # Bash deployment script
├── deploy.ps1                            # PowerShell deployment script
├── cleanup.sh                            # Bash cleanup script
└── README.md                             # This file
```

## Deployment Scripts

### deploy.ps1 (PowerShell)

```
.\deploy.ps1 [OPTIONS]

  -Environment ENV       dev | staging | prod (default: dev)
  -ResourceGroup RG      Resource group name (default: acme-mqtt-<env>-rg)
  -Location LOC          Azure region (default: australiaeast)
  -SubscriptionId ID     Azure subscription ID
  -Help                  Display help
```

### deploy.sh (Bash)

```
./deploy.sh [OPTIONS]

  -e, --environment ENV    dev | staging | prod (default: dev)
  -r, --resource-group RG  Resource group name (default: acme-mqtt-<env>-rg)
  -l, --location LOC       Azure region (default: australiaeast)
  -s, --subscription ID    Azure subscription ID
  -h, --help               Display help
```

### cleanup.sh (Bash)

```
./cleanup.sh [OPTIONS]

  -e, --environment ENV    dev | staging | prod (default: dev)
  -r, --resource-group RG  Resource group name
  -s, --subscription ID    Azure subscription ID
  -f, --force              Skip confirmation prompt
  -h, --help               Display help
```

## Bicep Templates

### main.bicep

Orchestrates deployment of all modules.

**Key Parameters:**

| Parameter | Default | Description |
|---|---|---|
| `location` | resource group location | Azure region |
| `environmentName` | `dev` | Environment: dev, staging, prod |
| `projectName` | `acme-mqtt` | Base name for resources |
| `mqttClientId` | `mqtt-proxy` | MQTT client ID registered in Event Grid |
| `deployEventGridSubscription` | `false` | Deploy Event Grid subscription to Function App |

**Outputs:**

| Output | Description |
|---|---|
| `eventGridNamespaceName` | Event Grid namespace name |
| `eventGridNamespaceHostname` | MQTT broker hostname |
| `storageAccountName` | Storage account name |
| `functionAppName` | Function App name |
| `eventGridTopicName` | Event Grid topic name |
| `eventGridTopicEndpoint` | Topic endpoint URL |

### Module Details

1. **eventgrid-namespace.bicep** — Event Grid namespace with MQTT broker enabled, client registration with certificate authentication (`SubjectMatchesAuthenticationName`), topic space for `sensor/#`, and publish/subscribe permission bindings.

2. **storage-account.bicep** — Standard LRS storage with `mqtt-data` blob container, TLS 1.2 minimum, 7-day soft delete retention.

3. **function-app.bicep** — Linux Consumption plan (Y1/Dynamic), Python 3.11, system-assigned managed identity with Storage Blob Data Contributor role. Zero idle cost.

4. **eventgrid-topic.bicep** — Basic tier Event Grid topic with EventGridSchema.

5. **eventgrid-subscription.bicep** — Connects the topic to the Function App's `EventGridTrigger` endpoint with retry policy (30 attempts, 24h TTL).

## Cost Considerations

| Resource | Estimated Monthly Cost (Dev) |
|---|---|
| Event Grid Namespace (Standard, 1 CU, zone redundant) | ~$10–20 |
| Storage Account (Standard LRS) | ~$1–5 |
| Function App (Consumption — pay per execution) | ~$0–5 (first 1M free) |
| Event Grid Topic (Basic) | ~$0–5 |
| **Total** | **~$12–35/month** |

Cost-saving measures applied:
- Consumption plan (Y1) — zero cost when idle
- Standard LRS storage (cheapest replication)
- Basic tier Event Grid topic

## Troubleshooting

### Deployment Fails

```bash
# Check CLI version (need 2.50.0+)
az --version

# View deployment error details
az deployment group show \
  --name <deployment-name> \
  --resource-group <resource-group> \
  --query properties.error
```

### Permission Binding Name Error

Event Grid permission binding names only allow letters, numbers, and hyphens. If your `mqttClientId` contains underscores, the template automatically converts them with `replace(mqttClientId, '_', '-')`.

### MQTT Client Authentication Error

The Event Grid client resource requires `clientCertificateAuthentication` with a valid `validationScheme`, even when using SAS tokens. This is configured in the template as `SubjectMatchesAuthenticationName`.

### SAS Token Generation

The `az eventgrid namespace` CLI commands require a preview extension that has known pip install issues on Windows. Use the provided `generate-sas-mqtt.ps1` script instead, which calls the ARM REST API directly.

### Function App Deployment

If `func` is not recognised, add it to PATH:
```powershell
$env:PATH += ";C:\Program Files\Microsoft\Azure Functions Core Tools"
```

### Function App Logs

```bash
az functionapp log tail \
  --name <function-app-name> \
  --resource-group <resource-group>
```

## Security Best Practices

- **Managed Identity** — Function App uses system-assigned identity for storage access
- **HTTPS Only** — All resources enforce TLS/HTTPS
- **FTPS Disabled** — FTP access is disabled on the Function App
- **TLS 1.2** — Minimum version enforced on storage and function app
- **Rotate SAS Tokens** — Regenerate MQTT client tokens periodically
- **Private Endpoints** — Consider adding for production deployments

## License

See [LICENSE](../LICENSE) file for details.
