# AWS CloudFormation DevOps Project

A comprehensive AWS infrastructure project demonstrating DevOps best practices using CloudFormation, CI/CD pipelines, and containerized microservices.

## Architecture Overview

This project showcases a production-ready infrastructure with:

- **Networking**: Custom VPC with public/private subnets across 3 AZs
- **Container Orchestration**: EKS cluster with managed node groups
- **Database**: Multi-AZ RDS PostgreSQL instance
- **Storage**: S3 buckets for artifacts and static assets
- **Compute**: Lambda functions for event-driven processing
- **Messaging**: SQS queues and SNS topics for decoupled architecture
- **Load Balancing**: Application Load Balancer for distributing traffic
- **CI/CD**: Full pipeline with CodePipeline, CodeBuild, CodeDeploy
- **Container Registry**: ECR for Docker images
- **IAM**: Least-privilege security roles and policies

## Project Structure

```
aws-cloudformation-project/
├── cloudformation/
│   ├── 01-vpc-network.yaml          # VPC, Subnets, NAT, IGW
│   ├── 02-eks-cluster.yaml          # EKS cluster and node groups
│   ├── 03-rds-database.yaml         # RDS PostgreSQL instance
│   ├── 04-storage-messaging.yaml    # S3, Lambda, SQS, SNS
│   ├── 05-cicd-pipeline.yaml        # CodePipeline, CodeBuild, CodeDeploy
│   └── parameters/
│       ├── dev.json
│       └── prod.json
├── app/
│   ├── src/                         # Sample Node.js microservice
│   ├── Dockerfile
│   └── package.json
├── kubernetes/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── scripts/
│   ├── deploy-stack.sh
│   ├── update-stack.sh
│   └── teardown.sh
├── .github/
│   └── workflows/
│       └── deploy.yaml              # GitHub Actions workflow
└── buildspec.yml                    # CodeBuild build specification

```

## AWS Services Used

- **VPC**: Custom networking with public/private subnets
- **EC2**: EKS worker nodes
- **EKS**: Kubernetes cluster management
- **ECR**: Container image registry
- **RDS**: PostgreSQL database
- **S3**: Object storage for artifacts
- **Lambda**: Serverless functions
- **SQS**: Message queuing
- **SNS**: Pub/Sub notifications
- **ALB**: Application Load Balancer
- **IAM**: Identity and access management
- **CodePipeline**: CI/CD orchestration
- **CodeBuild**: Build automation
- **CodeDeploy**: Deployment automation

## Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl installed
- Docker installed (for local testing)
- GitHub account (for Actions integration)

## Deployment Instructions

### 1. Deploy Base Infrastructure

```bash
# Deploy VPC and Networking
./scripts/deploy-stack.sh vpc-network 01-vpc-network.yaml dev

# Deploy EKS Cluster
./scripts/deploy-stack.sh eks-cluster 02-eks-cluster.yaml dev

# Deploy RDS Database
./scripts/deploy-stack.sh rds-database 03-rds-database.yaml dev

# Deploy Storage and Messaging
./scripts/deploy-stack.sh storage-messaging 04-storage-messaging.yaml dev

# Setup GitHub Token (required for CI/CD pipeline)
# Create token at: https://github.com/settings/tokens/new (scopes: repo, admin:repo_hook)
./scripts/update-github-token.sh ghp_your_token_here

# Deploy CI/CD Pipeline
./scripts/deploy-stack.sh cicd-pipeline 05-cicd-pipeline.yaml dev
```

### 2. Configure kubectl for EKS

```bash
aws eks update-kubeconfig --name devops-portfolio-cluster --region us-east-1
```

### 3. Deploy Application to EKS

```bash
kubectl apply -f kubernetes/
```

### 4. Setup GitHub Actions

- Add AWS credentials to GitHub Secrets:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_REGION`

## CI/CD Pipeline Flow

1. **Source**: Code pushed to GitHub repository
2. **Build**: CodeBuild compiles code, runs tests, builds Docker image
3. **Push**: Image pushed to ECR
4. **Deploy**: CodeDeploy updates EKS deployment with new image
5. **Notify**: SNS sends deployment notification

## Application Flow

1. User request → ALB → EKS Service
2. Application processes request, writes to RDS
3. Async tasks sent to SQS queue
4. Lambda function triggered by SQS message
5. Results stored in S3
6. SNS notification sent on completion

## Monitoring and Logging

- CloudWatch Logs for Lambda and EKS
- CloudWatch Metrics for all services
- ALB access logs stored in S3
- VPC Flow Logs enabled

## Cost Optimization

- Auto-scaling enabled for EKS node groups
- RDS configured with instance size appropriate for testing
- S3 lifecycle policies for log retention
- Lambda with appropriate memory/timeout settings

## Security Best Practices

- **Secrets Management**: GitHub tokens and DB credentials stored in AWS Secrets Manager (never in code)
- **Least Privilege IAM**: Scoped roles for all services with minimal required permissions
- **Network Isolation**: Database and apps in private subnets, NAT for outbound only
- **Encryption**: All data encrypted at rest (RDS, S3, EBS) and in transit (TLS)
- **Security Groups**: Minimal port access, no public database exposure
- **Monitoring**: VPC Flow Logs, CloudTrail, CloudWatch for audit trails

**See [SECURITY.md](SECURITY.md) for detailed security documentation.**

## Clean Up

```bash
./scripts/teardown.sh
```

## Future Enhancements

- ArgoCD for GitOps deployment
- Prometheus/Grafana for monitoring
- HashiCorp Vault for secrets management
- Multi-region deployment
- Blue/Green deployment strategy

## License

MIT

## Author

Your Name - AWS CloudFormation Portfolio Project
