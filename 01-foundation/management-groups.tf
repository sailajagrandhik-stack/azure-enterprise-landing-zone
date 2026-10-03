# Management groups = folders for subscriptions.
# Policies and RBAC set on a folder flow down to everything inside it.
# That's why this comes BEFORE policy: policy needs somewhere to attach.

resource "azurerm_management_group" "root" {
  name         = var.prefix # the ID — can't be changed later
  display_name = var.company_name
  # no parent => created directly under Tenant Root Group
}

resource "azurerm_management_group" "platform" {
  name                       = "${var.prefix}-platform"
  display_name               = "Platform"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "landingzones" {
  name                       = "${var.prefix}-landingzones"
  display_name               = "Landing Zones"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "corp" {
  name                       = "${var.prefix}-corp"
  display_name               = "Corp (internal apps)"
  parent_management_group_id = azurerm_management_group.landingzones.id
}

resource "azurerm_management_group" "online" {
  name                       = "${var.prefix}-online"
  display_name               = "Online (internet-facing apps)"
  parent_management_group_id = azurerm_management_group.landingzones.id
}

resource "azurerm_management_group" "sandbox" {
  name                       = "${var.prefix}-sandbox"
  display_name               = "Sandbox"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "decommissioned" {
  name                       = "${var.prefix}-decommissioned"
  display_name               = "Decommissioned"
  parent_management_group_id = azurerm_management_group.root.id
}

# Move the platform subscription into the Platform folder.
resource "azurerm_management_group_subscription_association" "platform" {
  management_group_id = azurerm_management_group.platform.id
  subscription_id     = "/subscriptions/${var.platform_subscription_id}"
}
