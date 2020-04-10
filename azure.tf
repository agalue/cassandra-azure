# Author: Alejandro Galue <agalue@opennms.org>

# Configure the Azure Provider
provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# Requires Terraform 0.12.x or newer
terraform {
  required_version = ">= 0.12"
}