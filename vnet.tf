
resource "azurerm_resource_group" "cassandra" {
  name     = "cassandra-rg"
  location = var.location

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_virtual_network" "cassandra" {
  name                = "cassandra-vnet"
  resource_group_name = azurerm_resource_group.cassandra.name
  location            = azurerm_resource_group.cassandra.location
  address_space       = [var.address_space]

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_subnet" "cassandra" {
  name                 = "cassandra-subnet"
  resource_group_name  = azurerm_resource_group.cassandra.name
  virtual_network_name = azurerm_virtual_network.cassandra.name
  address_prefix       = var.subnet
}