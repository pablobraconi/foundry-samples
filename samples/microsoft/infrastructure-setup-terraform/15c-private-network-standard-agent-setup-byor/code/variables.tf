
variable "location" {
  description = "The name of the location to provision the resources to"
  type        = string
}

# Variables for existing resources
variable "existing_resource_group_name" {
  description = "The name of the existing resource group"
  type        = string
}

variable "existing_vnet_name" {
  description = "The name of the existing virtual network"
  type        = string
}

variable "existing_subnet_name" {
  description = "The name of the existing subnet"
  type        = string
}

variable "existing_search_name" {
  description = "The name of the existing AI Search service"
  type        = string
}

variable "existing_storage_account_name" {
  description = "The name of the existing storage account"
  type        = string
}

variable "existing_cosmosdb_name" {
  description = "The name of the existing Cosmos DB account"
  type        = string
}

variable "existing_foundry_name" {
  description = "The name of the existing AI Foundry resource"
  type        = string
}

variable "new_project_name" {
  description = "The name for the new AI Foundry project"
  type        = string
}
