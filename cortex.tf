# Author: Alejandro Galue <agalue@opennms.org>

resource "azurerm_network_security_group" "cortex" {
  name                = "cortex-sg"
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
    destination_port_range     = "9009"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "grpc"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9095"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = "Testing"
    Department  = "Support"
  }
}

resource "azurerm_network_interface" "cortex" {
  count               = var.use_cortex ? length(var.cortex_ip_addresses) : 0
  name                = "cortex${count.index + 1}-nic"
  location            = var.location
  resource_group_name = local.resource_group

  enable_accelerated_networking = true
  internal_dns_name_label       = "cortex${count.index + 1}"

  ip_configuration {
    name                          = "cortex${count.index + 1}"
    subnet_id                     = azurerm_subnet.cassandra.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.cortex_ip_addresses[count.index]
  }

  tags = {
    Environment = "Testing"
    Department  = "Support"
  }
}

resource "azurerm_network_interface_security_group_association" "cortex" {
  count                     = var.use_cortex ? length(var.cortex_ip_addresses) : 0
  network_interface_id      = azurerm_network_interface.cortex[count.index].id
  network_security_group_id = azurerm_network_security_group.cortex.id
}

resource "azurerm_linux_virtual_machine" "cortex" {
  count               = var.use_cortex ? length(var.cortex_ip_addresses) : 0
  name                = "cortex${count.index + 1}"
  computer_name       = "cortex${count.index + 1}"
  resource_group_name = local.resource_group
  location            = var.location
  size                = var.cortex_vm_size
  admin_username      = var.username

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.cortex[count.index].id,
  ]

  admin_ssh_key {
    username   = var.username
    public_key = file("./ansible/global-ssh-key.pub")
  }

  source_image_reference {
    publisher = var.os_image.publisher
    offer     = var.os_image.offer
    sku       = var.os_image.sku
    version   = var.os_image.version
  }

  os_disk {
    name                 = "cortex-os-disk${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  timeouts {
    create = "60m"
    delete = "30m"
  }

  tags = {
    Environment = "Testing"
    Department  = "Support"
    Application = "Cortex"
  }
}
