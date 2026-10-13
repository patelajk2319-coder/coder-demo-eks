# ── Argo CD (GitOps) ────────────────────────────────────────────────────────────
# Bootstraps the one thing that has to be installed before it can manage
# anything else — this release and the root Application stay Terraform-owned
# permanently; everything else it reconciles moves under gitops/.

locals {
  repo_root = abspath("${path.module}/../../../..")
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# Repo credential for this (private) repo's own GitOps source — never
# git-tracked, same treatment as an IRSA annotation.
resource "kubernetes_secret" "argocd_repo" {
  metadata {
    name      = "coder-demo-eks-repo"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    url      = "https://github.com/patelajk2319-coder/coder-demo-eks.git"
    username = "x-access-token"
    password = var.argocd_github_token
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "10.10.3"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [file("${local.repo_root}/helm-chart/coder-stack/values/argocd/argocd.yaml")]

  wait    = true
  timeout = 300

  depends_on = [kubernetes_secret.argocd_repo]
}

# The one AppProject scoping what Argo CD is allowed to touch, instead of
# accepting the chart's near-cluster-admin default.
resource "kubernetes_manifest" "argocd_project_platform" {
  manifest = yamldecode(file("${local.repo_root}/gitops/projects/platform-appproject.yaml"))

  depends_on = [helm_release.argocd]
}

# The one Application Terraform applies directly (app-of-apps) — everything
# else under gitops/ is declared inside it and reconciled from git from here on.
resource "kubernetes_manifest" "argocd_root_app" {
  manifest = yamldecode(file("${local.repo_root}/gitops/bootstrap/root-app.yaml"))

  depends_on = [kubernetes_manifest.argocd_project_platform]
}
