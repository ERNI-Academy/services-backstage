terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "2.89.0"
    }
    azuread = {
      source = "hashicorp/azuread"
      version = "2.12.0"
    }
    github = {
      source = "integrations/github"
      version = "4.19.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {
}

provider "github" {
  owner = var.github_organization
  token = var.github_token
}

locals {
  resource_group = "${var.service_name}rg"
  custom_domain = "${var.service_name}app.azurewebsites.net"
  pg_server = "${var.service_name}psql"
  pg_user = "backstage@${var.service_name}psql"
  pg_host = "${var.service_name}psql.postgres.database.azure.com"
  techdocs_storage_name = "${var.service_name}storage"
  techdocs_container_name = "${var.service_name}techdocs"
  app_insights_name = "${var.service_name}appi"
  app_plan = "${var.service_name}plan"
  backstage_app_name = "${var.service_name}app"
}

data "azurerm_client_config" "current" { }

resource "azurerm_resource_group" "backstage_rg" {
  name     = local.resource_group
  location = var.location
}

resource "azurerm_storage_account" "techdocs_storage" {
  name                     = local.techdocs_storage_name
  resource_group_name      = azurerm_resource_group.backstage_rg.name
  location                 = azurerm_resource_group.backstage_rg.location
  allow_blob_public_access = false
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "techdocs_storage_container" {
  name                  = local.techdocs_container_name
  storage_account_name  = azurerm_storage_account.techdocs_storage.name
  container_access_type = "private"
}

resource "azurerm_application_insights" "app_insights" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.backstage_rg.location
  resource_group_name = azurerm_resource_group.backstage_rg.name
  application_type    = "other"
}

resource "azurerm_app_service_plan" "backstage_app_plan" {
  name                = local.app_plan
  location            = azurerm_resource_group.backstage_rg.location
  resource_group_name = azurerm_resource_group.backstage_rg.name
  kind                = "Linux"
  reserved            = true

  sku {
    tier = "Basic"
    size = "B1"
  }
}

resource "azurerm_postgresql_server" "backstage_postgresql" {
  name                = local.pg_server
  location            = azurerm_resource_group.backstage_rg.location
  resource_group_name = azurerm_resource_group.backstage_rg.name

  sku_name = "B_Gen5_1"

  storage_mb                   = 5120
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled            = false

  administrator_login          = var.db_admin_username
  administrator_login_password = var.db_admin_password
  version                      = "11"
  ssl_enforcement_enabled      = true
}

resource "azurerm_postgresql_firewall_rule" "example" {
  name                = "AllowAll"
  resource_group_name = azurerm_resource_group.backstage_rg.name
  server_name         = azurerm_postgresql_server.backstage_postgresql.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "255.255.255.255"
}

resource "azurerm_postgresql_database" "backstage_postgresql_database" {
  name                = "docs"
  resource_group_name = azurerm_resource_group.backstage_rg.name
  server_name         = azurerm_postgresql_server.backstage_postgresql.name
  charset             = "UTF8"
  collation           = "en-US"
}

resource "azurerm_app_service" "backstage_app" {
  name                = local.backstage_app_name
  location            = azurerm_resource_group.backstage_rg.location
  resource_group_name = azurerm_resource_group.backstage_rg.name
  app_service_plan_id = azurerm_app_service_plan.backstage_app_plan.id

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "AZURE_CLIENT_ID" = var.azure_client_id
    "AZURE_CLIENT_SECRET" = var.azure_client_secret
    "AZURE_TENANT_ID" = var.azure_tenant_id
    "POSTGRES_HOST" = local.pg_host
    "POSTGRES_PORT" = var.postgres_port
    "POSTGRES_USER" = local.pg_user
    "POSTGRES_PASSWORD" = var.db_admin_password
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.app_insights.instrumentation_key
    "DOCKER_REGISTRY_SERVER_USERNAME" = var.container_registry_username
    "DOCKER_REGISTRY_SERVER_PASSWORD" = var.container_registry_password
    "CUSTOM_DOMAIN" = local.custom_domain
    "GITHUB_TOKEN" = var.github_token
    "GITHUB_ORG_OATH_CLIENT_ID" = var.github_org_oath_client_id
    "GITHUB_ORG_OATH_CLIENT_SECRET" = var.github_org_oath_client_secret
    "TECHDOCS_CONTAINER_NAME" = azurerm_storage_container.techdocs_storage_container.name
    "TECHDOCS_STORAGE_ACCOUNT" = azurerm_storage_account.techdocs_storage.name
  }
}

#resource "azurerm_container_registry" "acr" {
#  name                = "${var.service_name}acr"
#  resource_group_name = azurerm_resource_group.backstage_rg.name
#  location            = azurerm_resource_group.backstage_rg.location
#  sku                 = "Basic"
#  admin_enabled       = false
#}

resource "github_actions_organization_secret" "registry_login_server" {
  secret_name     = "REGISTRY_LOGIN_SERVER"
  visibility      = "all"
  plaintext_value = var.container_registry_login_server
}

resource "github_actions_organization_secret" "registry_username" {
  secret_name     = "REGISTRY_USERNAME"
  visibility      = "all"
  plaintext_value = var.container_registry_username
}

resource "github_actions_organization_secret" "registry_password" {
  secret_name     = "REGISTRY_PASSWORD"
  visibility      = "all"
  plaintext_value = var.container_registry_password
}

resource "github_actions_secret" "app_name" {
  repository       = var.github_repository_name
  secret_name      = "APP_NAME"
  plaintext_value  = azurerm_app_service.backstage_app.name
}

resource "github_actions_organization_secret" "github_techdocs_container_name" {
  visibility       = "all"
  secret_name      = "TECHDOCS_CONTAINER_NAME"
  plaintext_value  = azurerm_storage_container.techdocs_storage_container.name
}

resource "github_actions_organization_secret" "github_techdocs_storage_account_name" {
  visibility       = "all"
  secret_name      = "TECHDOCS_STORAGE_ACCOUNT"
  plaintext_value  = azurerm_storage_account.techdocs_storage.name
}

resource "github_actions_organization_secret" "github_azure_subscription_id" {
  visibility       = "all"
  secret_name      = "AZURE_SUBSCRIPTION_ID"
  plaintext_value  = var.azure_subscription_id
}

resource "github_actions_organization_secret" "github_azure_tenant_id" {
  visibility       = "all"
  secret_name      = "AZURE_TENANT_ID"
  plaintext_value  = var.azure_tenant_id
}

resource "github_actions_organization_secret" "github_azure_client_id" {
  visibility       = "all"
  secret_name      = "AZURE_CLIENT_ID"
  plaintext_value  = var.azure_client_id
}

resource "github_actions_organization_secret" "github_azure_client_secret" {
  visibility       = "all"
  secret_name      = "AZURE_CLIENT_SECRET"
  plaintext_value  = var.azure_client_secret
}

resource "github_actions_organization_secret" "github_organization" {
  visibility       = "all"
  secret_name      = "ORGANIZATION"
  plaintext_value  = var.github_organization
}

resource "github_actions_organization_secret" "github_token" {
  visibility       = "all"
  secret_name      = "TOKEN"
  plaintext_value  = var.github_token
}

resource "github_actions_secret" "azure_credentials" {
  repository       = var.github_repository_name
  secret_name      = "AZURE_CREDENTIALS"
  plaintext_value  = jsonencode({
    "clientId" = var.azure_client_id
    "clientSecret" = var.azure_client_secret
    "subscriptionId" = var.azure_subscription_id
    "tenantId" = var.azure_tenant_id
  })
}