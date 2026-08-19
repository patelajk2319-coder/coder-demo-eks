# CLAUDE.md — Project Standards

## Scope
This repo owns the platform layer only: EKS, RDS PostgreSQL, Secrets Manager, and
the Coder server. It never defines `coder_agent`/`coder_app`/templates or creates
workspaces — that belongs in a separate workspaces/templates repo. RBAC granted
here (e.g. the workspace-provisioner ClusterRole) is the platform's job since it's
a cluster security boundary, but *what* gets provisioned with it is not.

## Language
US English throughout all documentation, comments, and output strings.

## Shell Scripts
- Strict mode in every script: `set -euo pipefail`
- Source `scripts/lib/colors.sh` for all output (never raw `echo` with colour codes)
- Source `scripts/lib/cluster_context.sh` before any `kubectl` or `helm` invocation
- All scripts must be idempotent — safe to re-run without side effects
- Validate required environment variables at the top of each script using `: "${VAR:?message}"`

## Terraform
- Official providers only — never community forks (`hashicorp/aws`, `hashicorp/kubernetes`, `hashicorp/helm`, `hashicorp/tls`)
- Version constraints: `~>` for providers, `>= 1.5.0` for Terraform itself
- No heredocs for Kubernetes manifests — use `yamlencode()`
- One module per logical concern; no monolithic main.tf files
- All sensitive outputs marked `sensitive = true`
- IAM roles follow least privilege — scope policies to specific resource ARNs, not `*`, wherever the AWS API allows it

## Helm
- Official charts only, pinned to explicit versions — never `latest`
- All values externalised to `helm-chart/coder-stack/values/<component>/<component>.yaml`
- No inline `--set` flags in scripts for non-trivial values

## Taskfile
- Tasks must have a `desc:` field
- Tasks that call scripts pass through `.env` via the `dotenv` directive at file root
- Deployment order: `login` → `infra` → `coder` → `init`
- Cleanup order: `clean` (keep EKS running) or `nuke` (destroy everything)

## Deployment Workflow
Strict ordering must be followed:
1. `task login`  — validate AWS credentials
2. `task infra`  — deploy EKS cluster + RDS PostgreSQL + cluster add-ons via Terraform
3. `task coder`  — deploy Coder to EKS via Terraform (Helm release)
4. `task init`   — create admin user + write credentials to coder-init.json

## Governance Notes (for interview context)
- LLM API keys are stored in AWS Secrets Manager, read into the `coder` namespace
  only via the Secrets Store CSI Driver
- They are never injected into workspace pod specs
- Workspace pods run in isolated namespaces: `coder-ws-<owner>-<workspace>`
- NetworkPolicy restricts workspace egress to an explicit allowlist

## Network Exposure
- Coder's service LoadBalancer is internal-only (VPC-private, via the AWS Load
  Balancer Controller) — never expose it publicly
- Access from outside the VPC goes through `task port-forward` / `scripts/lib/port_forward.sh`
- `CODER_ACCESS_URL` is the internal NLB hostname, advertised to workspace agents
  — scripts outside the cluster must use the local port-forward, not this URL directly
- The EKS API server itself stays public so `kubectl`/`helm`/Terraform work from the deploy machine; cluster access is IAM-native (EKS Access Entries), not the legacy aws-auth ConfigMap
