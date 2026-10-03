variable "subscription_id" {
  type        = string
  description = "Subscription that will hold the state storage (your platform subscription)."
}

variable "prefix" {
  type        = string
  description = "Short lowercase company code, letters/numbers only (e.g. 'grandhi'). Max ~8 chars."
  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.prefix))
    error_message = "prefix must be 2-8 lowercase letters/numbers."
  }
}

variable "location" {
  type    = string
  default = "southcentralus"
}

variable "tags" {
  type = map(string)
  default = {
    owner       = "platform-team"
    environment = "platform" # required by the step 2 tag policy
    managed_by  = "terraform"
    purpose     = "tfstate"
  }
}

output "storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}

# Paste-ready backend config for every later step.
output "backend_config" {
  value = <<-EOT
    resource_group_name  = "${azurerm_resource_group.tfstate.name}"
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
    use_azuread_auth     = true
  EOT
}
