#!/bin/bash
# Azure Infrastructure Deployment Script
# This script deploys the ACME MQTT infrastructure using Azure CLI and Bicep

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if required commands are available
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI (az) is not installed. Please install it first."
        log_error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    log_info "Prerequisites check passed."
}

# Function to check Azure login status
check_azure_login() {
    log_info "Checking Azure login status..."
    
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    local account_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log_info "Logged in to Azure account: $account_name"
    log_info "Subscription ID: $subscription_id"
}

# Display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy ACME MQTT Azure infrastructure using Bicep templates"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV    Environment name (dev, staging, prod). Default: dev"
    echo "  -r, --resource-group RG  Resource group name. Default: acme-mqtt-<environment>-rg"
    echo "  -l, --location LOC       Azure region. Default: westus2"
    echo "  -s, --subscription ID    Azure subscription ID (optional)"
    echo "  -h, --help               Display this help message"
    echo ""
    echo "Example:"
    echo "  $0 --environment dev --resource-group my-rg --location eastus"
    exit 0
}

# Default values
ENVIRONMENT="dev"
LOCATION="westus2"
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, prod"
    exit 1
fi

# Set default resource group if not provided
if [ -z "$RESOURCE_GROUP" ]; then
    RESOURCE_GROUP="acme-mqtt-${ENVIRONMENT}-rg"
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BICEP_DIR="$SCRIPT_DIR/bicep"
PARAMETERS_FILE="$BICEP_DIR/parameters.${ENVIRONMENT}.json"

# Verify Bicep files exist
if [ ! -f "$BICEP_DIR/main.bicep" ]; then
    log_error "Main Bicep template not found at: $BICEP_DIR/main.bicep"
    exit 1
fi

if [ ! -f "$PARAMETERS_FILE" ]; then
    log_warning "Parameters file not found: $PARAMETERS_FILE"
    log_warning "Using default values from main.bicep"
    PARAMETERS_FILE=""
fi

# Check prerequisites
check_prerequisites
check_azure_login

# Set subscription if provided
if [ -n "$SUBSCRIPTION_ID" ]; then
    log_info "Setting Azure subscription to: $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Display deployment information
echo ""
log_info "==================================="
log_info "ACME MQTT Infrastructure Deployment"
log_info "==================================="
log_info "Environment: $ENVIRONMENT"
log_info "Resource Group: $RESOURCE_GROUP"
log_info "Location: $LOCATION"
log_info "Bicep Template: $BICEP_DIR/main.bicep"
if [ -n "$PARAMETERS_FILE" ]; then
    log_info "Parameters File: $PARAMETERS_FILE"
fi
echo ""

# Prompt for confirmation
read -p "Do you want to proceed with the deployment? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    log_info "Deployment cancelled."
    exit 0
fi

# Create resource group
log_info "Creating resource group: $RESOURCE_GROUP..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags environment="$ENVIRONMENT" project="acme-mqtt" managedBy="bicep" \
    --output table

# Deploy Bicep template
log_info "Deploying Bicep template..."
DEPLOYMENT_NAME="acme-mqtt-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S)"

if [ -n "$PARAMETERS_FILE" ]; then
    az deployment group create \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$BICEP_DIR/main.bicep" \
        --parameters "$PARAMETERS_FILE" \
        --parameters location="$LOCATION" \
        --output table
else
    az deployment group create \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$BICEP_DIR/main.bicep" \
        --parameters environmentName="$ENVIRONMENT" location="$LOCATION" \
        --output table
fi

# Check deployment status
if [ $? -eq 0 ]; then
    log_info "Deployment completed successfully!"
    echo ""
    
    # Get outputs
    log_info "Retrieving deployment outputs..."
    OUTPUTS=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.outputs \
        --output json)
    
    # Extract key values
    EVENTGRID_HOSTNAME=$(echo "$OUTPUTS" | jq -r '.eventGridNamespaceHostname.value // empty')
    FUNCTION_APP_NAME=$(echo "$OUTPUTS" | jq -r '.functionAppName.value // empty')
    STORAGE_ACCOUNT_NAME=$(echo "$OUTPUTS" | jq -r '.storageAccountName.value // empty')
    EVENTGRID_TOPIC_NAME=$(echo "$OUTPUTS" | jq -r '.eventGridTopicName.value // empty')
    
    # Display outputs
    echo ""
    log_info "==================================="
    log_info "Deployment Outputs"
    log_info "==================================="
    log_info "Resource Group: $RESOURCE_GROUP"
    
    if [ -n "$EVENTGRID_HOSTNAME" ]; then
        log_info "Event Grid MQTT Hostname: $EVENTGRID_HOSTNAME"
    fi
    
    if [ -n "$FUNCTION_APP_NAME" ]; then
        log_info "Function App Name: $FUNCTION_APP_NAME"
    fi
    
    if [ -n "$STORAGE_ACCOUNT_NAME" ]; then
        log_info "Storage Account Name: $STORAGE_ACCOUNT_NAME"
    fi
    
    if [ -n "$EVENTGRID_TOPIC_NAME" ]; then
        log_info "Event Grid Topic Name: $EVENTGRID_TOPIC_NAME"
    fi
    
    echo ""
    log_info "==================================="
    log_info "Next Steps"
    log_info "==================================="
    log_info "1. Generate a SAS token for MQTT client authentication:"
    log_info "   az eventgrid namespace client generate-sas-token \\"
    log_info "     --resource-group $RESOURCE_GROUP \\"
    log_info "     --namespace-name \$(az eventgrid namespace list -g $RESOURCE_GROUP --query '[0].name' -o tsv) \\"
    log_info "     --client-name mqtt-proxy \\"
    log_info "     --expiry-time-utc \"2025-12-31T23:59:59Z\""
    echo ""
    log_info "2. Update your .env file with the following values:"
    log_info "   EVENTGRID_MQTT_HOSTNAME=$EVENTGRID_HOSTNAME"
    log_info "   MQTT_CLIENT_ID=mqtt-proxy"
    log_info "   MQTT_USERNAME=mqtt-proxy"
    log_info "   MQTT_PASSWORD=<sas-token-from-step-1>"
    echo ""
    log_info "3. Deploy the Azure Function:"
    log_info "   cd azure-function"
    log_info "   func azure functionapp publish $FUNCTION_APP_NAME"
    echo ""
    log_info "4. Start the on-premises services:"
    log_info "   docker-compose up -d"
    echo ""
    
else
    log_error "Deployment failed. Please check the error messages above."
    exit 1
fi
