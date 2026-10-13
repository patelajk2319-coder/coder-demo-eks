output "team_demo_provisioner_key" {
  description = "Provisioner key for the team-demo external provisioner"
  value       = coderd_provisioner_key.team_demo.key
  sensitive   = true
}
