#!/bin/bash

# AWS Ubuntu Server Creation Script for CloudNativePG Lab
# This script creates an EC2 instance with Ubuntu 25.04 on ARM64 architecture

set -e

# Check requirements
command -v aws &> /dev/null || { echo "❌ AWS CLI not found. Install: curl -fsSL https://awscli.amazonaws.com/install.sh | bash"; exit 1; }
aws sts get-caller-identity &> /dev/null || { echo "❌ 'aws sts get-caller-identity' failed. AWS CLI configured? Run: aws configure"; exit 1; }

echo "=== AWS Ubuntu Server Setup for CloudNativePG Lab ==="
echo

echo "⚠️  WARNING: This script will modify the default security group to open SSH (port 22) and RDP (port 3389) to all IP addresses (0.0.0.0/0)."
echo "   This may affect other instances using the same security group."
echo
echo "   Press Ctrl-C at any time to cancel the setup."
echo

# Prompt for variables with defaults
read -p "Enter AWS region [us-west-2]: " REGION
REGION=${REGION:-us-west-2}

read -p "Enter instance name [cnpg1]: " INSTANCE_NAME
INSTANCE_NAME=${INSTANCE_NAME:-cnpg1}

read -p "Enter key pair name [default-keypair]: " KEY_NAME
KEY_NAME=${KEY_NAME:-default-keypair}

read -p "Enter instance type [m6g.xlarge]: " INSTANCE_TYPE
INSTANCE_TYPE=${INSTANCE_TYPE:-m6g.xlarge}

read -p "Use ARM64 architecture? (Y/n): " USE_ARM64
USE_ARM64=${USE_ARM64:-y}

read -p "Enter disk size in GB [100]: " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-100}

echo
echo "Configuration:"
echo "  Region: $REGION"
echo "  Instance Name: $INSTANCE_NAME"
echo "  Key Pair: $KEY_NAME"
echo "  Instance Type: $INSTANCE_TYPE"
echo "  Architecture: $([ "$USE_ARM64" = "y" ] && echo "ARM64" || echo "x86_64")"
echo "  Disk Size: ${DISK_SIZE}GB"
echo

read -p "Continue with these settings? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 1
fi

echo
if [[ "$USE_ARM64" = "y" ]]; then
    echo "Getting latest Ubuntu 25.04 ARM64 AMI..."
    AMI_ID=$(aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/25.04/stable/current/arm64/hvm/ebs-gp3/ami-id --region $REGION --query 'Parameters[0].Value' --output text)
else
    echo "Getting latest Ubuntu 25.04 x86_64 AMI..."
    AMI_ID=$(aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/25.04/stable/current/amd64/hvm/ebs-gp3/ami-id --region $REGION --query 'Parameters[0].Value' --output text)
fi
echo "AMI ID: $AMI_ID"

echo
echo "Creating EC2 instance..."
aws ec2 run-instances --instance-type $INSTANCE_TYPE --image-id $AMI_ID \
    --region $REGION --monitoring Enabled=true --key-name $KEY_NAME \
    --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$DISK_SIZE,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --output text

echo
echo "Waiting for instance to be running..."
aws ec2 wait instance-running --region $REGION --filters "Name=tag:Name,Values=$INSTANCE_NAME"

echo
echo "Checking if SSH port (22) is open..."
SSH_OPEN=$(aws ec2 describe-security-groups --region $REGION --group-names default --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]' --output text)

if [[ -z "$SSH_OPEN" ]]; then
    echo "Opening SSH port (22)..."
    aws ec2 authorize-security-group-ingress \
        --region $REGION \
        --group-name default \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --output text
else
    echo "SSH port (22) is already open."
fi

echo
echo "Checking if RDP port (3389) is open..."
RDP_OPEN=$(aws ec2 describe-security-groups --region $REGION --group-names default --query 'SecurityGroups[0].IpPermissions[?FromPort==`3389`]' --output text)

if [[ -z "$RDP_OPEN" ]]; then
    echo "Opening RDP port (3389)..."
    aws ec2 authorize-security-group-ingress \
        --region $REGION \
        --group-name default \
        --protocol tcp \
        --port 3389 \
        --cidr 0.0.0.0/0 \
        --output text
else
    echo "RDP port (3389) is already open."
fi

echo
echo "Getting public IP address..."
PUBLIC_IP=$(aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo
echo "=== Setup Complete! ==="
echo
echo "Instance Details:"
echo "  Name: $INSTANCE_NAME"
echo "  Public IP: $PUBLIC_IP"
echo "  Region: $REGION"
echo
echo "Connection Commands:"
echo "  SSH: ssh ubuntu@$PUBLIC_IP"
echo "  RDP: Use your RDP client to connect to $PUBLIC_IP:3389"
echo
echo "To clean up later, run: bash scripts/aws-teardown.sh"