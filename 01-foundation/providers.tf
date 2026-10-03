terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azuread = { source = "hashicorp/azuread", version = "~> 3.0" }
  }

  # Values come from ../backend.hcl (created in step 0).
  backend "azurerm" {
    key = "01-foundation.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.platform_subscription_id
}

provider "azuread" {}

data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}
