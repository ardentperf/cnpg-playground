#!/bin/bash

# Azure Ubuntu Server Cleanup Script for CloudNativePG Lab
# This script deletes a VM and all associated resources

set -e

# Check requirements
command -v az &> /dev/null || { echo "❌ Azure CLI not found. Install: curl -fsSL https://aka.ms/InstallAzureCLIDeb | bash"; exit 1; }
az account show &> /dev/null || { echo "❌ 'az account show' failed. Azure CLI logged in? Run: az login"; exit 1; }

echo "=== Azure Ubuntu Server Cleanup for CloudNativePG Lab ==="
echo

# Prompt for variables with defaults
read -p "Enter resource group name [cnpg1]: " RESOURCE_GROUP
RESOURCE_GROUP=${RESOURCE_GROUP:-cnpg1}

echo
echo "Configuration:"
echo "  Resource Group: $RESOURCE_GROUP"
echo

echo
echo "Checking if resource group exists..."
if ! az group show --name $RESOURCE_GROUP >/dev/null 2>&1; then
    echo "Resource group '$RESOURCE_GROUP' does not exist."
    exit 1
fi

echo
echo "Listing resources in resource group '$RESOURCE_GROUP':"
echo "=================================================="
az resource list --resource-group $RESOURCE_GROUP --output table
echo

read -p "Continue with cleanup? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."

    exit 1
fi
echo
echo "Deleting resource group (this will delete the VM and all associated resources)..."
az group delete --name $RESOURCE_GROUP --yes --output tsv

echo
echo "=== Cleanup Complete! ==="
echo "Resource group '$RESOURCE_GROUP' and all associated resources have been deleted."