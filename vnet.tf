# Author: Alejandro Galue <agalue@opennms.org>

locals {
  resource_group = var.resource_group_create ? azurerm_resource_group.main[0].name : var.resource_group_name
  vnet           = var.resource_group_create ? azurerm_virtual_network.main[0].name : var.vnet_name
}

resource "azurerm_resource_group" "main" {
  count    = var.resource_group_create ? 1 : 0
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_virtual_network" "main" {
  count               = var.resource_group_create ? 1 : 0
  name                = var.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main[0].name
  address_space       = [var.address_space]

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_subnet" "cassandra" {
  name                 = "cassandra-subnet"
  resource_group_name  = local.resource_group
  virtual_network_name = local.vnet
  address_prefixes     = [var.subnet]
}