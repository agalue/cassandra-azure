# Author: Alejandro Galue <agalue@opennms.org>

resource "azurerm_network_security_group" "opennms" {
  name                = "opennms-sg"
  location            = azurerm_resource_group.cassandra.location
  resource_group_name = azurerm_resource_group.cassandra.name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "http"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8980"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "karaf"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8181"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_public_ip" "opennms" {
  name                = "opennms-ip"
  location            = azurerm_resource_group.cassandra.location
  resource_group_name = azurerm_resource_group.cassandra.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "opennms" {
  name                = "opennms-nic"
  location            = azurerm_resource_group.cassandra.location
  resource_group_name = azurerm_resource_group.cassandra.name

  enable_accelerated_networking = true
  internal_dns_name_label       = "opennms"

  ip_configuration {
    name                          = "opennms"
    subnet_id                     = azurerm_subnet.cassandra.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.opennms_ip_address
    public_ip_address_id          = azurerm_public_ip.opennms.id
  }

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_network_interface_security_group_association" "opennms" {
  network_interface_id      = azurerm_network_interface.opennms.id
  network_security_group_id = azurerm_network_security_group.opennms.id
}

data "template_file" "opennms" {
  template = file("${path.module}/opennms.tpl")

  vars = {
    cassandra_seed       = var.cassandra_ip_addresses[0]
    replication_factor   = var.replication_factor
    cache_max_entries    = var.cache_max_entries
    connections_per_host = var.connections_per_host
    ring_buffer_size     = var.ring_buffer_size
  }
}

resource "azurerm_virtual_machine" "opennms" {
  name                = "opennms"
  resource_group_name = azurerm_resource_group.cassandra.name
  location            = azurerm_resource_group.cassandra.location
  vm_size             = var.opennms_vm_size

  delete_os_disk_on_termination = true

  network_interface_ids = [
    azurerm_network_interface.opennms.id,
  ]

  storage_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.5"
    version   = "latest"
  }

  os_profile {
    computer_name  = "opennms"
    admin_username = var.username
    custom_data    = data.template_file.opennms.rendered
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/${var.username}/.ssh/authorized_keys"
      key_data = file("~/.ssh/id_rsa.pub")
    }
  }

  storage_os_disk {
    name              = "opennms-os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}
