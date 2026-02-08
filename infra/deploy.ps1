# Azure Infrastructure Deployment Script
# This script deploys the ACME MQTT infrastructure using Azure CLI and Bicep
# Supports both command-line parameters and environment variables for configuration

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$Location = "australiaeast",

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# Colors for output
$RED = "Red"
$GREEN = "Green"
$YELLOW = "Yellow"
$NC = "White"  # Default color

# Function to print colored messages
function Write-LogInfo {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $GREEN
}

function Write-LogError {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $RED
}

function Write-LogWarning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $YELLOW
}

# Function to display usage information
function Show-Usage {
    $scriptName = Split-Path -Leaf $MyInvocation.PSCommandPath
    Write-Host "Usage: $scriptName [OPTIONS]"
    Write-Host ""
    Write-Host "Deploy ACME MQTT Azure infrastructure using Bicep templates"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Environment ENV       Environment name (dev, staging, prod). Default: dev"
    Write-Host "  -ResourceGroup RG      Resource group name. Default: acme-mqtt-<environment>-rg"
    Write-Host "  -Location LOC          Azure region. Default: australiaeast"
    Write-Host "  -SubscriptionId ID     Azure subscription ID (optional)"
    Write-Host "  -Help                  Display this help message"
    Write-Host ""
    Write-Host "Note: Event Grid subscription is not deployed by default."
    Write-Host "      Deploy it separately after function code is published."
    Write-Host ""
    Write-Host "Environment Variables:"
    Write-Host "  AZURE_SUBSCRIPTION_ID  Azure subscription ID (alternative to -SubscriptionId)"
    Write-Host "  SUBSCRIPTION_ID        Azure subscription ID (alternative to -SubscriptionId)"
    Write-Host "  AZURE_RESOURCE_GROUP   Resource group name (alternative to -ResourceGroup)"
    Write-Host "  RESOURCE_GROUP         Resource group name (alternative to -ResourceGroup)"
    Write-Host ""
    Write-Host "Example:"
    Write-Host "  $scriptName -Environment dev -ResourceGroup my-rg -Location eastus"
    Write-Host "  # Or using environment variables:"
    Write-Host "  `$env:AZURE_SUBSCRIPTION_ID = '12345678-1234-1234-1234-123456789012'"
    Write-Host "  `$env:AZURE_RESOURCE_GROUP = 'my-resource-group'"
    Write-Host "  $scriptName -Environment dev"
    exit 0
}

# Display help if requested
if ($Help) {
    Show-Usage
}

