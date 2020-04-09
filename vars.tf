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

# Must be consistent with the chosen Location/Region
# Use CI images for cloud-init support
# Alternative theoretical option would be RedHat:RHEL:7-RAW-CI:latest
# Unlike when Ubuntu (or any image in AWS), there is no cloud-init-output.log; instead:
# sudo grep cloud-init /var/log/messages
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
      sku       = "7-CI"
      version   = "latest"
    }
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

variable "opennms_settings" {
  description = "OpenNMS Settings"
    type = object({
      replication_factor   = number
      cache_max_entries    = number
      ring_buffer_size     = number
      connections_per_host = number
    })
    default = {
      replication_factor   = 2
      cache_max_entries    = 2000000
      ring_buffer_size     = 4194304
      connections_per_host = 24
    }
}
