variable "prefix" {
  type        = string
  description = "Short company code, same as step 0 (e.g. 'grandhi')."
}

variable "company_name" {
  type        = string
  description = "Display name for the top management group."
  default     = "Grandhi"
}

variable "platform_subscription_id" {
  type        = string
  description = "The platform subscription — goes under the Platform MG."
}

variable "platform_admin_object_ids" {
  type        = list(string)
  description = "Entra object IDs of people to put in platform-admins. Get yours: az ad signed-in-user show --query id -o tsv"
  default     = []
}

variable "automation_object_ids" {
  type        = list(string)
  description = "Object IDs of automation identities (the pipeline's service principal) that must stay owners of the Entra groups. Get it: az ad sp show --id <client-id> --query id -o tsv"
  default     = []
}

output "management_group_ids" {
  description = "Used by step 2 (policy) to know where to attach policies."
  value = {
    root           = azurerm_management_group.root.id
    platform       = azurerm_management_group.platform.id
    landingzones   = azurerm_management_group.landingzones.id
    corp           = azurerm_management_group.corp.id
    online         = azurerm_management_group.online.id
    sandbox        = azurerm_management_group.sandbox.id
    decommissioned = azurerm_management_group.decommissioned.id
  }
}

output "group_object_ids" {
  value = { for k, g in azuread_group.this : k => g.object_id }
}
