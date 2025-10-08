#!/bin/bash

# Script to teardown all CloudFormation stacks
# Usage: ./teardown.sh <environment>

set -e

ENVIRONMENT=${1:-devops-portfolio}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=== WARNING: This will delete all infrastructure ===${NC}"
echo "Environment: $ENVIRONMENT"
echo "Region: ${AWS_REGION:-us-east-1}"
echo ""

# Confirm deletion
read -p "Are you sure you want to delete all stacks? Type 'DELETE' to confirm: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo -e "${YELLOW}Teardown cancelled${NC}"
    exit 0
fi

# List of stacks to delete in order (reverse of creation)
STACKS=(
    "cicd-pipeline"
    "storage-messaging"
    "rds-database"
    "eks-cluster"
    "vpc-network"
)

# Function to delete a stack
delete_stack() {
    local stack_name="$ENVIRONMENT-$1"

    echo -e "\n${YELLOW}Checking if stack exists: $stack_name${NC}"

    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region ${AWS_REGION:-us-east-1} \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "DOES_NOT_EXIST")

    if [ "$STACK_STATUS" == "DOES_NOT_EXIST" ]; then
        echo -e "${YELLOW}Stack does not exist: $stack_name${NC}"
        return
    fi

    echo -e "${RED}Deleting stack: $stack_name${NC}"

    # Empty S3 buckets first if they exist
    if [[ $1 == *"storage"* ]] || [[ $1 == *"pipeline"* ]]; then
        echo -e "${YELLOW}Emptying S3 buckets...${NC}"

        BUCKETS=$(aws cloudformation describe-stack-resources \
            --stack-name "$stack_name" \
            --region ${AWS_REGION:-us-east-1} \
            --query 'StackResources[?ResourceType==`AWS::S3::Bucket`].PhysicalResourceId' \
            --output text 2>/dev/null || echo "")

        for bucket in $BUCKETS; do
            if [ -n "$bucket" ]; then
                echo "Emptying bucket: $bucket"
                aws s3 rm s3://$bucket --recursive --region ${AWS_REGION:-us-east-1} 2>/dev/null || true
                aws s3api delete-bucket --bucket $bucket --region ${AWS_REGION:-us-east-1} 2>/dev/null || true
            fi
        done
    fi

    # Delete ECR images if this is the EKS stack
    if [[ $1 == *"eks"* ]]; then
        echo -e "${YELLOW}Deleting ECR images...${NC}"

        REPOS=$(aws cloudformation describe-stack-resources \
            --stack-name "$stack_name" \
            --region ${AWS_REGION:-us-east-1} \
            --query 'StackResources[?ResourceType==`AWS::ECR::Repository`].PhysicalResourceId' \
            --output text 2>/dev/null || echo "")

        for repo in $REPOS; do
            if [ -n "$repo" ]; then
                echo "Deleting images from repository: $repo"
                aws ecr batch-delete-image \
                    --repository-name $repo \
                    --image-ids "$(aws ecr list-images --repository-name $repo --region ${AWS_REGION:-us-east-1} --query 'imageIds[*]' --output json)" \
                    --region ${AWS_REGION:-us-east-1} 2>/dev/null || true
            fi
        done
    fi

    # Delete the stack
    aws cloudformation delete-stack \
        --stack-name "$stack_name" \
        --region ${AWS_REGION:-us-east-1}

    echo -e "${YELLOW}Waiting for stack deletion: $stack_name${NC}"
    aws cloudformation wait stack-delete-complete \
        --stack-name "$stack_name" \
        --region ${AWS_REGION:-us-east-1} 2>&1 || {
        echo -e "${RED}Warning: Stack deletion may have failed or timed out${NC}"
    }

    echo -e "${GREEN}Stack deleted: $stack_name${NC}"
}

# Delete all stacks
for stack in "${STACKS[@]}"; do
    delete_stack "$stack"
    sleep 5  # Small delay between deletions
done

echo -e "\n${GREEN}=== Teardown Complete ===${NC}"
echo -e "${YELLOW}Note: Some resources may take additional time to fully delete${NC}"
echo ""
echo "Verify all resources are deleted:"
echo "  aws cloudformation list-stacks --region ${AWS_REGION:-us-east-1}"
