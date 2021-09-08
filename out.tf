# Author: Alejandro Galue <agalue@opennms.org>

output "opennms_public_ip" {
  value = azurerm_public_ip.opennms.ip_address
}

output "opennms_public_fqdn" {
  value = azurerm_public_ip.opennms.fqdn
}

output "cassandra_ip_addresses" {
  value = var.cassandra_ip_addresses
}
