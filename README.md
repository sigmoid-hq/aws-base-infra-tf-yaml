## AWS Base Infrastructure Terraform and YAML var Blueprint

A base AWS infrastructure implemented using __**Terraform and YAML based variable management**__. Provides essential resources including VPC, ECS (Fargate), RDS, and DynamoDB to serve as a reusable foundation for infrastructure testing and development.

---

## Diagram
![AWS DIAGRAM](/aws-base-infra-terraform.drawio.png)

## Introduction

This repository provisions a reusable AWS baseline using Terraform. It sets up
networking, compute, storage, and delivery components that can be promoted
across environments (`env/dev`, `env/prod`).

---
## Structure
```
.
├── config/                 # YAML environment configs consumed by locals
│   ├── dev.yaml            # Active dev configuration (copy from .sample)
│   └── prod.yaml           # Production configuration (copy from .sample)
├── env/
│   ├── dev/                  # Development workspace (providers, locals, state backend)
│   └── prod/                 # Production workspace
├── modules/
│   ├── cloudfront/           # CDN routing for static site + `/api` traffic
│   ├── dynamodb/             # Application DynamoDB table
│   ├── ec2/                  # Bastion host module
│   ├── ecs/                  # Fargate cluster, task definition, ALB, ECR
│   ├── iam/                  # Shared IAM roles/profiles (bastion, ECS)
│   ├── rds/                  # MySQL-compatible RDS instance
│   ├── s3/                   # Static website, logs, and asset buckets
│   └── vpc/                  # VPC, subnets, NAT, routing
├── keypair/                  # SSH public keys consumed by the bastion module
├── hello.tf
├── README.md
└── terraform.*               # Shared configs / helpers
```

---
## Module Overview
| Module      | Purpose |
|-------------|---------|
| **VPC**     | Builds the network foundation with VPC, subnets, NAT gateways, routing tables, Internet Gateway, and NAT EIPs. |
| **IAM**     | Provides opinionated roles and instance profiles (power user, read-only, ECS task execution) for EC2 and ECS workloads. |
| **EC2**     | Provisions the bastion host, associated key pair, security group rules, and optional Elastic IP. |
| **S3**      | Creates three buckets: primary (artifacts/backups), static asset hosting (website), and access logs with recommended defaults. |
| **RDS**     | Launches a MySQL-compatible instance with subnet group, security group, optional parameter overrides, backups, and logging toggles. |
| **DynamoDB**| Manages an application table supporting configurable attributes, billing mode, TTL, and optional secondary indexes. |
| **ECS**     | Packages ECR repository, Fargate cluster/service, task definition, CloudWatch log group, ALB + target group, and lifecycle hooks. |
| **CloudFront** | Routes `/` traffic to the static S3 site and `/api/*` to the ECS ALB, enforcing HTTPS and appropriate caching/forwarding rules. |

---
## SSH Key Preparation
The EC2 bastion module expects a public key at `keypair/<key_name>.pub`.

```bash
# Generate a new SSH key pair
mkdir -p keypair
ssh-keygen -t ed25519 -f keypair/ec2-kp-prod -C "ops@somedomain"

# Result: keypair/ec2-kp-prod (private) & keypair/ec2-kp-prod.pub (public)
# Ensure the .pub file name matches `bastion.key_name` in the YAML config.
```

> ⚠️ Never commit private keys. Keep only the public `.pub` file in repo if
> needed.

---
## YAML Configuration
Environment-specific values now live in YAML under `config/`. Each workspace
loads its corresponding file via `yamldecode`, so updating infrastructure
inputs is just a matter of editing YAML.

1. Copy the sample for each environment:
   ```bash
   cp config/dev.yaml.sample config/dev.yaml
   cp config/prod.yaml.sample config/prod.yaml
   ```
2. Fill in secrets such as `rds.master_password` outside of version control.
   Consider using SOPS or your preferred secrets manager if you need to commit
   encrypted values.
3. Optional overrides can go under additional top-level keys; anything set in
   YAML is picked up by the `locals {}` block in each environment.

Example (`config/dev.yaml`):
```yaml
metadata:
  environment: dev
  project_name: aws-base-infra
  prefix: sigmoid
  managed_by: Sigmoid

aws:
  region: ap-northeast-2
  profile: default

networking:
  vpc_cidr: 10.0.0.0/16

bastion:
  instance_type: t3.small
  key_name: ec2-kp

rds:
  engine: mysql
  engine_version: 8.0.42
  database_name: sigmoid_app
  port: 3306
  parameter_group_family: mysql8.0
  backup_window: 03:00-04:00
  maintenance_window: sun:05:00-sun:06:00
  cloudwatch_logs_exports:
    - error
    - slowquery
  performance_insights_enabled: false
  master_password: "<strong-password>"

ecs:
  repository_name: sigmoid-app
  image_tag_mutability: MUTABLE
  keep_last_n_images: 10
  app_version: 1.0.2
```

> ℹ️ `terraform.tfvars` files are no longer required. You can still use them for
> ad-hoc overrides, but the canonical configuration source is the YAML file.

---
## Deploying Environments
Each environment maintains its own backend while loading inputs from the
environment YAML files.

### 1. Review the YAML config
Update `config/dev.yaml` so metadata, networking, bastion key, database
credentials, and ECS image settings reflect your environment. Do the same for
`config/prod.yaml` before promoting.

### 2. Initialize
From the environment directory:
```bash
cd env/dev
terraform init
```
Repeat inside `env/prod` when ready.

### 3. Validate & Plan
```bash
terraform validate
terraform plan -out dev.plan
```

### 4. Apply
```bash
terraform apply dev.plan
```

### 5. Promote to Production
```bash
cd ../prod
terraform init
terraform validate
terraform plan -out prod.plan
terraform apply prod.plan
```

> ☝️ Remember to set a strong `rds.master_password` in your YAML (or source it
> via environment variables / secrets manager) before applying.

---
## Useful Outputs
Both environments export key outputs such as VPC IDs, RDS endpoints, DynamoDB
ARNs, ECS ALB DNS, and the CloudFront distribution domain. Run
`terraform output` inside the environment directory to inspect.

---
## Notes
- The ECS module builds/pushes images locally via `docker` and AWS CLI; ensure
  your workstation has permissions.
- CloudFront is configured with default certs; swap for ACM if using custom
  domains.
- Update `bastion_key_name` and the YAML configs before committing to keep
  secrets out of git.
