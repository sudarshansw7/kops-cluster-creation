#!/bin/bash
echo "Kops installation is started......"
sleep 4
curl -LO https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
chmod +x kops-linux-amd64
sudo mv kops-linux-amd64 /usr/local/bin/kops
echo "Kops installation is sucessfull"
sleep 4

echo "Kubectl installation is started......"
sleep 4
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
echo "Kubectl installation is sucessfull"
sleep 4

echo "creation of S3 bucket is started......"
sleep 4
AWS_REGION="us-east-1"
KOPS_CLUSTER_NAME="mykopsbucket.in"

# Create S3 bucket
BUCKET_NAME="mykopsbucket.in.k8s"

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "Bucket $BUCKET_NAME already exists."
else
    aws s3 mb "s3://$BUCKET_NAME"
    echo "Bucket $BUCKET_NAME created."
fi

sleep 4
echo "Creating private hosted zone in Route 53..."
sleep 4

# Get the name of the oldest S3 bucket
BUCKET_NAME=$(aws s3 ls 2>/dev/null | awk '{print $3}' | head -n 1)

# Get the default VPC ID
VPC_ID=$(aws ec2 describe-vpcs \
    --filters Name=isDefault,Values=true \
    --query "Vpcs[0].VpcId" \
    --output text)

aws configure set region us-east-1
AWS_REGION=$(aws configure get region)


# If AWS_REGION is empty, try getting it from instance metadata (for EC2 instances)
if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
fi

# If still empty, prompt an error and exit
if [[ -z "$AWS_REGION" ]]; then
    echo "Error: AWS region is not set. Configure it using 'aws configure set region <your-region>'"
    exit 1
fi

# Ensure all variables are set before proceeding
if [[ -z "$BUCKET_NAME" || -z "$VPC_ID" || -z "$AWS_REGION" ]]; then
    echo "Error: One or more required values are missing."
    echo "BUCKET_NAME: $BUCKET_NAME"
    echo "VPC_ID: $VPC_ID"
    echo "AWS_REGION: $AWS_REGION"
    exit 1
fi

# Create Route 53 private hosted zone
CLUSTER_NAME="mykopsbucket.in"
aws route53 create-hosted-zone \
    --name "$CLUSTER_NAME" \
    --vpc VPCId="$VPC_ID",VPCRegion="$AWS_REGION" \
    --caller-reference "$(date +%s)" \
    --hosted-zone-config PrivateZone=true
echo "creation of Private hosted zone is sucessfull"
sleep 4
echo "export variables to bashrc"
sleep 4
# Define cluster name and state store bucket
CLUSTER_NAME="mykopsbucket.in"
STATE_STORE="s3:CLUSTER_NAME="mykopsbucket.in"
//mykopsbucket.in.k8s"

# Check if variables already exist in .bashrc
grep -q "export KOPS_CLUSTER_NAME=" ~/.bashrc && sed -i "/export KOPS_CLUSTER_NAME=/c\export KOPS_CLUSTER_NAME=$CLUSTER_NAME" ~/.bashrc || echo "export KOPS_CLUSTER_NAME=$CLUSTER_NAME" >> ~/.bashrc
grep -q "export KOPS_STATE_STORE=" ~/.bashrc && sed -i "/export KOPS_STATE_STORE=/c\export KOPS_STATE_STORE=$STATE_STORE" ~/.bashrc || echo "export KOPS_STATE_STORE=$STATE_STORE" >> ~/.bashrc

# Reload .bashrc
source ~/.bashrc

echo "Updated ~/.bashrc with KOPS_CLUSTER_NAME and KOPS_STATE_STORE"
sleep 4

echo "Generation of ssh-keys started"
sleep 4
KEY_PATH="$HOME/.ssh/id_rsa"

if [ -f "$KEY_PATH" ]; then
    echo "SSH key already exists at $KEY_PATH"
else
    ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N ""
    chmod 600 "$KEY_PATH"
    chmod 644 "$KEY_PATH.pub"
    echo "SSH key generated successfully!"
fi

echo "Private key: $KEY_PATH"
echo "Public key: ${KEY_PATH}.pub"

sleep 4

echo "kubernetes cluster creation is started"
sleep 4

# Exit immediately if a command exits with a non-zero status
set -e

# Set required variables (Modify these according to your setup)
KOPS_STATE_STORE="s3://mykopsbucket.in.k8s"
KOPS_CLUSTER_NAME="mykopsbucket.in"
NODE_COUNT=2
CONTROL_PLANE_COUNT=1
NODE_SIZE="t3.medium"
CONTROL_PLANE_SIZE="t3.medium"
DNS_TYPE="private"

# Get the first available AWS zone dynamically
DEFAULT_ZONE=$(aws ec2 describe-availability-zones \
    --query "AvailabilityZones[0].ZoneName" \
    --output text)

echo "Using availability zone: $DEFAULT_ZONE"

# Export KOPS_STATE_STORE to ensure kops recognizes it
export KOPS_STATE_STORE

# Create the Kubernetes cluster with kops
kops create cluster \
    --state=${KOPS_STATE_STORE} \
    --node-count=${NODE_COUNT} \
    --control-plane-count=${CONTROL_PLANE_COUNT} \
    --node-size=${NODE_SIZE} \
    --control-plane-size=${CONTROL_PLANE_SIZE} \
    --zones=${DEFAULT_ZONE} \
    --name=${KOPS_CLUSTER_NAME} \
    --dns=${DNS_TYPE}

# Apply the cluster configuration
kops update cluster --yes --admin

# Validate the cluster after creation
echo "Waiting for cluster to be ready..."
sleep 60  # Adjust as needed

kops validate cluster --state=${KOPS_STATE_STORE} --name=${KOPS_CLUSTER_NAME}

echo "Kubernetes cluster ${KOPS_CLUSTER_NAME} created successfully!"

