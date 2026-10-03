# Added AFTER the first apply: the storage didn't exist before that.
terraform {
  backend "azurerm" {
    key = "00-bootstrap.tfstate"
  }
}
