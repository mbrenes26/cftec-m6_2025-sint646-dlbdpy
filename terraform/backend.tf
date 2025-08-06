terraform {
  backend "azurerm" {
    resource_group_name   = "rg-cftec-sint-646-tfstate"
    storage_account_name  = "sint646sttfstatecenfotec"
    container_name        = "tfstate"
    key                   = "cftec-m6_2025-sint646-dlbdpy.tfstate"
  }
}
