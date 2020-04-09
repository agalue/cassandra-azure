# Author: Alejandro Galue <agalue@opennms.org>

resource "azurerm_resource_group" "cassandra" {
  count    = var.resource_group_create ? 0 : 1
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_virtual_network" "cassandra" {
  count               = var.resource_group_create ? 0 : 1
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_subnet" "cassandra" {
  name                 = "cassandra-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefix       = var.subnet
}