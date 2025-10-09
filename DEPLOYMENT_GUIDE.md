# Deployment Guide

This guide walks you through deploying the AWS DevOps Portfolio project from scratch.

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured
   ```bash
   aws configure
   ```
3. **kubectl** installed
   ```bash
   # macOS
   brew install kubectl

   # Linux
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   ```
4. **Docker** installed for local testing
5. **GitHub Account** for code repository and Actions

## Step-by-Step Deployment

### 1. Set Environment Variables

```bash
export AWS_REGION=us-east-1
export ENVIRONMENT=devops-portfolio
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

### 2. Deploy Infrastructure

#### 2.1 VPC and Networking

```bash
chmod +x scripts/*.sh
./scripts/deploy-stack.sh vpc-network 01-vpc-network.yaml devops-portfolio
```

**What this creates:**
- VPC with CIDR 10.0.0.0/16
- 3 public subnets across 3 AZs
- 3 private subnets across 3 AZs
- Internet Gateway
- 3 NAT Gateways (one per AZ)
- Route tables and associations
- VPC Flow Logs

**Estimated time:** 5-7 minutes

#### 2.2 EKS Cluster

```bash
./scripts/deploy-stack.sh eks-cluster 02-eks-cluster.yaml devops-portfolio
```

**What this creates:**
- EKS cluster (v1.34 - latest)
- Managed node group with 2 t3.medium instances
- ECR repository for Docker images
- IAM roles for EKS cluster and nodes
- Security groups
- OIDC provider for IRSA
- CloudWatch log group

**Estimated time:** 15-20 minutes

#### 2.3 RDS Database

```bash
./scripts/deploy-stack.sh rds-database 03-rds-database.yaml devops-portfolio
```

**What this creates:**
- PostgreSQL 14 RDS instance
- DB subnet group across private subnets
- Security group allowing access from EKS nodes
- Secrets Manager secret with credentials
- CloudWatch alarms for monitoring
- Performance Insights enabled

**Estimated time:** 10-15 minutes

#### 2.4 Storage and Messaging

```bash
./scripts/deploy-stack.sh storage-messaging 04-storage-messaging.yaml devops-portfolio
```

**What this creates:**
- S3 buckets (artifacts, static content, logs)
- SQS queues (processing queue + DLQ)
- SNS topic for notifications
- Lambda functions for processing
- IAM roles and policies
- CloudWatch log groups

**Estimated time:** 3-5 minutes

#### 2.5 CI/CD Pipeline

**IMPORTANT: Setup GitHub Token First**

Before deploying the pipeline, you need to store your GitHub personal access token in AWS Secrets Manager:

```bash
# 1. Create a GitHub personal access token
# Go to: https://github.com/settings/tokens/new
# Required scopes: repo, admin:repo_hook
# Copy the generated token (starts with ghp_)

# 2. Store the token in AWS Secrets Manager
./scripts/update-github-token.sh ghp_your_token_here

# 3. Deploy the CI/CD pipeline
./scripts/deploy-stack.sh cicd-pipeline 05-cicd-pipeline.yaml devops-portfolio
```

**What this creates:**
- CodePipeline with Source, Build, Deploy stages
- CodeBuild project
- CodeDeploy application
- S3 bucket for pipeline artifacts
- GitHub webhook
- IAM roles and policies
- CloudWatch events

**Estimated time:** 3-5 minutes

### 3. Configure kubectl

```bash
aws eks update-kubeconfig --name devops-portfolio-cluster --region us-east-1
kubectl get nodes
```

### 4. Install AWS Load Balancer Controller

```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install cert-manager
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Install AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=devops-portfolio-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 5. Initialize Database

**Important:** The RDS database is in a private subnet and can only be accessed from within the VPC. You cannot connect directly from your local machine (this is a security best practice).

**Option A: Connect using a Kubernetes Pod (Recommended)**

```bash
# Step 1: Configure kubectl for EKS
aws eks update-kubeconfig --name devops-portfolio-cluster --region us-east-1

# Step 2: Get database endpoint
DB_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name devops-portfolio-rds-database \
  --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
  --output text --region us-east-1)

echo "Database Endpoint: $DB_ENDPOINT"

# Step 3: Get database password from Secrets Manager
DB_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id devops-portfolio-db-secret \
  --region us-east-1 \
  --query SecretString --output text)

DB_PASSWORD=$(echo $DB_SECRET | jq -r '.password')
echo "Password retrieved (keep this secure!)"

# Step 4: Launch a PostgreSQL client pod in your EKS cluster
kubectl run psql-client --rm -it --image=postgres:16 --restart=Never -- bash

# Step 5: Inside the pod, connect to the database
# (Replace <password> with the password from step 3)
export PGPASSWORD="<paste-password-here>"
psql -h <paste-db-endpoint-here> -U dbadmin -d appdb

# Step 6: Create your table (run this at the psql prompt)
CREATE TABLE IF NOT EXISTS items (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

# Step 7: Verify table creation
\dt

# Step 8: Insert test data
INSERT INTO items (name, description) VALUES ('Test Item', 'Created from Kubernetes pod');

# Step 9: Query to verify
SELECT * FROM items;

# Step 10: Exit psql and the pod
\q
exit
```

**Option B: All-in-One Script (Automated)**

```bash
# Get credentials and endpoint
DB_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name devops-portfolio-rds-database \
  --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
  --output text --region us-east-1)

DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id devops-portfolio-db-secret \
  --region us-east-1 \
  --query SecretString --output text | jq -r '.password')

# Run SQL commands in a temporary pod
kubectl run psql-client --rm -i --image=postgres:16 --restart=Never -- \
  bash -c "export PGPASSWORD='$DB_PASSWORD' && psql -h $DB_ENDPOINT -U dbadmin -d appdb << 'EOF'
CREATE TABLE IF NOT EXISTS items (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO items (name, description) VALUES ('Test Item', 'Initial setup complete');

SELECT * FROM items;
EOF
"
```

**Why can't I connect from my local machine?**

The database is correctly configured in private subnets with no public access. This is a security best practice that prevents unauthorized access. The database can only be accessed from:
- EKS pods (your applications)
- EC2 instances within the VPC
- Through a bastion host or VPN connection

This design follows AWS security recommendations and is how production databases should be configured.

### 6. Build and Push Docker Image

```bash
cd app

# Get ECR repository URI
ECR_URI=$(aws cloudformation describe-stacks \
  --stack-name devops-portfolio-eks-cluster \
  --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryUri`].OutputValue' \
  --output text)

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URI

# Build and push
docker build -t $ECR_URI:latest .
docker push $ECR_URI:latest

cd ..
```

### 7. Deploy Application to EKS

```bash
# Get required values
export ECR_REPOSITORY_URI=$(aws cloudformation describe-stacks \
  --stack-name devops-portfolio-eks-cluster \
  --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryUri`].OutputValue' \
  --output text)

export IMAGE_TAG=latest

export DB_SECRET_ARN=$(aws cloudformation describe-stacks \
  --stack-name devops-portfolio-rds-database \
  --query 'Stacks[0].Outputs[?OutputKey==`DBSecretArn`].OutputValue' \
  --output text)

export SQS_QUEUE_URL=$(aws cloudformation describe-stacks \
  --stack-name devops-portfolio-storage-messaging \
  --query 'Stacks[0].Outputs[?OutputKey==`ProcessingQueueUrl`].OutputValue' \
  --output text)

export S3_BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name devops-portfolio-storage-messaging \
  --query 'Stacks[0].Outputs[?OutputKey==`StaticContentBucketName`].OutputValue' \
  --output text)

export IAM_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name devops-portfolio-storage-messaging \
  --query 'Stacks[0].Outputs[?OutputKey==`LambdaExecutionRoleArn`].OutputValue' \
  --output text)

# Deploy to Kubernetes
envsubst < kubernetes/deployment.yaml | kubectl apply -f -
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# Wait for deployment
kubectl rollout status deployment/devops-portfolio-app -n default
```

### 8. Setup GitHub Actions (Optional)

1. Fork/push this repository to GitHub

2. Add GitHub Secrets:
   - Go to Settings > Secrets and variables > Actions
   - Add the following secrets:
     - `AWS_ACCESS_KEY_ID`
     - `AWS_SECRET_ACCESS_KEY`
     - `AWS_REGION` (us-east-1)
     - `SNS_TOPIC_ARN`

3. Push code to main branch to trigger pipeline

### 9. Verify Deployment

```bash
# Check pods
kubectl get pods -n default

# Check services
kubectl get svc -n default

# Get load balancer URL
LB_URL=$(kubectl get svc devops-portfolio-service -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Application URL: http://$LB_URL"

# Test application
curl http://$LB_URL/health
```

## Monitoring and Logs

### CloudWatch Logs

```bash
# EKS logs
aws logs tail /aws/eks/devops-portfolio-cluster/cluster --follow

# Lambda logs
aws logs tail /aws/lambda/devops-portfolio-processing-function --follow

# RDS logs
aws logs tail /aws/rds/instance/devops-portfolio-db/postgresql --follow
```

### Kubernetes Logs

```bash
# Application logs
kubectl logs -f deployment/devops-portfolio-app -n default

# All pods
kubectl logs -l app=devops-portfolio -n default --tail=100
```

## Cost Estimation

**Monthly costs (us-east-1, approximate):**

- EKS Cluster: $73
- EC2 (2x t3.medium): $60
- NAT Gateways (3): $97
- RDS (db.t3.micro): $15
- ALB: $23
- S3, Lambda, SQS, SNS: $5-10
- CloudWatch Logs: $5-10

**Total: ~$280-300/month**

**Cost optimization for demo/portfolio:**
- Use 1 NAT Gateway instead of 3: Save $64/month
- Use db.t3.micro for RDS: Current config
- Reduce EKS nodes to 1 for testing: Save $30/month
- Delete when not in use

## Cleanup

To delete all infrastructure:

```bash
./scripts/teardown.sh devops-portfolio
```

**Important:** Type `DELETE` when prompted to confirm.

This will delete all stacks in reverse order and clean up S3 buckets and ECR images.

## Troubleshooting

### EKS Nodes Not Joining

```bash
kubectl get nodes
aws eks describe-nodegroup --cluster-name devops-portfolio-cluster --nodegroup-name devops-portfolio-node-group
```

### Application Not Accessible

```bash
kubectl get ingress
kubectl describe ingress devops-portfolio-ingress
kubectl get svc aws-load-balancer-controller -n kube-system
```

### Database Connection Issues

```bash
kubectl exec -it deployment/devops-portfolio-app -- env | grep DB
kubectl logs deployment/devops-portfolio-app
```

### Pipeline Failures

```bash
aws codepipeline get-pipeline-state --name devops-portfolio-pipeline
aws codebuild batch-get-builds --ids <build-id>
```

## Next Steps

1. **Add Domain and SSL**: Update ingress with ACM certificate
2. **Setup Monitoring**: Add Prometheus and Grafana
3. **Implement ArgoCD**: For GitOps deployment
4. **Add More Features**: Expand the application
5. **Implement Blue/Green**: Use CodeDeploy for zero-downtime deployments

## Support

For issues or questions, check:
- AWS CloudFormation Console
- EKS Console
- CloudWatch Logs
- GitHub Actions logs
