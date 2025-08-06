# Arquitectura de Cómputo — Laboratorio #1

## Descripción General

El objetivo principal del Laboratorio #1 es analizar el rendimiento de tres bases de datos NoSQL (HBase, MongoDB y Redis) al procesar y consultar un dataset de gran volumen (2 millones de registros), todo ello montado sobre una infraestructura reproducible y automatizada con herramientas modernas de despliegue.

---

## Componentes Principales

### 1. Máquina Virtual (Azure VM)

| Recurso          | Detalle                                                                 |
|------------------|-------------------------------------------------------------------------|
| Tipo             | Azure Virtual Machine                                                   |
| Sistema Operativo| Ubuntu 22.04 LTS                                                        |
| Recursos         | 2 vCPU, 8 GB RAM *(estimado para pruebas de laboratorio)*               |
| Despliegue       | Automatizado vía Terraform                                              |
| Scripts de gestión | `restart_lab_services.sh` (reinicio de servicios principales)         |
| Servicios instalados | Docker, Jupyter Notebook, Python, librerías específicas              |

---

### 2. Servicios de Base de Datos (Docker Containers)

Cada base de datos se ejecuta dentro de su propio contenedor Docker en la misma máquina virtual.

#### HBase

- Imagen utilizada: `harisekhon/hbase`
- Exposición: Puerto 16010 (UI), 2181 (Zookeeper), 8080 (API HBase REST)
- Acceso desde Python: librería `happybase` o `hbase-python`
- Configuración: volumen persistente local

#### MongoDB

- Imagen utilizada: `mongo`
- Puerto: 27017
- Acceso desde Python: `pymongo`
- Configuración: usuario/clave opcional, persistencia con volumen

#### Redis

- Imagen utilizada: `redis`
- Puerto: 6379
- Acceso desde Python: `redis-py`
- Configuración: sin autenticación (modo laboratorio)

---

### 3. Carga y Consulta de Datos (Python)

| Componente      | Descripción                                                                 |
|-----------------|-----------------------------------------------------------------------------|
| Dataset         | Datos simulados de una tienda de electrónicos (2 millones de registros)     |
| Script de carga | Insertar los datos en HBase, MongoDB y Redis                                |
| Script de consulta | Consultas específicas: categoría más vendida, marca con más ingresos, mes con más ventas |
| Plataforma      | Jupyter Notebooks (`Lab1_Databases_ElectronicsStore.ipynb`)                 |
| Librerías clave | `pandas`, `datetime`, `pymongo`, `redis`, `happybase`, `matplotlib`         |

---

### 4. Automatización y DevOps

#### Terraform

- Ubicación: `terraform/`
- Proveedores: `azurerm`
- Backend: local (`terraform.tfstate`)
- Recursos definidos:
  - Grupo de recursos (`azurerm_resource_group`)
  - Red virtual y subred (`azurerm_virtual_network`, `azurerm_subnet`)
  - Interfaz de red (`azurerm_network_interface`)
  - Máquina virtual Linux (`azurerm_linux_virtual_machine`)

#### GitHub Actions

- Ubicación: `.github/workflows/`
- Flujos:
  - `terraform.yml`: despliegue de la infraestructura
  - `restart-lab-services.yml`: reinicio de contenedores en la VM
  - `Manage_Lab_VM.yml`: control manual de encendido/apagado de la VM

---

## Esquema Visual (Resumen)

```
                     +---------------------------+
                     |     Azure Virtual Machine |
                     |---------------------------|
                     | OS: Ubuntu 22.04          |
                     | Docker + Python + Jupyter |
                     +-----------+---------------+
                                 |
              +----------------+-------------------+
              |                |                   |
       +------+-----+   +------+-----+      +------+-----+
       |  MongoDB   |   |   HBase    |      |   Redis     |
       | (pymongo)  |   | (happybase)|      | (redis-py)  |
       +------------+   +------------+      +------------+
              |                |                   |
        Consultas         Consultas           Consultas
        Dataset            Dataset             Dataset
```

---

## Detalle de Infraestructura como Código (IaC) con Terraform

### Proveedor y Backend

```hcl
provider "azurerm" {
  features {}
}

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

### Grupo de recursos

```hcl
resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
}
```

### Red

```hcl
resource "azurerm_virtual_network" "lab" {
  name                = var.vnet_name
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
}

resource "azurerm_subnet" "lab" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.subnet_prefix]
}
```

### Máquina Virtual

```hcl
resource "azurerm_linux_virtual_machine" "lab" {
  name                  = var.vm_name
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  network_interface_ids = [azurerm_network_interface.lab.id]
  size                  = var.vm_size

  admin_username = var.admin_username

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "22_04-lts"
    version   = "latest"
  }

  disable_password_authentication = true
}
```

---

## Repositorio del Proyecto

Este laboratorio está documentado y versionado en el siguiente repositorio de GitHub:

🔗 [https://github.com/mbrenes26/cftec-m6_2025-sint646-dlbdpy](https://github.com/mbrenes26/cftec-m6_2025-sint646-dlbdpy)

---

## Conclusión

La arquitectura del laboratorio busca balancear simplicidad, aislamiento y reproducibilidad. Al contener los servicios en una sola VM con contenedores separados, se facilita el manejo de recursos, reinicio controlado de servicios, y análisis comparativo justo, ya que todas las bases de datos se ejecutan bajo condiciones similares.