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
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_network_interface" "nginx" {
  count               = var.use_cortex ? 1 : 0
  name                = "nginx-nic"
  location            = var.location
  resource_group_name = local.resource_group

  enable_accelerated_networking = true
  internal_dns_name_label       = "cortex"

  ip_configuration {
    name                          = "cortex"
    subnet_id                     = azurerm_subnet.cassandra.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.nginx_ip_address
  }

  tags = {
    Environment = "Test"
    Department  = "Support"
  }
}

resource "azurerm_network_interface_security_group_association" "nginx" {
  count                     = var.use_cortex ? 1 : 0
  network_interface_id      = azurerm_network_interface.nginx[count.index].id
  network_security_group_id = azurerm_network_security_group.cortex.id
}

resource "azurerm_linux_virtual_machine" "nginx" {
  count               = var.use_cortex ? 1 : 0
  name                = "cortex"
  computer_name       = "cortex"
  resource_group_name = local.resource_group
  location            = var.location
  size                = var.nginx_vm_size
  admin_username      = var.username

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.nginx[count.index].id,
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
    name                 = "nginx-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  timeouts {
    create = "60m"
    delete = "30m"
  }

  tags = {
    Environment = "Test"
    Department  = "Support"
    Application = "Nginx"
  }
}
