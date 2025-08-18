# nsg.tf

resource "azurerm_network_security_group" "lab_nsg" {
  name                = "nsg-cftec-m62025-SINT646-lab01"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name

  # MongoDB - only your IP
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

  # Redis - only your IP
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

  # HBase Master UI - only your IP
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

  # HBase RegionServer UI - only your IP
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

  # Mongo Express UI - only your IP
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

  # RedisInsight UI - only your IP
  security_rule {
    name                       = "Allow-RedisInsight-MyIP"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8001"
    source_address_prefix      = "190.108.74.42/32"
    destination_address_prefix = "*"
  }

  # Jupyter Notebook - only your IP
  security_rule {
    name                       = "Allow-Jupyter-MyIP"
    priority                   = 160
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8888"
    source_address_prefix      = "190.108.74.42/32"
    destination_address_prefix = "*"
  }

  # Kafka UI - only your IP
  security_rule {
    name                       = "Allow-Kafka-UI-MyIP"
    priority                   = 170
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9000"
    source_address_prefix      = "190.108.74.42/32"
    destination_address_prefix = "*"
  }

  # Kafka external listener (PLAINTEXT) on 29092 - only your IP
  security_rule {
    name                       = "Allow-Kafka-External-MyIP"
    priority                   = 180
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "29092"
    source_address_prefix      = "190.108.74.42/32"
    destination_address_prefix = "*"
  }

  # SSH - only your IP
  security_rule {
    name                       = "Allow-SSH-MyIP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "190.108.74.42/32"
    destination_address_prefix = "*"
  }
}

# Associate NSG to the subnet defined in network.tf
resource "azurerm_subnet_network_security_group_association" "lab_subnet_nsg" {
  subnet_id                 = azurerm_subnet.lab_subnet.id
  network_security_group_id = azurerm_network_security_group.lab_nsg.id
}
