# Identity: WHO can do WHAT, WHERE.
# Rule #1: give access to GROUPS, never to individual people.
# People join/leave groups; the RBAC below never has to change.

locals {
  groups = {
    platform-admins = "Full control of the Azure platform (use PIM in real life)"
    platform-ops    = "Day-to-day platform operations, no permission changes"
    security-team   = "Read-only view of everything + security settings"
    app-developers  = "Build and run apps inside landing zones"
    readers         = "Read-only access to everything (auditors, managers)"
  }

  # group => list of { mg, role }
  role_map = {
    platform-admins = [
      { mg = "root", role = "Owner" },
    ]
    platform-ops = [
      { mg = "platform", role = "Contributor" },
      { mg = "root", role = "Reader" },
    ]
    security-team = [
      { mg = "root", role = "Security Admin" },
      { mg = "root", role = "Reader" },
    ]
    app-developers = [
      { mg = "landingzones", role = "Contributor" },
      { mg = "sandbox", role = "Contributor" },
    ]
    readers = [
      { mg = "root", role = "Reader" },
    ]
  }

  mg_ids = {
    root         = azurerm_management_group.root.id
    platform     = azurerm_management_group.platform.id
    landingzones = azurerm_management_group.landingzones.id
    sandbox      = azurerm_management_group.sandbox.id
  }

  # Flatten into one map so for_each gets a stable key per assignment.
  assignments = {
    for a in flatten([
      for g, list in local.role_map : [
        for r in list : { key = "${g}|${r.mg}|${r.role}", group = g, mg = r.mg, role = r.role }
      ]
    ]) : a.key => a
  }
}

resource "azuread_group" "this" {
  for_each         = local.groups
  display_name     = "grp-${var.prefix}-${each.key}"
  description      = each.value
  security_enabled = true
  # Owners are listed EXPLICITLY (admins + the pipeline's identity), never
  # "whoever runs Terraform" — otherwise a laptop plan and a pipeline plan
  # would disagree about who the owners should be.
  owners = distinct(concat(var.platform_admin_object_ids, var.automation_object_ids))
}

resource "azurerm_role_assignment" "this" {
  for_each             = local.assignments
  scope                = local.mg_ids[each.value.mg]
  role_definition_name = each.value.role
  principal_id         = azuread_group.this[each.value.group].object_id
  principal_type       = "Group"
}

# Put the named people in platform-admins, so they keep access after
# "elevated access" is turned back off. Listed by ID on purpose: when the
# pipeline runs Terraform, "current user" is the pipeline, not you.
resource "azuread_group_member" "platform_admins" {
  for_each         = toset(var.platform_admin_object_ids)
  group_object_id  = azuread_group.this["platform-admins"].object_id
  member_object_id = each.value
}
