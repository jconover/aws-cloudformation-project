#!/bin/bash

# Script to deploy CloudFormation stacks
# Usage: ./deploy-stack.sh <stack-name> <template-file> <environment>

set -e

STACK_NAME=$1
TEMPLATE_FILE=$2
ENVIRONMENT=${3:-devops-portfolio}

if [ -z "$STACK_NAME" ] || [ -z "$TEMPLATE_FILE" ]; then
    echo "Usage: ./deploy-stack.sh <stack-name> <template-file> <environment>"
    echo "Example: ./deploy-stack.sh vpc-network 01-vpc-network.yaml dev"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_PATH="$PROJECT_ROOT/cloudformation/$TEMPLATE_FILE"
PARAMS_FILE="$PROJECT_ROOT/cloudformation/parameters/${ENVIRONMENT}.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Deploying CloudFormation Stack ===${NC}"
echo "Stack Name: $ENVIRONMENT-$STACK_NAME"
echo "Template: $TEMPLATE_FILE"
echo "Environment: $ENVIRONMENT"
echo "Region: ${AWS_REGION:-us-east-1}"
echo ""

# Check if template file exists
if [ ! -f "$TEMPLATE_PATH" ]; then
    echo -e "${RED}Error: Template file not found: $TEMPLATE_PATH${NC}"
    exit 1
fi

# Validate template
echo -e "${YELLOW}Validating template...${NC}"
aws cloudformation validate-template \
    --template-body file://$TEMPLATE_PATH \
    --region ${AWS_REGION:-us-east-1} > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Template validation successful${NC}"
else
    echo -e "${RED}Template validation failed${NC}"
    exit 1
fi

# Build parameters
PARAMETERS=""
if [ -f "$PARAMS_FILE" ]; then
    echo -e "${YELLOW}Using parameters from: $PARAMS_FILE${NC}"
    PARAMETERS="--parameters file://$PARAMS_FILE"
else
    echo -e "${YELLOW}No parameters file found, using defaults${NC}"
    PARAMETERS="--parameters ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT"
fi

# Check if stack exists
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$ENVIRONMENT-$STACK_NAME" \
    --region ${AWS_REGION:-us-east-1} \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "$STACK_STATUS" == "DOES_NOT_EXIST" ]; then
    echo -e "${YELLOW}Creating new stack...${NC}"
    aws cloudformation create-stack \
        --stack-name "$ENVIRONMENT-$STACK_NAME" \
        --template-body file://$TEMPLATE_PATH \
        $PARAMETERS \
        --capabilities CAPABILITY_NAMED_IAM \
        --region ${AWS_REGION:-us-east-1} \
        --tags Key=Environment,Value=$ENVIRONMENT Key=ManagedBy,Value=CloudFormation

    echo -e "${YELLOW}Waiting for stack creation to complete...${NC}"
    aws cloudformation wait stack-create-complete \
        --stack-name "$ENVIRONMENT-$STACK_NAME" \
        --region ${AWS_REGION:-us-east-1}

    echo -e "${GREEN}Stack created successfully!${NC}"
else
    echo -e "${YELLOW}Updating existing stack...${NC}"
    aws cloudformation update-stack \
        --stack-name "$ENVIRONMENT-$STACK_NAME" \
        --template-body file://$TEMPLATE_PATH \
        $PARAMETERS \
        --capabilities CAPABILITY_NAMED_IAM \
        --region ${AWS_REGION:-us-east-1} \
        2>&1 | tee /tmp/update-output.txt

    if grep -q "No updates are to be performed" /tmp/update-output.txt; then
        echo -e "${YELLOW}No changes detected in stack${NC}"
    else
        echo -e "${YELLOW}Waiting for stack update to complete...${NC}"
        aws cloudformation wait stack-update-complete \
            --stack-name "$ENVIRONMENT-$STACK_NAME" \
            --region ${AWS_REGION:-us-east-1}

        echo -e "${GREEN}Stack updated successfully!${NC}"
    fi
fi

# Show stack outputs
echo -e "\n${GREEN}=== Stack Outputs ===${NC}"
aws cloudformation describe-stacks \
    --stack-name "$ENVIRONMENT-$STACK_NAME" \
    --region ${AWS_REGION:-us-east-1} \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table

echo -e "\n${GREEN}Deployment completed!${NC}"
