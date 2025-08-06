resource "azurerm_public_ip" "lab_pip" {
  name                = "pip-cftec-m62025-SINT646-lab01"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
}
resource "azurerm_network_interface" "lab_nic" {
  name                = "nic-cftec-m62025-SINT646-lab01"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.lab_pip.id
  }
}
resource "azurerm_virtual_network" "lab_vnet" {
  name                = "vnet-cftec-m62025-SINT646-lab01"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
}

resource "azurerm_subnet" "lab_subnet" {
  name                 = "subnet-cftec-m62025-SINT646-lab01"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}
