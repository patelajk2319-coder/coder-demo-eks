output "team_demo_provisioner_key" {
  description = "Provisioner key for coder-team-cluster-demo's external provisioner — copy into that repo's .env as CODER_PROVISIONER_KEY"
  value       = coderd_provisioner_key.team_demo.key
  sensitive   = true
}
