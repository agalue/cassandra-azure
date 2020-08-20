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

  security_rule {
    name                       = "grafana"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = "Testing"
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
    Environment = "Testing"
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

  disable_password_authentication = true

  depends_on = [
    azurerm_virtual_machine.cassandra,
    azurerm_linux_virtual_machine.nginx,
    azurerm_linux_virtual_machine.cortex
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
    name                 = "opennms-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

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
      "ansible-playbook playbook.yaml -e tss_strategy=${var.use_cortex ? 'cortex' : 'newts'}"
    ]
  }

  timeouts {
    create = "60m"
    delete = "30m"
  }

  tags = {
    Environment = "Testing"
    Department  = "Support"
    Application = "OpenNMS"
  }
}
