# Author: Alejandro Galue <agalue@opennms.org>

resource "azurerm_network_security_group" "cassandra" {
  name                = "${var.username}-cassandra-sg"
  location            = var.location
  resource_group_name = local.resource_group
  tags                = local.required_tags

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
}

resource "azurerm_network_interface" "cassandra" {
  count               = length(var.cassandra_ip_addresses)
  name                = "${var.username}-cassandra${count.index + 1}-nic"
  location            = var.location
  resource_group_name = local.resource_group
  tags                = local.required_tags

  enable_accelerated_networking = true
  internal_dns_name_label       = "${var.username}-cassandra${count.index + 1}"

  ip_configuration {
    name                          = "cassandra${count.index + 1}"
    subnet_id                     = azurerm_subnet.cassandra.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.cassandra_ip_addresses[count.index]
  }
}

resource "azurerm_network_interface_security_group_association" "cassandra" {
  count                     = length(var.cassandra_ip_addresses)
  network_interface_id      = azurerm_network_interface.cassandra[count.index].id
  network_security_group_id = azurerm_network_security_group.cassandra.id
}

# To facilitate data disks management, avoid using azurerm_linux_virtual_machine
resource "azurerm_virtual_machine" "cassandra" {
  count               = length(var.cassandra_ip_addresses)
  name                = "${var.username}-cassandra${count.index + 1}"
  resource_group_name = local.resource_group
  tags                = local.required_tags
  location            = var.location
  vm_size             = var.cassandra_vm_size

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

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
    computer_name  = "${var.username}-cassandra${count.index + 1}"
    admin_username = var.username
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/${var.username}/.ssh/authorized_keys"
      key_data = file("./ansible/global-ssh-key.pub")
    }
  }

  storage_os_disk {
    name              = "${var.username}-cassandra${count.index + 1}-os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  dynamic "storage_data_disk" {
    iterator = disk
    for_each = range(2)
    content {
      name                      = "${var.username}-cassandra${count.index + 1}-data-disk${disk.key}"
      create_option             = "Empty"
      managed_disk_type         = "Premium_LRS"
      disk_size_gb              = 1023
      write_accelerator_enabled = false
      lun                       = disk.key
    }
  }
}
