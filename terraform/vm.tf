resource "azurerm_linux_virtual_machine" "lab_vm" {
  name                            = "vm-cftec-m62025-SINT646-labs"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = var.location
  size                            = "Standard_A4m_v2"
  admin_username                  = "azureuser"
  network_interface_ids           = [azurerm_network_interface.lab_nic.id]
  disable_password_authentication = true

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

  # cloud-init desde archivo externo
  custom_data = filebase64("${path.module}/cloud-init.yml")

  tags = {
    project = var.project_name
    env     = "lab"
  }
}
