# Author: Alejandro Galue <agalue@opennms.org>

resource "azurerm_resource_group" "cassandra" {
  count    = var.resource_group_create ? 1 : 0
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_virtual_network" "cassandra" {
  count               = var.resource_group_create ? 1 : 0
  name                = var.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.cassandra[0].name
  address_space       = [var.address_space]

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_subnet" "cassandra" {
  name                 = "cassandra-subnet"
  resource_group_name  = var.resource_group_create ? azurerm_resource_group.cassandra[0].name : var.resource_group_name
  virtual_network_name = var.resource_group_create ? azurerm_virtual_network.cassandra[0].name : var.vnet_name
  address_prefix       = var.subnet
}