# Author: Alejandro Galue <agalue@opennms.org>

resource "azurerm_network_security_group" "cassandra" {
  name                = "cassandra-sg"
  location            = var.location
  resource_group_name = local.resource_group

  security_rule {
    name                       = "intra-node"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "7000-7001"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "cql-native"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9042"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "thrift"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9160"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "jmx"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "7199"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_network_interface" "cassandra" {
  count               = length(var.cassandra_ip_addresses)
  name                = "cassandra-nic-${count.index + 1}"
  location            = var.location
  resource_group_name = local.resource_group

  enable_accelerated_networking = true
  internal_dns_name_label       = "cassandra${count.index + 1}"

  ip_configuration {
    name                          = "cassandra${count.index + 1}"
    subnet_id                     = azurerm_subnet.cassandra.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.cassandra_ip_addresses[count.index]
  }

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_network_interface_security_group_association" "cassandra" {
  count                     = length(var.cassandra_ip_addresses)
  network_interface_id      = azurerm_network_interface.cassandra[count.index].id
  network_security_group_id = azurerm_network_security_group.cassandra.id
}

resource "azurerm_managed_disk" "disk1" {
  count                = length(var.cassandra_ip_addresses)
  name                 = "cassandra${count.index + 1}-disk1"
  location             = var.location
  resource_group_name  = local.resource_group
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = "1023"

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_managed_disk" "disk2" {
  count                = length(var.cassandra_ip_addresses)
  name                 = "cassandra${count.index + 1}-disk2"
  location             = var.location
  resource_group_name  = local.resource_group
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = "1023"

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

data "template_file" "cassandra" {
  template = file("cassandra.tpl")

  vars = {
    cluster_name = "OpenNMS"
    seed_name    = var.cassandra_ip_addresses[0]
  }
}

resource "azurerm_virtual_machine" "cassandra" {
  count               = length(var.cassandra_ip_addresses)
  name                = "cassandra${count.index + 1}"
  resource_group_name = local.resource_group
  location            = var.location
  vm_size             = var.cassandra_vm_size

  delete_os_disk_on_termination = true

  network_interface_ids = [
    azurerm_network_interface.cassandra[count.index].id,
  ]

  storage_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  os_profile {
    computer_name  = "cassandra${count.index + 1}"
    admin_username = var.username
    custom_data    = data.template_file.cassandra.rendered
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/${var.username}/.ssh/authorized_keys"
      key_data = file(var.public_ssh_key)
    }
  }

  storage_os_disk {
    name              = "cassandra-os-disk-${count.index + 1}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_data_disk {
    name            = azurerm_managed_disk.disk1[count.index].name
    managed_disk_id = azurerm_managed_disk.disk1[count.index].id
    create_option   = "Attach"
    lun             = 1
    disk_size_gb    = azurerm_managed_disk.disk1[count.index].disk_size_gb
  }

  storage_data_disk {
    name            = azurerm_managed_disk.disk2[count.index].name
    managed_disk_id = azurerm_managed_disk.disk2[count.index].id
    create_option   = "Attach"
    lun             = 2
    disk_size_gb    = azurerm_managed_disk.disk2[count.index].disk_size_gb
  }

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}
