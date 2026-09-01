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

## Configuration

All configuration lives in `.env`, copied from `.env.example`. `.env` is gitignored —
it holds real credentials and must never be committed. `.env.example` mirrors `.env`
exactly (same variable names) and is the only one of the two safe to commit.

`.env.example` has two kinds of variables, and each is labelled with a comment so it's
clear which is which:

- **You fill these in**: `AWS_PROFILE`, `CODER_ADMIN_PASSWORD`,
  `TF_VAR_postgres_admin_password`, `ANTHROPIC_API_KEY` (a placeholder is fine if you
  don't need AI Bridge features yet — see the comment above it), `GITHUB_OAUTH_CLIENT_ID`
  / `GITHUB_OAUTH_CLIENT_SECRET` (from a GitHub OAuth App — see the comment above them),
  plus a couple that already have sensible defaults (`CODER_ADMIN_EMAIL`, `CODER_VERSION`).
- **The deploy scripts write these** — leave them blank: `CODER_ACCESS_URL` (written by
  `task coder`) and `EKS_CLUSTER_NAME` / `RDS_ENDPOINT` / `RDS_DATABASE` (written by
  `task infra`).

External auth (`CODER_EXTERNAL_AUTH_*`) lets workspace templates authenticate git
operations as each developer's own GitHub identity via `data.coder_external_auth`,
instead of a shared PAT baked into the template. It uses GitHub's device flow (a
code entered at `github.com/login/device`), not a browser-redirect callback —
required here because `CODER_ACCESS_URL` is the internal NLB hostname, which a
developer's browser can never land back on after a redirect. Enable "Device Flow"
on the GitHub OAuth App itself (its settings page, alongside the Client ID/Secret)
or authorization will fail.

There's no region variable — it's fixed to `eu-west-1` directly in Terraform (a
single-region demo stack, not something meant to be reconfigured per-deploy). Your
`AWS_PROFILE` needs to resolve to that region. Terraform state is also how the three
`terraform/` directories talk to each other, via `terraform_remote_state` instead of
scripts threading `-var` flags: `core-infra` (VPC, EKS, RDS, Secrets Manager — pure
AWS, no kubernetes/helm needed) is read directly by both `addons` (the AWS Load
Balancer Controller and Secrets Store CSI driver — the only things that actually
need kubernetes/helm) and `coder` (the Helm release).

## Premium License (optional)

If you have a Coder Premium license, drop the file at `licence.lic` in the repo
root before running `task init` (or re-run `task init` any time afterwards —
it's idempotent). `licence.lic` is gitignored (`*.lic`) and must never be
committed; if it's absent, `task init` just skips this step and Coder runs on
the open-source feature set as normal.

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
ANTHROPIC_API_KEY=<your-anthropic-key>
```

### 3. Deploy the Stack
```bash
task login  # Validate AWS credentials
task infra  # EKS cluster + RDS PostgreSQL + VPC + cluster add-ons
task coder  # Coder Helm release
task init   # Create admin user, write credentials, apply licence.lic if present
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
| `task init` | Create Coder admin user, write credentials, apply `licence.lic` if present |
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
| `task help` | List all available tasks |
