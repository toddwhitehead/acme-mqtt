#!/bin/bash
# Azure Infrastructure Cleanup Script
# This script removes all Azure resources created for ACME MQTT

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
    echo "Clean up ACME MQTT Azure infrastructure"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV    Environment name (dev, staging, prod). Default: dev"
    echo "  -r, --resource-group RG  Resource group name. Default: acme-mqtt-<environment>-rg"
    echo "  -s, --subscription ID    Azure subscription ID (optional)"
    echo "  -f, --force              Skip confirmation prompt"
    echo "  -h, --help               Display this help message"
    echo ""
    echo "Example:"
    echo "  $0 --environment dev --resource-group my-rg"
    exit 0
}

# Default values
ENVIRONMENT="dev"
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
FORCE=false

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
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
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

# Check prerequisites
check_prerequisites
check_azure_login

# Set subscription if provided
if [ -n "$SUBSCRIPTION_ID" ]; then
    log_info "Setting Azure subscription to: $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Check if resource group exists
log_info "Checking if resource group exists: $RESOURCE_GROUP"
if ! az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
    log_error "Resource group '$RESOURCE_GROUP' does not exist."
    exit 1
fi

# List resources in the resource group
log_info "Resources in '$RESOURCE_GROUP':"
az resource list --resource-group "$RESOURCE_GROUP" --output table

echo ""
log_warning "==================================="
log_warning "DESTRUCTIVE OPERATION WARNING"
log_warning "==================================="
log_warning "This will DELETE the following:"
log_warning "- Resource Group: $RESOURCE_GROUP"
log_warning "- All resources within the resource group"
log_warning "- All data stored in the resources (Storage Accounts, etc.)"
echo ""
log_warning "This action CANNOT be undone!"
echo ""

# Prompt for confirmation unless --force is used
if [ "$FORCE" = false ]; then
    read -p "Type 'DELETE' to confirm deletion of resource group '$RESOURCE_GROUP': " -r
    echo
    if [[ ! $REPLY == "DELETE" ]]; then
        log_info "Cleanup cancelled."
        exit 0
    fi
fi

# Delete resource group
log_info "Deleting resource group: $RESOURCE_GROUP..."
log_warning "This may take several minutes..."

az group delete \
    --name "$RESOURCE_GROUP" \
    --yes \
    --no-wait

log_info "Resource group deletion initiated: $RESOURCE_GROUP"
log_info "Deletion is running in the background."
log_info "You can check the status with:"
log_info "  az group show --name $RESOURCE_GROUP"
echo ""
log_info "Cleanup process started successfully."
