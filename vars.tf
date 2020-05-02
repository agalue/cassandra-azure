# Author: Alejandro Galue <agalue@opennms.org>
#
# WARNING: Make sure the content is consistent with ansible/inventory/inventory.yaml
#          (IP Address list of the Cassandra cluster)

variable "location" {
  description = "Azure Location/Region"
  type        = string
  default     = "East US"
}

variable "resource_group_create" {
  description = "Set to true to create the resource group and the vnet"
  type        = bool
  default     = false
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "sales-testing"
}

variable "vnet_name" {
  description = "Name of the Virtual Network within the chosen resource group"
  type        = string
  default     = "sales-testing-vnet"
}

variable "username" {
  description = "Administrative user to manage VMs (SSH Access)"
  type        = string
  default     = "agalue"
}

# Must be consistent with the chosen Location/Region
variable "os_image" {
  description = "OS Image to use for OpenNMS and Cassandra"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "8_1"
    version   = "latest"
  }
}

# Used only when resource_group_create=true
variable "address_space" {
  description = "Virtual Network Address Space"
  type        = string
  default     = "10.0.0.0/16"
}

# Must exist within the address_space of the chosen virtual network
variable "subnet" {
  description = "Main Subnet Range"
  type        = string
  default     = "10.0.2.0/24"
}

# Must exist within the main subnet range
variable "opennms_ip_address" {
  description = "OpenNMS IP Address"
  type        = string
  default     = "10.0.2.10"
}

# Must exist within the main subnet range
# Must match hosts range for the cassandra_servers group in the Ansible inventory
variable "cassandra_ip_addresses" {
  description = "Cassandra IP Addresses. This also determines the size of the cluster."
  type        = list(string)
  default = [
    "10.0.2.11",
    "10.0.2.12",
    "10.0.2.13",
    "10.0.2.14",
    "10.0.2.15",
    "10.0.2.16",
    "10.0.2.17",
    "10.0.2.18",
  ]
}

variable "opennms_vm_size" {
  description = "OpenNMS Virtual Machine Size"
  type        = string
  default     = "Standard_D16s_v3" # General Purpose Instance with 16 Cores, 64GB of RAM
}

# https://docs.microsoft.com/en-us/azure/architecture/best-practices/cassandra
# Premium Storage Required
variable "cassandra_vm_size" {
  description = "OpenNMS Virtual Machine Size"
  type        = string
  default     = "Standard_DS13_v2" # Memory Optimized Instance with 8 Cores, 56GB of RAM
}