# Function to check if required commands are available
function Test-Prerequisites {
    Write-LogInfo "Checking prerequisites..."

    if (!(Get-Command az -ErrorAction SilentlyContinue)) {
        Write-LogError "Azure CLI (az) is not installed. Please install it first."
        Write-LogError "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    }

    Write-LogInfo "Prerequisites check passed."
}

# Function to check Azure login status
function Test-AzureLogin {
    Write-LogInfo "Checking Azure login status..."

    try {
        $account = az account show 2>$null | ConvertFrom-Json
        $accountName = $account.name
        $subscriptionId = $account.id
        Write-LogInfo "Logged in to Azure account: $accountName"
        Write-LogInfo "Subscription ID: $subscriptionId"
    }
    catch {
        Write-LogError "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    }
}

# Check for environment variables if parameters not provided
if ([string]::IsNullOrEmpty($SubscriptionId)) {
    $SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
    if ([string]::IsNullOrEmpty($SubscriptionId)) {
        $SubscriptionId = $env:SUBSCRIPTION_ID
    }
}

if ([string]::IsNullOrEmpty($ResourceGroup)) {
    $ResourceGroup = $env:AZURE_RESOURCE_GROUP
    if ([string]::IsNullOrEmpty($ResourceGroup)) {
        $ResourceGroup = $env:RESOURCE_GROUP
    }
}

# Set default resource group if not provided
if ([string]::IsNullOrEmpty($ResourceGroup)) {
    $ResourceGroup = "acme-mqtt-${Environment}-rg"
}

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BicepDir = Join-Path $ScriptDir "bicep"
$ParametersFile = Join-Path $BicepDir "parameters.${Environment}.json"

# Verify Bicep files exist
if (!(Test-Path (Join-Path $BicepDir "main.bicep"))) {
    Write-LogError "Main Bicep template not found at: $(Join-Path $BicepDir 'main.bicep')"
    exit 1
}

if (!(Test-Path $ParametersFile)) {
    Write-LogWarning "Parameters file not found: $ParametersFile"
    Write-LogWarning "Using default values from main.bicep"
    $ParametersFile = $null
}

# Check prerequisites
Test-Prerequisites
Test-AzureLogin

# Set subscription if provided
if ($SubscriptionId) {
    Write-LogInfo "Setting Azure subscription to: $SubscriptionId"
    az account set --subscription $SubscriptionId
}

# Display deployment information
Write-Host ""
Write-LogInfo "==================================="
Write-LogInfo "ACME MQTT Infrastructure Deployment"
Write-LogInfo "==================================="
Write-LogInfo "Environment: $Environment"
Write-LogInfo "Resource Group: $ResourceGroup"
Write-LogInfo "Location: $Location"
Write-LogInfo "Bicep Template: $(Join-Path $BicepDir 'main.bicep')"
if ($ParametersFile) {
    Write-LogInfo "Parameters File: $ParametersFile"
}
Write-Host ""

# Prompt for confirmation
$confirmation = Read-Host "Do you want to proceed with the deployment? (yes/no)"
if ($confirmation -notmatch "^[Yy]es$") {
    Write-LogInfo "Deployment cancelled."
    exit 0
}

# Create resource group
Write-LogInfo "Creating resource group: $ResourceGroup..."
az group create `
    --name $ResourceGroup `
    --location $Location `
    --tags environment=$Environment project="acme-mqtt" managedBy="bicep" `
    --output table

# Deploy Bicep template
Write-LogInfo "Deploying Bicep template..."
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$DeploymentName = "acme-mqtt-${Environment}-$timestamp"

if ($ParametersFile) {
    az deployment group create `
        --name $DeploymentName `
        --resource-group $ResourceGroup `
        --template-file (Join-Path $BicepDir "main.bicep") `
        --parameters $ParametersFile `
        --parameters location=$Location `
        --output table
}
else {
    az deployment group create `
        --name $DeploymentName `
        --resource-group $ResourceGroup `
        --template-file (Join-Path $BicepDir "main.bicep") `
        --parameters environmentName=$Environment location=$Location `
        --output table
}

# Check deployment status
if ($LASTEXITCODE -eq 0) {
    Write-LogInfo "Deployment completed successfully!"
    Write-Host ""

    # Get outputs
    Write-LogInfo "Retrieving deployment outputs..."
    $outputsJson = az deployment group show `
        --name $DeploymentName `
        --resource-group $ResourceGroup `
        --query properties.outputs `
        --output json

    $outputs = $outputsJson | ConvertFrom-Json

    # Extract key values
    $eventGridHostname = $outputs.eventGridNamespaceHostname.value
    $functionAppName = $outputs.functionAppName.value
    $storageAccountName = $outputs.storageAccountName.value
    $eventGridTopicName = $outputs.eventGridTopicName.value

    # Display outputs
    Write-Host ""
    Write-LogInfo "==================================="
    Write-LogInfo "Deployment Outputs"
    Write-LogInfo "==================================="
    Write-LogInfo "Resource Group: $ResourceGroup"

    if ($eventGridHostname) {
        Write-LogInfo "Event Grid MQTT Hostname: $eventGridHostname"
    }

    if ($functionAppName) {
        Write-LogInfo "Function App Name: $functionAppName"
    }

    if ($storageAccountName) {
        Write-LogInfo "Storage Account Name: $storageAccountName"
    }

    if ($eventGridTopicName) {
        Write-LogInfo "Event Grid Topic Name: $eventGridTopicName"
    }

    Write-Host ""
    Write-LogInfo "==================================="
    Write-LogInfo "Next Steps"
    Write-LogInfo "==================================="
    Write-LogInfo "1. Generate a SAS token for MQTT client authentication:"
    Write-LogInfo "   cd bicep; .\generate-sas-mqtt.ps1"
    Write-LogInfo "   (Update the script variables if your resource group or namespace name differs)"
    Write-Host ""
    Write-LogInfo "2. Update your .env file with the following values:"
    Write-LogInfo "   EVENTGRID_MQTT_HOSTNAME=$eventGridHostname"
    Write-LogInfo "   MQTT_CLIENT_ID=mqtt-proxy"
    Write-LogInfo "   MQTT_USERNAME=mqtt-proxy"
    Write-LogInfo "   MQTT_PASSWORD=<sas-token-from-step-1>"
    Write-Host ""
    Write-LogInfo "3. Deploy the Azure Function:"
    Write-LogInfo "   cd azure-function"
    Write-LogInfo "   func azure functionapp publish $functionAppName"
    Write-Host ""
    Write-LogInfo "4. Deploy the Event Grid subscription (after function code is deployed):"
    Write-LogInfo "   # Update parameters.dev.json to set deployEventGridSubscription to true"
    Write-LogInfo "   # Or redeploy with parameter: --parameters deployEventGridSubscription=true"
    Write-Host ""
    Write-LogInfo "5. Start the on-premises services:"
    Write-LogInfo "   docker-compose up -d"
    Write-Host ""

}
else {
    Write-LogError "Deployment failed. Please check the error messages above."
    exit 1
}