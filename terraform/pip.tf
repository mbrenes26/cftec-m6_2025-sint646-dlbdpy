# pip.tf

# Public IP for the VM/NIC
resource "azurerm_public_ip" "lab_pip" {
  name                = "pip-cftec-m62025-SINT646-labs"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name

  allocation_method = "Static"
  sku               = "Standard"

  # Optional: uncomment if you want a DNS label (must be unique per region)
  # domain_name_label = var.pip_dns_label

  tags = {
    project = var.project_name
    env     = "lab"
  }
}

# Helpful outputs
output "lab_public_ip" {
  description = "Public IP address"
  value       = azurerm_public_ip.lab_pip.ip_address
}

output "lab_public_ip_id" {
  description = "Public IP resource ID"
  value       = azurerm_public_ip.lab_pip.id
}
