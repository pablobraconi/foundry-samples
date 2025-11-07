# Setup providers
provider "azapi" {
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
  subscription_id     = "2e405fb4-a6e2-41c8-8809-9ca54dffc2a4"
}
