resource "azurerm_linux_virtual_machine" "lab_vm" {
  name                = "vm-cftec-m62025-SINT646-lab01"
  resource_group_name = azurerm_resource_group.lab.name
  location            = var.location
  size                = "Standard_A4m_v2"
  admin_username      = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.lab_nic.id
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<EOF
#!/bin/bash
apt-get update -y
apt-get upgrade -y
apt-get install -y docker.io
systemctl enable docker
systemctl start docker
EOF
  )

  tags = {
    project = var.project_name
    env     = "lab"
  }
}
