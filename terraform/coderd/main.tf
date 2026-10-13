data "coderd_organization" "default" {
  is_default = true
}

# Optional — skipped if licence.lic isn't present. create_before_destroy so a
# rotation doesn't briefly disable licensed features.
resource "coderd_license" "this" {
  count   = fileexists(var.licence_path) ? 1 : 0
  license = file(var.licence_path)

  lifecycle {
    create_before_destroy = true
  }
}

# Concrete resource, not for_each — only one external provisioner exists
# today. Add another when a second team is onboarded.
resource "coderd_provisioner_key" "team_demo" {
  name            = "team-demo"
  organization_id = data.coderd_organization.default.id
  tags = {
    team = "demo"
  }
}
