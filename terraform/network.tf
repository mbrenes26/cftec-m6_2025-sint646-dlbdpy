# Public IP
resource "azurerm_public_ip" "lab_pip" {
  name                = "pip-cftec-m62025-SINT646-lab01"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Network Interface
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

# Virtual Network
resource "azurerm_virtual_network" "lab_vnet" {
  name                = "vnet-cftec-m62025-SINT646-lab01"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
}

# Subnet
resource "azurerm_subnet" "lab_subnet" {
  name                 = "subnet-cftec-m62025-SINT646-lab01"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group con todas las reglas
resource "azurerm_network_security_group" "lab_nsg" {
  name                = "nsg-cftec-m62025-SINT646-lab01"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name

  # SSH abierto para cualquier IP (solo laboratorio)
  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # MongoDB - Solo tu IP
  security_rule {
    name                       = "Allow-MongoDB-MyIP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "27017"
    source_address_prefix      = "190.108.74.42/32"
    destination_address_prefix = "*"
  }

  # Redis - Solo tu IP
  security_rule {
    name                       = "Allow-Redis-MyIP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6379"
    source_address_prefix      = "190.108.74.42/32"
    destination_address_prefix = "*"
  }

  # HBase Web UI (Master) - Solo tu IP
  security_rule {
    name                       = "Allow-HBase-Master-UI-MyIP"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "16010"
    source_address_prefix      = "190.108.74.42/32"
    destination_address_prefix = "*"
  }

  # HBase Web UI (RegionServer) - Solo tu IP
  security_rule {
    name                       = "Allow-HBase-Region-UI-MyIP"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "16030"
    source_address_prefix      = "190.108.74.42/32"
    destination_address_prefix = "*"
  }
}

# Asociación del NSG a la Subnet
resource "azurerm_subnet_network_security_group_association" "lab_subnet_nsg" {
  subnet_id                 = azurerm_subnet.lab_subnet.id
  network_security_group_id = azurerm_network_security_group.lab_nsg.id
}
# Mongo Express UI - Solo tu IP
security_rule {
  name                       = "Allow-MongoExpress-MyIP"
  priority                   = 140
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "8081"
  source_address_prefix      = "190.108.74.42/32"
  destination_address_prefix = "*"
}
