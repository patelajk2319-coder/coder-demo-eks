# Coder on EKS

Deploys the Coder platform on Amazon Elastic Kubernetes Service: EKS, Amazon RDS for PostgreSQL, AWS Secrets Manager, and the Coder server itself, with full audit logging. This is the one-time platform bootstrap — re-run `infra`/`coder` only for infra changes or version upgrades, not routinely.

Workspaces, agent templates, and AI task provisioning live in a separate repo (if you have one) — this repo owns the platform layer only.

## Prerequisites

### AWS Requirements
- Active AWS account
- AWS CLI configured — either an SSO profile in `~/.aws/config` (`AWS_PROFILE=<profile>` in `.env`; `task login` opens the browser and authenticates automatically) or static credentials
- Admin-level IAM permissions to create VPC, EKS, RDS, Secrets Manager, CloudWatch, and IAM resources in the target account (the deploying identity needs `iam:*` for role/OIDC-provider management — a PowerUser-style policy without IAM access will not work)

### Required Tools (install via Homebrew)
```bash
brew install terraform awscli kubectl jq go-task coder shellcheck
```

## Configuration

Copy `.env.example` to `.env`.

**You fill in:**

| Variable Name | Description |
|----------------|-------------|
| `AWS_PROFILE` | Your AWS CLI profile |
| `CODER_ADMIN_EMAIL` | Coder admin login email (defaults to `admin@coder.demo`) |
| `CODER_ADMIN_PASSWORD` | Coder admin login password |
| `TF_VAR_postgres_admin_password` | RDS admin password |
| `GITHUB_OAUTH_CLIENT_ID` | GitHub OAuth App client ID (see below) |
| `GITHUB_OAUTH_CLIENT_SECRET` | GitHub OAuth App client secret (see below) |

**Written by the deploy scripts — leave blank:**

| Variable Name | Description |
|----------------|-------------|
| `CODER_ACCESS_URL` | Internal NLB hostname Coder is reachable at — written by `task coder` |
| `CODER_API_TOKEN` | API token for the `coderd` Terraform provider — written by `task init`, re-minted if the old one stops authenticating |
| `EKS_CLUSTER_NAME` | The EKS cluster's name — written by `task infra` |
| `RDS_ENDPOINT` | The RDS instance's connection endpoint — written by `task infra` |
| `RDS_DATABASE` | The Coder database name — written by `task infra` |
| `RDS_ADMIN_USERNAME` | The RDS admin username — written by `task infra` |

Region is fixed to `eu-west-1` in Terraform, not a variable — your
`AWS_PROFILE` must resolve to that region.

GitHub external auth uses device flow (a code entered at
`github.com/login/device`), not a redirect — enable "Device Flow" on the
GitHub OAuth App's settings page or authorization will fail.

## Node Pools

Three dedicated EKS node pools (`terraform/core-infra/main.tf`), each labeled
*and* tainted so nothing lands there without a matching `nodeSelector` +
toleration:

| Pool | Runs | Instance type |
|------|------|----------------|
| `coderd` | Coder server only (2 replicas, 1 vCPU/2Gi request, 2 vCPU/4Gi limit each — requests below limits so a rollout's surge pod has room) | `m6i.xlarge` |
| `system` | ALB controller, EBS CSI controller, CoreDNS, Secrets Store CSI driver | `m6i.large` |
| `workspaces` | Not created yet — deferred | — |

Per [Coder's validated-architectures guidance](https://coder.com/docs/admin/infrastructure/validated-architectures),
taken a step further: `coderd` is isolated from infrastructure too, not just
workspaces.

## Premium License (optional)

Optional: drop a Coder Premium license at `licence.lic` before
`task init`, or run `task coder-config` afterwards to apply it. Without one,
Coder runs on the open-source feature set.

Check what's currently applied with:
```bash
coder licenses list
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

Fill in the values described in [Configuration](#configuration) above — at minimum:
```env
CODER_ADMIN_PASSWORD=<your-secure-password>
TF_VAR_postgres_admin_password=<your-secure-password>
```

### 3. Deploy the Stack
```bash
task login  # Validate AWS credentials
task up     # Deploy everything: infra + coder + init (see Available Commands below)
```

### 4. Access Coder

Coder's LoadBalancer is internal-only (VPC-private) — nothing about this stack is reachable from the public internet. Reach it via port-forward:

```bash
task port-forward   # forwards localhost:8080 -> Coder, foreground (Ctrl-C to stop)
```

Then open `http://localhost:8080` in a browser and log in with
`CODER_ADMIN_EMAIL` / `CODER_ADMIN_PASSWORD` from your `.env`.

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
| `task up` | Full deploy — `infra` + `coder` + `init` (incl. platform config) in one command |
| `task infra` | Deploy EKS + RDS PostgreSQL + VPC + cluster add-ons |
| `task coder` | Deploy Coder Helm release to EKS |
| `task init` | Create Coder admin user + API token, then apply platform config via `coder-config` |
| `task coder-config` | Re-apply Coder platform config (license, provisioner keys) alone — e.g. after rotating `licence.lic` |
| `task provisioner-key` | Mint/fetch team-demo's provisioner key alone |
| `task clean` | Reset Coder to clean state (keeps EKS + RDS) |
| `task nuke` | Destroy all AWS infrastructure |
| `task status` | Check Coder pod status |
| `task pods` | List pods with node placement |
| `task ports` | Show Coder service and internal NLB hostname |
| `task port-forward` | Forward Coder to localhost:8080 for browser/CLI access |
| `task port-forward-stop` | Stop the persistent port-forward |
| `task nodes` | List EKS nodes |
| `task logs` | Stream Coder control plane logs |
| `task info` | Display connection info and credentials |
| `task audit-logs` | Export AI governance audit logs |
| `task ai-logs` | Export AI Bridge interception logs |
| `task connection-logs` | Export Coder connection logs |
| `task upgrade-coder` | Upgrade Coder to the latest (or a specific, `V=x.y.z`) version |
| `task rotate-secret` | Rotate a Secrets Manager secret (`SECRET_NAME=`, `SECRET_VALUE=`) and restart Coder |
| `task validate` | terraform fmt/validate (all `terraform/` dirs) + shellcheck |
| `task help` | List all available tasks |
