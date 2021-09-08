# Author: Alejandro Galue <agalue@opennms.org>

locals {
  onms_vm_mame = "${var.username}-onmscas01"
}

resource "azurerm_network_security_group" "opennms" {
  name                = "${local.onms_vm_mame}-sg"
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
}

resource "azurerm_public_ip" "opennms" {
  name                = "${local.onms_vm_mame}-ip"
  location            = var.location
  resource_group_name = local.resource_group
  tags                = local.required_tags
  allocation_method   = "Dynamic"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "opennms" {
  name                = "${local.onms_vm_mame}-nic"
  location            = var.location
  resource_group_name = local.resource_group
  tags                = local.required_tags

  enable_accelerated_networking = true

  ip_configuration {
    name                          = "opennms"
    subnet_id                     = azurerm_subnet.cassandra.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.opennms_ip_address
    public_ip_address_id          = azurerm_public_ip.opennms.id
  }
}

resource "azurerm_network_interface_security_group_association" "opennms" {
  network_interface_id      = azurerm_network_interface.opennms.id
  network_security_group_id = azurerm_network_security_group.opennms.id
}

resource "azurerm_linux_virtual_machine" "opennms" {
  name                = local.onms_vm_mame
  resource_group_name = local.resource_group
  tags                = local.required_tags
  location            = var.location
  size                = var.opennms_vm_size
  admin_username      = var.username

  depends_on = [
    azurerm_virtual_machine.cassandra
  ]

  network_interface_ids = [
    azurerm_network_interface.opennms.id,
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
    name                 = "${local.onms_vm_mame}-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # For the provisioners
  connection {
    type        = "ssh"
    user        = var.username
    host        = azurerm_public_ip.opennms.ip_address
    private_key = file("./ansible/global-ssh-key")
  }

  # Copy Ansible Playbook files
  provisioner "file" {
    source      = "ansible"
    destination = "/home/${var.username}"
  }

  # Install Ansible and run the Playbook
  provisioner "remote-exec" {
    inline = [
      "sudo dnf install -q -y python3 python3-pip",
      "sudo pip3 -qqq install ansible",
      "cd ~/ansible",
      "chmod 400 global-ssh-key",
      "ansible-playbook playbook.yaml"
    ]
  }

  timeouts {
    create = "60m"
    delete = "30m"
  }
}
