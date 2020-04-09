# Author: Alejandro Galue <agalue@opennms.org>

resource "azurerm_public_ip" "bastion" {
  name                = "cassandra-bastion-ip"
  location            = azurerm_resource_group.cassandra.location
  resource_group_name = azurerm_resource_group.cassandra.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.cassandra.name
  virtual_network_name = azurerm_virtual_network.cassandra.name
  address_prefix       = var.bastion_subnet
}

resource "azurerm_bastion_host" "bastion" {
  name                = "cassandra-bastion-bastion"
  location            = azurerm_resource_group.cassandra.location
  resource_group_name = azurerm_resource_group.cassandra.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}
