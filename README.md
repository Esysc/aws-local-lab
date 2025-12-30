# AWS Local Lab

A hands-on Terraform training lab for practicing infrastructure patterns locally using [LocalStack](https://localstack.cloud/) and **Docker-based EC2 emulation**. This lab demonstrates common AWS resource patterns like VPCs, subnets, EC2 instances, autoscaling groups, and load balancers without requiring a real AWS account.

## Architecture

When `var.use_local` is set to `true` (default), the lab uses a hybrid approach:

- **LocalStack**: Emulates AWS core services (VPC, IAM, S3, Route53, CloudWatch).
- **Docker Containers**: Emulates EC2 instances (Bastion and Web nodes using `ubuntu:20.04`).
- **Terraform Docker Provider**: Manages the local containers. Initial provisioning is done via `docker exec` to bypass SSH authentication bootstrap issues, followed by standard Terraform `remote-exec` (SSH) to verify connectivity.

## Goals

- **Learn Terraform workflows**: `init`, `plan`, `apply`, `destroy`.
- **Practice Resource Patterns**: VPC networking, security groups, user-data (cloud-init), and autoscaling.
- **Local-First Development**: Avoid cloud costs and credential management issues.

## Quick Start (Local)

1. **Start LocalStack**:

   ```bash
   docker compose up -d
   ```

2. **Run the Lab Helper**:
   The easiest way to start is using the helper script:

   ```bash
   ./lab-run.sh --apply
   ```

   _Note: This script handles SSH key generation, waits for LocalStack, and runs Terraform._

3. **Manual Terraform Workflow**:
   ```bash
   export TF_VAR_use_local=true
   make init
   make plan
   make apply
   ```

## SSH Access (Local)

The `lab-run.sh` script automatically generates an SSH keypair in `./.local/ssh/`. You can connect to the local "EC2" nodes using:

- **Bastion**: `ssh -i .local/ssh/id_rsa -p 2222 root@127.0.0.1`
- **Web Node**: `ssh -i .local/ssh/id_rsa -p 2223 root@127.0.0.1`

### Troubleshooting SSH host key warnings ⚠️

If you re-create the containers you may see an SSH host key mismatch warning when connecting (example: "REMOTE HOST IDENTIFICATION HAS CHANGED"). This is expected because container host keys change after recreation. To clear the old key and avoid the warning locally:

- Remove the old entry for the host/port from your `known_hosts`:
  - `ssh-keygen -R "[127.0.0.1]:2222"`
  - `ssh-keygen -R "[127.0.0.1]:2223"`

- Or manually edit `~/.ssh/known_hosts` and remove the offending line(s).

> Tip: When developing locally, use `./lab-run.sh --apply` to recreate containers. If you prefer faster iteration, you can build images locally (opt-in) and then run Terraform apply; however, by default image builds are performed by Terraform for reproducibility.

## Repository Structure

- `core/`: Main Terraform configuration.
  - `main.tf`: AWS resource definitions.
  - `docker_local.tf`: Local Docker emulation logic.
  - `templates/`: User-data and provisioning templates.
- `scripts/`: Helper scripts (e.g., `httpCheck`).
- `lab-run.sh`: Automation helper for local environment.

## Cleanup

```bash
./lab-run.sh --destroy
docker compose down -v
```

## Security

- Never commit real AWS credentials.
- Use `terraform.tfvars` (ignored by git) for sensitive variables when running against real AWS.
