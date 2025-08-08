#!/bin/bash

# Azure Ubuntu Server Creation Script for CloudNativePG Lab
# This script creates a VM with Ubuntu 25.04 on ARM64 architecture

set -e

# Check requirements
command -v az &> /dev/null || { echo "❌ Azure CLI not found. Install: curl -fsSL https://aka.ms/InstallAzureCLIDeb | bash"; exit 1; }
az account show &> /dev/null || { echo "❌ 'az account show' failed. Azure CLI logged in? Run: az login"; exit 1; }

echo "=== Azure Ubuntu Server Setup for CloudNativePG Lab ==="
echo

# Prompt for variables with defaults
read -p "Enter Azure location [westus2]: " LOCATION
LOCATION=${LOCATION:-westus2}

read -p "Enter resource group name [cnpg1]: " RESOURCE_GROUP
RESOURCE_GROUP=${RESOURCE_GROUP:-cnpg1}

read -p "Enter VM name [${RESOURCE_GROUP}vm]: " VM_NAME
VM_NAME=${VM_NAME:-${RESOURCE_GROUP}vm}

read -p "Enter VM size [Standard_D4ps_v6]: " VM_SIZE
VM_SIZE=${VM_SIZE:-Standard_D4ps_v6}

read -p "Use ARM64 architecture? (Y/n): " USE_ARM64
USE_ARM64=${USE_ARM64:-Y}

if [[ $USE_ARM64 =~ ^[Yy]$ ]]; then
    ARCHITECTURE="arm64"
else
    ARCHITECTURE="x86_64"
fi

read -p "Enter disk size in GB [100]: " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-100}

echo
echo "Configuration:"
echo "  Location: $LOCATION"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  VM Name: $VM_NAME"
echo "  VM Size: $VM_SIZE"
echo "  Architecture: $ARCHITECTURE"
echo "  Disk Size: ${DISK_SIZE}GB"
echo

read -p "Continue with these settings? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 1
fi

echo
echo "Checking if resource group '$RESOURCE_GROUP' already exists..."
EXISTING_RG=$(az group show --name $RESOURCE_GROUP --query 'name' --output tsv 2>/dev/null || echo "")

if [[ "$EXISTING_RG" != "" ]]; then
    echo "❌ Error: Resource group '$RESOURCE_GROUP' already exists"
    echo "Please choose a different resource group name."
    exit 1
fi

echo "✅ No existing resource group found with name '$RESOURCE_GROUP'"

echo
echo "Creating resource group..."
az group create --name $RESOURCE_GROUP --location $LOCATION --output tsv

echo
echo "Creating VM..."

# Set image based on architecture
if [[ "$ARCHITECTURE" == "arm64" ]]; then
    IMAGE="Canonical:ubuntu-25_04:server-arm64:latest"
else
    IMAGE="Canonical:ubuntu-25_04:server:latest"
fi

az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --location $LOCATION \
  --size $VM_SIZE \
  --image $IMAGE \
  --admin-username ubuntu \
  --generate-ssh-keys \
  --os-disk-size-gb $DISK_SIZE \
  --storage-sku Standard_LRS \
  --public-ip-address ${VM_NAME}PublicIP \
  --output tsv

echo
echo "Opening RDP port (3389) for remote desktop access..."
az vm open-port \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --port 3389 \
  --output tsv

echo
echo "Getting IP addresses..."
az vm list-ip-addresses --resource-group $RESOURCE_GROUP --output table

echo
echo "Getting public IP address..."
PUBLIC_IP=$(az vm show --name $VM_NAME --resource-group $RESOURCE_GROUP --show-details --query "publicIps" --output tsv)

echo
echo "=== Setup Complete! ==="
echo
echo "VM Details:"
echo "  Name: $VM_NAME"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Public IP: $PUBLIC_IP"
echo "  Location: $LOCATION"
echo
echo "Connection Commands:"
echo "  SSH: ssh ubuntu@$PUBLIC_IP"
echo "  RDP: Use your RDP client to connect to $PUBLIC_IP:3389"
echo
echo "Next steps:"
echo "  ssh ubuntu@$PUBLIC_IP git clone https://github.com/ardentperf/cnpg-playground"
echo "  ssh ubuntu@$PUBLIC_IP bash -c \"echo && cd cnpg-playground && git checkout tmp-work\""
echo "  ssh -t ubuntu@$PUBLIC_IP bash cnpg-playground/lab/install.sh"
echo
read -p "Would you like to automatically run these next steps? (y/N): " RUN_NEXT_STEPS
if [[ $RUN_NEXT_STEPS =~ ^[Yy]$ ]]; then
    echo "Cloning repository..."
    ssh ubuntu@$PUBLIC_IP git clone https://github.com/ardentperf/cnpg-playground

    echo "Checking out tmp-work branch..."
    ssh ubuntu@$PUBLIC_IP bash -c "echo && cd cnpg-playground && git checkout tmp-work"

    echo "Running lab installation..."
    ssh -t ubuntu@$PUBLIC_IP bash cnpg-playground/lab/install.sh
fi
echo
echo "To clean up later, run: bash scripts/azure-teardown.sh"