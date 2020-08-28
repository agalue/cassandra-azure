# Author: Alejandro Galue <agalue@opennms.org>

resource "azurerm_network_interface" "envoy" {
  count               = var.use_cortex && length(var.cortex_ip_addresses) > 1 ? 1 : 0
  name                = "envoy-nic"
  location            = var.location
  resource_group_name = local.resource_group

  enable_accelerated_networking = true
  internal_dns_name_label       = "cortex"

  ip_configuration {
    name                          = "cortex"
    subnet_id                     = azurerm_subnet.cassandra.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.envoy_ip_address
  }

  tags = {
    Environment = "Testing"
    Department  = "Support"
  }
}

resource "azurerm_network_interface_security_group_association" "envoy" {
  count                     = var.use_cortex && length(var.cortex_ip_addresses) > 1 ? 1 : 0
  network_interface_id      = azurerm_network_interface.envoy[count.index].id
  network_security_group_id = azurerm_network_security_group.cortex.id
}

resource "azurerm_linux_virtual_machine" "envoy" {
  count               = var.use_cortex && length(var.cortex_ip_addresses) > 1 ? 1 : 0
  name                = "cortex"
  computer_name       = "cortex"
  resource_group_name = local.resource_group
  location            = var.location
  size                = var.envoy_vm_size
  admin_username      = var.username

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.envoy[count.index].id,
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
    name                 = "envoy-os-disk"
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
    Application = "Envoy"
  }
}
