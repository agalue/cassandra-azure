# Author: Alejandro Galue <agalue@opennms.org>

# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
  required_version = ">= 0.13"
}

provider "azurerm" {
  features {}
}
