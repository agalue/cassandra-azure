# Author: Alejandro Galue <agalue@opennms.org>

output "opennms_public_ip" {
  value = azurerm_public_ip.opennms.ip_address
}

output "cassandra_ip_addresses" {
  value = var.cassandra_ip_addresses
}

output "opennms_settings" {
  value = var.opennms_settings
}