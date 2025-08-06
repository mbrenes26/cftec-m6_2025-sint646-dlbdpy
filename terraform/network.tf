resource "azurerm_public_ip" "lab_pip" {
  name                = "pip-cftec-m62025-SINT646-lab01"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
}
