resource "azurerm_resource_group" "lab" {
  name     = "rg-cftec-m62025-SINT646"
  location = var.location

  tags = {
    project = var.project_name
    env     = "lab"
  }
}
