# network.tf

# Virtual Network
resource "azurerm_virtual_network" "lab_vnet" {
  name                = "vnet-cftec-m62025-SINT646-labs"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    project = var.project_name
    env     = "lab"
  }
}

# Subnet
resource "azurerm_subnet" "lab_subnet" {
  name                 = "subnet-cftec-m62025-SINT646-labs"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Interface (references the Public IP defined in pip.tf)
resource "azurerm_network_interface" "lab_nic" {
  name                = "nic-cftec-m62025-SINT646-labs"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "internal" # keep as-is to avoid replacement
    subnet_id                     = azurerm_subnet.lab_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.lab_pip.id
  }

  tags = {
    project = var.project_name
    env     = "lab"
  }
}
