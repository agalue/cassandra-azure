# Author: Alejandro Galue <agalue@opennms.org>

variable "location" {
  description = "Azure Location/Region"
  type        = string
  default     = "South Central US"
}

variable "username" {
  description = "Administrative user to manage VMs"
  type        = string
  default     = "agalue"
}

variable "address_space" {
  description = "Virtual Network Address Space"
  type        = string
  default     = "10.0.0.0/16"
}

# Must exist within the address_space
variable "subnet" {
  description = "Main Subnet Range"
  type        = string
  default     = "10.0.2.0/24"
}

# Must exist within the address_space
variable "bastion_subnet" {
  description = "Bastion Subnet"
  type        = string
  default     = "10.0.0.0/27"
}

# Must exist within the main subnet range
variable "opennms_ip_address" {
  description = "OpenNMS IP Address"
  type        = string
  default     = "10.0.2.10"
}

# Must exist within the main subnet range
variable "cassandra_ip_addresses" {
  description = "Cassandra IP Addresses. This also determines the size of the cluster."
  type        = list(string)
  default = [
    "10.0.2.11",
    "10.0.2.12",
    "10.0.2.13",
  ]
}

variable "opennms_vm_size" {
  description = "OpenNMS Virtual Machine Size"
  type        = string
  default     = "Standard_DS3_v2"
}

variable "cassandra_vm_size" {
  description = "OpenNMS Virtual Machine Size"
  type        = string
  default     = "Standard_DS3_v2"
}

variable "replication_factor" {
  type    = number
  default = 2
}

variable "cache_max_entries" {
  type    = number
  default = 2000000
}

variable "ring_buffer_size" {
  type    = number
  default = 4194304
}

variable "connections_per_host" {
  type    = number
  default = 24
}

