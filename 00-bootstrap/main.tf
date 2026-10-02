# Step 0 — Bootstrap: a secure storage account for Terraform state.
# This project uses LOCAL state on purpose (chicken-and-egg: the backend
# can't store its own state before it exists). Run once, keep the local
# terraform.tfstate file safe (or migrate it into the new backend later).

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true # no storage keys — use Entra ID auth
}

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${var.prefix}-tfstate"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                            = "st${var.prefix}tfstate${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = "GRS" # state is precious — keep a copy in another region
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # force Entra ID auth, no keys lying around

  blob_properties {
    versioning_enabled = true # lets you roll back a broken state file
    delete_retention_policy { days = 30 }
    container_delete_retention_policy { days = 30 }
  }

  tags = var.tags
}

# You need data-plane rights to read/write blobs when keys are disabled.
resource "azurerm_role_assignment" "me_blob" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
  depends_on            = [azurerm_role_assignment.me_blob]
}

# Protect the state storage from accidental deletion.
resource "azurerm_management_lock" "tfstate" {
  name       = "lock-tfstate"
  scope      = azurerm_resource_group.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Holds Terraform state for the landing zone."
}
