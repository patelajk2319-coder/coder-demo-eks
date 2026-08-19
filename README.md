# Coder on EKS

Deploys the Coder platform on Amazon Elastic Kubernetes Service: EKS, Amazon RDS for PostgreSQL, AWS Secrets Manager, and the Coder server itself, with full audit logging. This is the one-time platform bootstrap — re-run `infra`/`coder` only for infra changes or version upgrades, not routinely.

Workspaces, agent templates, and AI task provisioning live in a separate repo (if you have one) — this repo owns the platform layer only.

## Prerequisites

### AWS Requirements
- Active AWS account
- AWS CLI configured — either an SSO profile in `~/.aws/config` (`AWS_PROFILE=<profile>` in `.env`; `task login` opens the browser and authenticates automatically, like `az login` in the AKS version) or static credentials
- Admin-level IAM permissions to create VPC, EKS, RDS, Secrets Manager, CloudWatch, and IAM resources in the target account (the deploying identity needs `iam:*` for role/OIDC-provider management — a PowerUser-style policy without IAM access will not work)

### Required Tools (install via Homebrew)
```bash
brew install terraform awscli kubectl jq go-task coder
```

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/patelajk2319-coder/coder-demo-eks.git
cd coder-demo-eks
```

### 2. Create `.env` File
```bash
cp .env.example .env
```

Fill in the required values:
```env
AWS_REGION=eu-west-1
AWS_PROFILE=default

CODER_ADMIN_PASSWORD=<your-secure-password>
TF_VAR_postgres_admin_password=<your-secure-password>
ANTHROPIC_API_KEY=<your-anthropic-key>
```

### 3. Deploy the Stack
```bash
task login  # Validate AWS credentials
task infra  # EKS cluster + RDS PostgreSQL + VPC + cluster add-ons
task coder  # Coder Helm release
task init   # Create admin user, write credentials to coder-init.json
```

### 4. Access Coder

Coder's LoadBalancer is internal-only (VPC-private) — nothing about this stack is reachable from the public internet. Reach it via port-forward:

```bash
task port-forward   # forwards localhost:8080 -> Coder, foreground (Ctrl-C to stop)
```

Then open `http://localhost:8080` in a browser.

Run `task info` to see the internal access URL, admin credentials, and cluster state.

## Cleanup

```bash
# Reset Coder (keeps EKS + RDS running — re-deploy with task coder && task init)
task clean

# Destroy all AWS infrastructure including EKS and RDS
task nuke
```

## Available Commands

| Task | Description |
|------|-------------|
| `task login` | Validate AWS credentials |
| `task infra` | Deploy EKS + RDS PostgreSQL + VPC + cluster add-ons |
| `task coder` | Deploy Coder Helm release to EKS |
| `task init` | Create Coder admin user and write credentials |
| `task clean` | Reset Coder to clean state (keeps EKS + RDS) |
| `task nuke` | Destroy all AWS infrastructure |
| `task status` | Check Coder pod status |
| `task pods` | List pods with node placement |
| `task ports` | Show Coder service and internal NLB hostname |
| `task port-forward` | Forward Coder to localhost:8080 for browser/CLI access |
| `task nodes` | List EKS nodes |
| `task logs` | Stream Coder control plane logs |
| `task info` | Display connection info and credentials |
| `task audit-logs` | Export AI governance audit logs |
| `task ai-logs` | Export AI Bridge interception logs |
