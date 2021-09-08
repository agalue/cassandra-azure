# Author: Alejandro Galue <agalue@opennms.org>

locals {
  resource_group = var.resource_group_create ? azurerm_resource_group.main[0].name : var.resource_group_name
  # For resource tagging purposes
  required_tags = {
    Environment = "Test"
    Department  = "Support"
    Owner       = var.username
  }
}

resource "azurerm_resource_group" "main" {
  count    = var.resource_group_create ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = local.required_tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.username}-cassandra-vnet"
  location            = var.location
  resource_group_name = local.resource_group
  address_space       = [var.address_space]
  tags                = local.required_tags
}

resource "azurerm_subnet" "cassandra" {
  name                 = "main"
  resource_group_name  = local.resource_group
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet]
}