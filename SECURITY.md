# Security Best Practices

This document outlines the security measures implemented in this project and best practices for managing secrets.

## Secrets Management

### GitHub Personal Access Token

The GitHub personal access token is **never** stored in CloudFormation templates or code. Instead, it's securely stored in AWS Secrets Manager.

#### How It Works

1. **AWS Secrets Manager**: The token is encrypted at rest using AWS KMS
2. **Dynamic Resolution**: CloudFormation uses `{{resolve:secretsmanager:...}}` to fetch the token at runtime
3. **No Exposure**: The token never appears in CloudFormation templates, stack outputs, or logs

#### Setting Up the GitHub Token

```bash
# Store your token securely
./scripts/update-github-token.sh ghp_your_token_here

# The token is now encrypted in AWS Secrets Manager
# CloudFormation will retrieve it automatically when deploying the pipeline
```

#### Updating the Token

If you need to rotate or update your GitHub token:

```bash
# Create a new token at https://github.com/settings/tokens/new
# Then update it:
./scripts/update-github-token.sh ghp_new_token_here
```

The pipeline will automatically use the new token on the next deployment or trigger.

### Database Credentials

Database credentials are managed through AWS Secrets Manager:

- **Master Password**: Set during stack creation (use a strong password)
- **Automatic Storage**: CloudFormation stores credentials in Secrets Manager
- **Application Access**: Applications retrieve credentials at runtime using IAM roles

#### Accessing Database Credentials

```bash
# Get the secret ARN
SECRET_ARN=$(aws cloudformation describe-stacks \
  --stack-name devops-portfolio-rds-database \
  --query 'Stacks[0].Outputs[?OutputKey==`DBSecretArn`].OutputValue' \
  --output text)

# Retrieve the credentials (requires appropriate IAM permissions)
aws secretsmanager get-secret-value --secret-id $SECRET_ARN
```

### Best Practices

1. **Never Commit Secrets**:
   - All sensitive files are listed in `.gitignore`
   - Use environment variables or Secrets Manager
   - Rotate tokens regularly

2. **Use IAM Roles**:
   - EKS pods use IRSA (IAM Roles for Service Accounts)
   - Lambda functions have dedicated execution roles
   - Principle of least privilege

3. **Encryption**:
   - All secrets encrypted at rest (AWS KMS)
   - RDS encryption enabled
   - S3 bucket encryption enabled
   - EBS volumes encrypted

4. **Network Security**:
   - Database in private subnets
   - Security groups with minimal access
   - VPC Flow Logs enabled
   - Network policies for Kubernetes

5. **Monitoring**:
   - CloudWatch logs for all services
   - CloudTrail for API activity
   - Secrets Manager rotation tracking

## What NOT to Do

❌ **DO NOT** hardcode tokens in CloudFormation templates
❌ **DO NOT** commit `.env` files with real credentials
❌ **DO NOT** use default passwords
❌ **DO NOT** expose database to public internet
❌ **DO NOT** share IAM credentials
❌ **DO NOT** disable encryption

## What TO Do

✅ **DO** use AWS Secrets Manager for all secrets
✅ **DO** rotate credentials regularly
✅ **DO** use strong, unique passwords
✅ **DO** enable MFA on AWS accounts
✅ **DO** review IAM policies regularly
✅ **DO** use encrypted connections (TLS/SSL)
✅ **DO** enable CloudTrail and monitor logs

## Secrets Rotation

### GitHub Token Rotation

```bash
# 1. Create new token on GitHub
# 2. Update in Secrets Manager
./scripts/update-github-token.sh ghp_new_token

# 3. No stack update needed - automatically used on next pipeline run
```

### RDS Password Rotation

```bash
# AWS Secrets Manager can automatically rotate RDS passwords
# To enable rotation, uncomment the rotation section in 03-rds-database.yaml
# and deploy a rotation Lambda function
```

## IAM Permissions

This project follows the principle of least privilege:

- **CodeBuild**: Only accesses ECR, S3, and EKS
- **Lambda**: Only accesses S3, SQS, SNS, and specific secrets
- **EKS Pods**: Use IRSA with scoped permissions
- **CodePipeline**: Only manages its own resources

## Compliance

The infrastructure follows these compliance frameworks:

- AWS Well-Architected Framework (Security Pillar)
- CIS AWS Foundations Benchmark (where applicable)
- OWASP security best practices

## Reporting Security Issues

If you discover a security vulnerability in this project:

1. **DO NOT** open a public issue
2. Contact the maintainer privately
3. Provide details of the vulnerability
4. Allow time for a fix before public disclosure

## Additional Resources

- [AWS Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [EKS Security Best Practices](https://aws.github.io/aws-eks-best-practices/security/docs/)
- [RDS Security](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.html)
- [GitHub Token Security](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github)
