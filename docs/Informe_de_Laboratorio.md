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
- Recursos definidos:
  - `azurerm_resource_group`
  - `azurerm_virtual_network`
  - `azurerm_subnet`
  - `azurerm_network_interface`
  - `azurerm_linux_virtual_machine`
- Backend configurado para estado remoto local

#### GitHub Actions

- Ubicación: `.github/workflows/`
- Flujos:
  - `terraform.yml`: despliegue de la infraestructura
  - `restart-lab-services.yml`: reinicio de contenedores en la VM
  - `Manage_Lab_VM.yml`: control manual de encendido/apagado de la VM

---

## Esquema Visual (Resumen)

```text
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

Consideraciones de Rendimiento
Todos los servicios comparten la misma VM, lo cual puede generar competencia por recursos.

Se espera que Redis tenga el mejor tiempo de respuesta en consultas simples, seguido por MongoDB, y por último HBase en operaciones de lectura complejas.

El análisis de rendimiento se complementa con capturas de pantalla almacenadas en docs/img/.

Repositorio del Proyecto
Este laboratorio está documentado y versionado en el siguiente repositorio de GitHub:

🔗 https://github.com/mbrenes26/cftec-m6_2025-sint646-dlbdpy

Incluye el código fuente, scripts de automatización, notebooks y documentación relevante para su reproducción y análisis.

Conclusión
La arquitectura del laboratorio busca balancear simplicidad, aislamiento y reproducibilidad. Al contener los servicios en una sola VM con contenedores separados, se facilita el manejo de recursos, reinicio controlado de servicios, y análisis comparativo justo, ya que todas las bases de datos se ejecutan bajo condiciones similares.