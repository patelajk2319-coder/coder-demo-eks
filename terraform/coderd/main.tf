data "coderd_organization" "default" {
  is_default = true
}

# Optional — skipped entirely if licence.lic isn't present, matching
# 30_init_coder.sh's prior "check for the file, skip if absent" behaviour.
# create_before_destroy per the provider's own docs: without it, a license
# rotation removes the old license before adding the new one, briefly
# disabling licensed features for users.
resource "coderd_license" "this" {
  count   = fileexists(var.licence_path) ? 1 : 0
  license = file(var.licence_path)

  lifecycle {
    create_before_destroy = true
  }
}

# One concrete resource per team, not a for_each map — this is the only
# external provisioner in use today (coder-team-cluster-demo). Add another
# named resource when a second team is actually onboarded, rather than
# generalizing ahead of need.
resource "coderd_provisioner_key" "team_demo" {
  name            = "team-demo"
  organization_id = data.coderd_organization.default.id
  tags = {
    team = "demo"
  }
}
