#!/bin/bash

# AWS Ubuntu Server Cleanup Script for CloudNativePG Lab
# This script terminates an EC2 instance and cleans up associated resources

set -e

# Check requirements
command -v aws &> /dev/null || { echo "❌ AWS CLI not found. Install: curl -fsSL https://awscli.amazonaws.com/install.sh | bash"; exit 1; }
aws sts get-caller-identity &> /dev/null || { echo "❌ 'aws sts get-caller-identity' failed. AWS CLI configured? Run: aws configure"; exit 1; }

echo "=== AWS Ubuntu Server Cleanup for CloudNativePG Lab ==="
echo

# Prompt for variables with defaults
read -p "Enter AWS region [us-west-2]: " REGION
REGION=${REGION:-us-west-2}

read -p "Enter instance name [cnpg1]: " INSTANCE_NAME
INSTANCE_NAME=${INSTANCE_NAME:-cnpg1}

echo
echo "Configuration:"
echo "  Region: $REGION"
echo "  Instance Name: $INSTANCE_NAME"
echo

echo
echo "Getting instance ID by name tag..."
INSTANCE_ID=$(aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text)

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
    echo "No instance found with name '$INSTANCE_NAME' in region '$REGION'"
    exit 1
fi

echo "Instance ID: $INSTANCE_ID"

read -p "Continue with cleanup? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 1
fi

echo
echo "Terminating instance (this will also delete the EBS volume due to DeleteOnTermination=true)..."
aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCE_ID --output text

echo
echo "Waiting for instance to be terminated..."
aws ec2 wait instance-terminated --region $REGION --instance-ids $INSTANCE_ID

echo
echo "=== Cleanup Complete! ==="
echo "Instance '$INSTANCE_NAME' has been terminated and all associated resources cleaned up."