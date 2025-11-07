########## Create infrastructure resources
##########

## Get subscription data
##

data "azurerm_client_config" "current" {}

# Use existing resource group
data "azurerm_resource_group" "rg" {
  name = var.existing_resource_group_name
}

# Use existing virtual network
data "azurerm_virtual_network" "vnet" {
  name                = var.existing_vnet_name
  resource_group_name = var.existing_resource_group_name
}

# Use existing subnets
data "azurerm_subnet" "subnet_agent" {
  name                 = var.existing_subnet_name
  virtual_network_name = data.azurerm_virtual_network.vnet.name
  resource_group_name  = var.existing_resource_group_name
}

########## Create resoures required to store agent data
##########

# Use existing storage account
data "azurerm_storage_account" "storage_account" {
  name                = var.existing_storage_account_name
  resource_group_name = var.existing_resource_group_name
}

# Use existing Cosmos DB account
data "azurerm_cosmosdb_account" "cosmosdb" {
  name                = var.existing_cosmosdb_name
  resource_group_name = var.existing_resource_group_name
}

# Use existing AI Search service
data "azurerm_search_service" "ai_search" {
  name                = var.existing_search_name
  resource_group_name = var.existing_resource_group_name
}

########## Create AI Foundry resource
##########

# Use existing AI Foundry resource
data "azapi_resource" "ai_foundry" {
  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name      = var.existing_foundry_name
  parent_id = data.azurerm_resource_group.rg.id
}



########## Create the AI Foundry project, project connections, role assignments, and project-level capability host
##########

## Create NEW AI Foundry project in existing Foundry
##
resource "azapi_resource" "ai_foundry_project" {
  depends_on = [
    data.azapi_resource.ai_foundry
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name                      = var.new_project_name
  parent_id                 = data.azapi_resource.ai_foundry.id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    sku = {
      name = "S0"
    }
    identity = {
      type = "SystemAssigned"
    }

    properties = {
      displayName = var.new_project_name
      description = "A project for AI Foundry account"
    }
  }

  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]
}

## Wait 10 seconds for the AI Foundry project system-assigned managed identity to be created and to replicate
## through Entra ID
resource "time_sleep" "wait_project_identities" {
  depends_on = [
    azapi_resource.ai_foundry_project
  ]
  create_duration = "10s"
}

## Create AI Foundry project connections with unique names
##
resource "azapi_resource" "conn_cosmosdb" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = "${data.azurerm_cosmosdb_account.cosmosdb.name}-${var.new_project_name}"
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  depends_on = [
    azapi_resource.ai_foundry_project
  ]

  body = {
    name = "${data.azurerm_cosmosdb_account.cosmosdb.name}-${var.new_project_name}"
    properties = {
      category = "CosmosDb"
      target   = data.azurerm_cosmosdb_account.cosmosdb.endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = data.azurerm_cosmosdb_account.cosmosdb.id
        location   = var.location
      }
    }
  }
}

## Create the AI Foundry project connection to Azure Storage Account
##
resource "azapi_resource" "conn_storage" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = "${data.azurerm_storage_account.storage_account.name}-${var.new_project_name}"
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  depends_on = [
    azapi_resource.ai_foundry_project
  ]

  body = {
    name = "${data.azurerm_storage_account.storage_account.name}-${var.new_project_name}"
    properties = {
      category = "AzureStorageAccount"
      target   = data.azurerm_storage_account.storage_account.primary_blob_endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = data.azurerm_storage_account.storage_account.id
        location   = var.location
      }
    }
  }

  response_export_values = [
    "identity.principalId"
  ]
}

## Create the AI Foundry project connection to AI Search
##
resource "azapi_resource" "conn_aisearch" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = "${data.azurerm_search_service.ai_search.name}-${var.new_project_name}"
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  depends_on = [
    azapi_resource.ai_foundry_project
  ]

  body = {
    name = "${data.azurerm_search_service.ai_search.name}-${var.new_project_name}"
    properties = {
      category = "CognitiveSearch"
      target   = "https://${data.azurerm_search_service.ai_search.name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2025-05-01-preview"
        ResourceId = data.azurerm_search_service.ai_search.id
        location   = var.location
      }
    }
  }

  response_export_values = [
    "identity.principalId"
  ]
}

