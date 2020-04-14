# Author: Alejandro Galue <agalue@opennms.org>

resource "azurerm_network_security_group" "opennms" {
  name                = "opennms-sg"
  location            = var.location
  resource_group_name = local.resource_group

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
  location            = var.location
  resource_group_name = local.resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "opennms" {
  name                = "opennms-nic"
  location            = var.location
  resource_group_name = local.resource_group

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

resource "azurerm_linux_virtual_machine" "opennms" {
  name                = "opennms"
  computer_name       = "opennms"
  resource_group_name = local.resource_group
  location            = var.location
  size                = var.opennms_vm_size
  admin_username      = var.username
  admin_password      = var.password

  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.opennms.id,
  ]

  source_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  os_disk {
    name                 = "opennms-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

data "template_file" "opennms" {
  template = file("opennms.tpl")

  vars = {
    cassandra_seed       = var.cassandra_ip_addresses[0]
    cache_max_entries    = var.opennms_settings.cache_max_entries
    connections_per_host = var.opennms_settings.connections_per_host
    ring_buffer_size     = var.opennms_settings.ring_buffer_size
  }
}

resource "azurerm_virtual_machine_extension" "opennms" {
  name                 = "opennms-vmext"
  virtual_machine_id   = azurerm_linux_virtual_machine.opennms.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  protected_settings = <<PROT
    {
      "script": "${base64encode(data.template_file.opennms.rendered)}"
    }
    PROT

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

output "opennms-public-ip" {
  value = azurerm_public_ip.opennms.ip_address
}
