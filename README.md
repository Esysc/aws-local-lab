# AWS Local Lab

> DISCLAIMER: This repo targets local development using LocalStack (Community edition). LocalStack OSS is convenient for learning but does not fully emulate every AWS API or production behavior — some ALB/ELB, AutoScaling, AMI lookups, Route53 certificate flows, or advanced CloudWatch features may be limited. The configs include guards so basic flows run on LocalStack OSS; enable `var.localstack_pro` or use a real AWS sandbox account for higher fidelity.

A hands-on Terraform training lab for practicing infrastructure patterns locally using [LocalStack](https://localstack.cloud/). This lab demonstrates common AWS resource patterns like VPCs, subnets, EC2 instances, autoscaling groups, and load balancers without requiring a real AWS account.

## Goals

- **Learn Terraform workflows**: `init`, `plan`, `apply`, `destroy`.
- **Practice Resource Patterns**: VPC networking, security groups, user-data provisioning, and autoscaling.
- **Local-First Development**: Avoid cloud costs and credential management issues by using LocalStack.

## Quick Start (Local)

1. **Start LocalStack**:

   ```bash
   docker compose up -d
   ```

2. **Run the Lab Helper**:
   You can use the provided helper script to automate the setup:

   ```bash
   ./lab-run.sh --apply
   ```

   _Note: This script waits for LocalStack to be ready, initializes Terraform, and applies the configuration._

3. **Manual Terraform Workflow**:
   If you prefer running commands manually:

   ```bash
   export TF_VAR_use_local=true
   make init
   make plan
   make apply
   ```

## Repository Structure

- `core/`: Main Terraform configuration files.
- `scripts/`: Helper scripts like `httpCheck` for health monitoring.
- `docker-compose.yml`: LocalStack configuration for local emulation.
- `lab-run.sh`: Automation script for the local workflow.
- `Makefile`: Convenience targets for Terraform operations.

## What Terraform Creates**

- **VPC & Networking:**: creates a VPC (`aws_vpc.main`), three subnets (`aws_subnet.*`), an Internet Gateway (`aws_internet_gateway.main`), route table and associations. See [core/main.tf](core/main.tf).
- **Security Groups:**: SSH (public/private), HTTP, and ELB security groups used to control access (`aws_security_group.*`).
- **Bastion (EC2):**: `aws_instance.main_bastion` — a small instance used as a bastion host with IMDS `http_tokens = "required"`, encrypted root block device, and an Elastic IP (`aws_eip.bastionip`). The AMI is resolved from AWS when running against real AWS; a fallback `var.ami_id` is used for local runs.
- **Web tier (optional / advanced):**: launch configuration (`aws_launch_configuration.web`), autoscaling group (`aws_autoscaling_group.web`), classical ELB (`aws_elb.web_elb`), autoscaling policies and CloudWatch alarms. These resources are gated by the `local.advanced_count` logic so they are optional when running against LocalStack OSS. See [core/main.tf](core/main.tf).
- **DNS / Route53:**: public hosted zone (`aws_route53_zone.web-public-zone`) and an A record alias pointing to the ELB (`aws_route53_record.cloudlab`).
- **Observability & Flow Logs (non-local):**: CloudWatch log group and VPC flow logs (`aws_cloudwatch_log_group`, `aws_flow_log`) plus an IAM role/policy to allow flow logs. These are skipped when `var.use_local = true`.
- **State & Guards:**: the Terraform config uses `var.use_local` (default `true`) to point the AWS provider to LocalStack and to disable resources that LocalStack OSS does not fully emulate (AMI lookups, flow logs, etc.). The `var.localstack_pro` toggle controls whether advanced LocalStack Pro-only features are considered available.
- **Local fallbacks/tools:**: the repository includes local helpers and overrides for exercises that don't map well to LocalStack OSS: `docker-compose.override.yml` (adds `ec2-node-1`, `minio`, `mailhog`), `core/local_ec2.tf` (starts the local SSH container when `use_local`), and `lab-run.sh` (waits for LocalStack, generates/injects SSH keys for local `ec2-node-1`, and exports `TF_VAR_ssh_private_key_path`).

## LocalStack Details

- **Persistence**: Data is persisted in the `./.localstack` directory.
- **Health Check**: Available at `http://localhost:4566/_localstack/health`.
- **Supported Services**: EC2, S3, ELB, Autoscaling, Route53, CloudWatch, IAM.

### Observed LocalStack services (OSS)

```text
acm: available
apigateway: available
cloudformation: available
cloudwatch: available
config: available
dynamodb: available
dynamodbstreams: available
ec2: running
es: available
events: available
firehose: available
iam: running
kinesis: available
kms: available
lambda: available
logs: available
opensearch: available
redshift: available
resource-groups: available
resourcegroupstaggingapi: available
route53: running
route53resolver: available
s3: running
s3control: available
scheduler: available
secretsmanager: available
ses: available
sns: available
sqs: available
ssm: available
stepfunctions: available
sts: running
support: available
swf: available
transcribe: available
```

Services marked `running` typically indicate the LocalStack edge/service is active and responding; `available` means the emulator exposes an implementation of the API but behavior/fidelity may be limited in OSS.

If LocalStack OSS lacks fidelity for a given service, you can often supplement with a small, focused Docker image for that capability. Practical alternatives include:

- Load balancer / ELB/ALB: run a lightweight reverse proxy (nginx, Traefik) and point DNS to it. Example snippet:

```yaml
services:
   nginx-lb:
      image: nginx:stable-alpine
      ports:
         - "8080:80"
      volumes:
         - ./nginx.conf:/etc/nginx/nginx.conf:ro
```

- Auto-scaling (simulate): run multiple `web` containers and update the load balancer upstream, or use `docker compose up --scale web=3` for replicated instances.

- AMI/EC2 metadata or AMI lookup gaps: use a fixed `ami_id` fallback (see `var.ami_id`) or replace EC2-based web servers with a Docker `nginx` container for exercises.

- Certificate / ACM flows: use `mkcert` for local TLS, or `certbot` against a staging CA for demos. For email/SES testing use `mailhog` or `smtp4dev`.

- OpenSearch/Elasticsearch: use the official OpenSearch image:

```yaml
services:
   opensearch:
      image: opensearchproject/opensearch:2.5.0
      environment:
         - discovery.type=single-node
      ports:
         - "9200:9200"
```

General guidance:

- Add these extra services to `docker-compose.override.yml` to bring them up alongside LocalStack.
- Wire Terraform/tests to alternative endpoints via variables (e.g., `TF_VAR_minio_endpoint` or `TF_VAR_opensearch_endpoint`).
- Keep `var.use_local` guards so advanced resources are optional when LocalStack OSS is used.

### LocalStack OSS vs LocalStack Pro

- **LocalStack OSS**: covers many core AWS APIs (S3, SQS, SNS, basic EC2 calls, STS, etc.) and is well-suited for local development and lightweight CI. It does not fully emulate every AWS API or the full behavior of managed services — some Describe/Filter combinations, advanced ELB/ALB features, or production-ready Route53/Certificate flows may be missing or limited.

- **LocalStack Pro**: a commercial offering that expands API coverage, improves fidelity for services such as ALB/ELB, Route53, EKS-related flows, and provides additional tooling (dashboard, performance/scale improvements). Pro reduces false negatives in tests that require richer service behavior.

Guidance:

- Use OSS for quick, low-cost local iterations and learning exercises.
- Use Pro (or run against a sandbox AWS account) when you need higher fidelity testing for production-like behaviors.
- Design Terraform configs defensively (guard non-essential resources under `var.use_local`) so they run cleanly in both OSS and real AWS environments.

## Cleanup

To remove all local resources and the LocalStack container:

```bash
make destroy
docker compose down -v
```

## Security

- Never commit real AWS credentials.
- Use `terraform.tfvars` (ignored by git) for sensitive variables when running against real AWS or a Vault service.