## Create the necessary role assignments for the AI Foundry project over the resources used to store agent data
##
resource "azurerm_role_assignment" "cosmosdb_operator_ai_foundry_project" {
  depends_on = [
    resource.time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${azapi_resource.ai_foundry_project.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${data.azurerm_resource_group.rg.name}cosmosdboperator")
  scope                = data.azurerm_cosmosdb_account.cosmosdb.id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_role_assignment" "storage_blob_data_contributor_ai_foundry_project" {
  depends_on = [
    resource.time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${azapi_resource.ai_foundry_project.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${data.azurerm_storage_account.storage_account.name}storageblobdatacontributor")
  scope                = data.azurerm_storage_account.storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_role_assignment" "search_index_data_contributor_ai_foundry_project" {
  depends_on = [
    resource.time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${azapi_resource.ai_foundry_project.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${data.azurerm_search_service.ai_search.name}searchindexdatacontributor")
  scope                = data.azurerm_search_service.ai_search.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_role_assignment" "search_service_contributor_ai_foundry_project" {
  depends_on = [
    resource.time_sleep.wait_project_identities
  ]
  name                 = uuidv5("dns", "${azapi_resource.ai_foundry_project.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${data.azurerm_search_service.ai_search.name}searchservicecontributor")
  scope                = data.azurerm_search_service.ai_search.id
  role_definition_name = "Search Service Contributor"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

## Pause 60 seconds to allow for role assignments to propagate
##
resource "time_sleep" "wait_rbac" {
  depends_on = [
    azurerm_role_assignment.cosmosdb_operator_ai_foundry_project,
    azurerm_role_assignment.storage_blob_data_contributor_ai_foundry_project,
    azurerm_role_assignment.search_index_data_contributor_ai_foundry_project,
    azurerm_role_assignment.search_service_contributor_ai_foundry_project
  ]
  create_duration = "60s"
}

## Create the AI Foundry project capability host
##
resource "azapi_resource" "ai_foundry_project_capability_host" {
  depends_on = [
    azapi_resource.conn_aisearch,
    azapi_resource.conn_cosmosdb,
    azapi_resource.conn_storage,
    time_sleep.wait_rbac
  ]
  type                      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name                      = "caphostproj"
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind = "Agents"
      vectorStoreConnections = [
        "${data.azurerm_search_service.ai_search.name}-${var.new_project_name}"
      ]
      storageConnections = [
        "${data.azurerm_storage_account.storage_account.name}-${var.new_project_name}"
      ]
      threadStorageConnections = [
        "${data.azurerm_cosmosdb_account.cosmosdb.name}-${var.new_project_name}"
      ]
    }
  }
}

## Create the necessary data plane role assignments to the existing CosmosDb databases
##
resource "azurerm_cosmosdb_sql_role_assignment" "cosmosdb_db_sql_role_aifp_user_thread_message_store" {
  depends_on = [
    azapi_resource.ai_foundry_project_capability_host
  ]
  name                = uuidv5("dns", "${azapi_resource.ai_foundry_project.name}${azapi_resource.ai_foundry_project.output.identity.principalId}userthreadmessage_dbsqlrole")
  resource_group_name = data.azurerm_resource_group.rg.name
  account_name        = data.azurerm_cosmosdb_account.cosmosdb.name
  scope               = "${data.azurerm_cosmosdb_account.cosmosdb.id}/dbs/enterprise_memory/colls/${local.project_id_guid}-thread-message-store"
  role_definition_id  = "${data.azurerm_cosmosdb_account.cosmosdb.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_cosmosdb_sql_role_assignment" "cosmosdb_db_sql_role_aifp_system_thread_name" {
  depends_on = [
    azurerm_cosmosdb_sql_role_assignment.cosmosdb_db_sql_role_aifp_user_thread_message_store
  ]
  name                = uuidv5("dns", "${azapi_resource.ai_foundry_project.name}${azapi_resource.ai_foundry_project.output.identity.principalId}systemthread_dbsqlrole")
  resource_group_name = data.azurerm_resource_group.rg.name
  account_name        = data.azurerm_cosmosdb_account.cosmosdb.name
  scope               = "${data.azurerm_cosmosdb_account.cosmosdb.id}/dbs/enterprise_memory/colls/${local.project_id_guid}-system-thread-message-store"
  role_definition_id  = "${data.azurerm_cosmosdb_account.cosmosdb.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_cosmosdb_sql_role_assignment" "cosmosdb_db_sql_role_aifp_entity_store_name" {
  depends_on = [
    azurerm_cosmosdb_sql_role_assignment.cosmosdb_db_sql_role_aifp_system_thread_name
  ]
  name                = uuidv5("dns", "${azapi_resource.ai_foundry_project.name}${azapi_resource.ai_foundry_project.output.identity.principalId}entitystore_dbsqlrole")
  resource_group_name = data.azurerm_resource_group.rg.name
  account_name        = data.azurerm_cosmosdb_account.cosmosdb.name
  scope               = "${data.azurerm_cosmosdb_account.cosmosdb.id}/dbs/enterprise_memory/colls/${local.project_id_guid}-agent-entity-store"
  role_definition_id  = "${data.azurerm_cosmosdb_account.cosmosdb.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.ai_foundry_project.output.identity.principalId
}

## Create the necessary data plane role assignments to the existing Azure Storage Account containers
##
resource "azurerm_role_assignment" "storage_blob_data_owner_ai_foundry_project" {
  depends_on = [
    azapi_resource.ai_foundry_project_capability_host
  ]
  name                 = uuidv5("dns", "${azapi_resource.ai_foundry_project.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${data.azurerm_storage_account.storage_account.name}storageblobdataowner")
  scope                = data.azurerm_storage_account.storage_account.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
  condition_version    = "2.0"
  condition            = <<-EOT
  (
    (
      !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read'})
      AND !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action'})
      AND !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write'})
    )
    OR
    (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase '${local.project_id_guid}'
    AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase '*-azureml-agent')
  )
  EOT
}

## Added AI Foundry account purger to avoid running into InUseSubnetCannotBeDeleted-lock caused by the agent subnet delegation.
## The azapi_resource_action.purge_ai_foundry (only gets executed during destroy) purges the AI foundry account removing /subnets/snet-agent/serviceAssociationLinks/legionservicelink so the agent subnet can get properly removed.

resource "azapi_resource_action" "purge_ai_foundry" {
  method      = "DELETE"
  resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.CognitiveServices/locations/${data.azurerm_resource_group.rg.location}/resourceGroups/${data.azurerm_resource_group.rg.name}/deletedAccounts/${var.existing_foundry_name}"
  type        = "Microsoft.Resources/resourceGroups/deletedAccounts@2021-04-30"
  when        = "destroy"

  depends_on = [time_sleep.purge_ai_foundry_cooldown]
}

resource "time_sleep" "purge_ai_foundry_cooldown" {
  destroy_duration = "900s" # 10-15m is enough time to let the backend remove the /subnets/snet-agent/serviceAssociationLinks/legionservicelink

  depends_on = [data.azurerm_subnet.subnet_agent]
}
