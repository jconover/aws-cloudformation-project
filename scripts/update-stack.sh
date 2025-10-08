#!/bin/bash

# Script to update CloudFormation stacks
# Usage: ./update-stack.sh <stack-name> <template-file> <environment>

set -e

STACK_NAME=$1
TEMPLATE_FILE=$2
ENVIRONMENT=${3:-devops-portfolio}

if [ -z "$STACK_NAME" ] || [ -z "$TEMPLATE_FILE" ]; then
    echo "Usage: ./update-stack.sh <stack-name> <template-file> <environment>"
    echo "Example: ./update-stack.sh vpc-network 01-vpc-network.yaml dev"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_PATH="$PROJECT_ROOT/cloudformation/$TEMPLATE_FILE"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Updating CloudFormation Stack ===${NC}"
echo "Stack Name: $ENVIRONMENT-$STACK_NAME"
echo "Template: $TEMPLATE_FILE"
echo ""

# Check if stack exists
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$ENVIRONMENT-$STACK_NAME" \
    --region ${AWS_REGION:-us-east-1} \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "$STACK_STATUS" == "DOES_NOT_EXIST" ]; then
    echo -e "${RED}Error: Stack does not exist. Use deploy-stack.sh to create it.${NC}"
    exit 1
fi

# Create change set
CHANGE_SET_NAME="${ENVIRONMENT}-${STACK_NAME}-$(date +%Y%m%d%H%M%S)"

echo -e "${YELLOW}Creating change set: $CHANGE_SET_NAME${NC}"
aws cloudformation create-change-set \
    --stack-name "$ENVIRONMENT-$STACK_NAME" \
    --change-set-name "$CHANGE_SET_NAME" \
    --template-body file://$TEMPLATE_PATH \
    --parameters ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT \
    --capabilities CAPABILITY_NAMED_IAM \
    --region ${AWS_REGION:-us-east-1}

echo -e "${YELLOW}Waiting for change set to be created...${NC}"
aws cloudformation wait change-set-create-complete \
    --stack-name "$ENVIRONMENT-$STACK_NAME" \
    --change-set-name "$CHANGE_SET_NAME" \
    --region ${AWS_REGION:-us-east-1}

# Describe changes
echo -e "\n${GREEN}=== Proposed Changes ===${NC}"
aws cloudformation describe-change-set \
    --stack-name "$ENVIRONMENT-$STACK_NAME" \
    --change-set-name "$CHANGE_SET_NAME" \
    --region ${AWS_REGION:-us-east-1} \
    --query 'Changes[*].[Type,ResourceChange.Action,ResourceChange.LogicalResourceId,ResourceChange.ResourceType]' \
    --output table

# Confirm execution
read -p "Do you want to execute this change set? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Change set not executed. Deleting change set...${NC}"
    aws cloudformation delete-change-set \
        --stack-name "$ENVIRONMENT-$STACK_NAME" \
        --change-set-name "$CHANGE_SET_NAME" \
        --region ${AWS_REGION:-us-east-1}
    exit 0
fi

# Execute change set
echo -e "${YELLOW}Executing change set...${NC}"
aws cloudformation execute-change-set \
    --stack-name "$ENVIRONMENT-$STACK_NAME" \
    --change-set-name "$CHANGE_SET_NAME" \
    --region ${AWS_REGION:-us-east-1}

echo -e "${YELLOW}Waiting for stack update to complete...${NC}"
aws cloudformation wait stack-update-complete \
    --stack-name "$ENVIRONMENT-$STACK_NAME" \
    --region ${AWS_REGION:-us-east-1}

echo -e "${GREEN}Stack updated successfully!${NC}"
