# 🧩 Guía de Configuración de Ambiente — Laboratorios CENFOTEC SINT646

Este documento describe el **ambiente base** que se utiliza para ejecutar los laboratorios de la asignatura **Deep Learning y Big Data con Python (SINT646)**, tomando como referencia el entorno configurado para el **Laboratorio #1**.

Su objetivo es servir como **instrucciones iniciales** para que cualquier nuevo laboratorio pueda desplegarse y ejecutarse de forma consistente.

---

## 📜 Descripción General

El ambiente está diseñado para:
- Proveer una **máquina virtual en Azure** como entorno de ejecución central.
- Desplegar **servicios de bases de datos** en contenedores Docker.
- Utilizar **Infraestructura como Código (IaC)** con Terraform.
- Integrar control de versiones y automatización con **GitHub Actions**.
- Disponer de un **entorno interactivo** (Jupyter Notebook) para análisis y desarrollo.

---

## 🏗️ Infraestructura en Azure

### 1. **Máquina Virtual (VM)**
- **Sistema Operativo**: Ubuntu 22.04 LTS
- **Recursos base**: 2–8 vCPU, 8–32 GB RAM *(ajustable según laboratorio)*
- **Creación**: Terraform (`terraform/`)
- **Autenticación**: Clave pública SSH (`TF_VAR_ssh_public_key`)
- **Puertos abiertos** *(según NSG)*:
  - 22 — SSH
  - 8081 — Mongo Express
  - 8001 — RedisInsight
  - 16010 — HBase Master UI
  - 16030 — HBase RegionServer UI
  - 8888 — Jupyter Notebook

---

## 📦 Servicios en Contenedores Docker

Cada servicio se ejecuta en un contenedor independiente en la VM:

| Servicio         | Imagen Docker                 | Puerto(s)       | Persistencia     |
|------------------|--------------------------------|-----------------|------------------|
| **MongoDB**      | `mongo:latest`                 | 27017           | `mongo_data`     |
| **Mongo Express**| `mongo-express:latest`         | 8081            | -                |
| **Redis**        | `redis:latest`                 | 6379            | `redis_data`     |
| **RedisInsight** | `redislabs/redisinsight:1.14.0`| 8001            | -                |
| **HBase**        | `harisekhon/hbase:latest`      | 16000,16010,16020,16030,2181 | `hbase_data` |

---

## 🧑‍💻 Entorno de Desarrollo

- **Lenguaje**: Python 3.8+
- **Librerías clave**:
  - `pandas`
  - `pymongo`
  - `redis`
  - `happybase`
  - `thriftpy2`
  - `matplotlib`
- **Entorno interactivo**:
  - **Jupyter Notebook**:
    - Puerto 8888
    - Contraseña hash (configurable)
    - Ejecución persistente con `tmux`

---

## ⚙️ Automatización y DevOps

### **Infraestructura como Código**
- **Terraform**:
  - Define y despliega:
    - Resource Group
    - Virtual Network + Subnet
    - Network Interface
    - Virtual Machine
  - Variables sensibles en `secrets` de GitHub Actions.

### **GitHub Actions**
- Workflows principales:
  - `terraform.yml` — Despliegue de infraestructura (manual por defecto)
  - `Manage_Lab_VM.yml` — Encender, apagar o reiniciar la VM
  - `restart-lab-services.yml` — Reinicio de contenedores y servicios en la VM
- Autenticación a Azure:
  - Service Principal (`AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`)

---

## 📂 Estructura del Repositorio

```
/
├── terraform/             # Código Terraform para crear la VM en Azure
├── docs/                  # Informe técnico, capturas y conclusiones
├── notebook/              # Jupyter Notebook con carga y consultas
├── scripts/               # Scripts auxiliares (ej. restart_lab_services.sh)
├── datasets/ (opcional)   # Dataset procesado (si se habilita)
├── .github/workflows/     # GitHub Actions (CI/CD, gestión de VM, etc.)
└── requerimientos.json    # Tareas y requisitos del laboratorio
```

---

## 🚀 Uso Básico

1. **Preparar secretos en GitHub**:
   - `AZURE_CLIENT_ID`
   - `AZURE_CLIENT_SECRET`
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_TENANT_ID`
   - `ARM_ACCESS_KEY`
   - `SSH_PUBLIC_KEY`

2. **Desplegar infraestructura**:
   - Ir a **GitHub Actions > Terraform CI/CD**
   - Ejecutar manualmente (`workflow_dispatch`) con confirmación `"yes"`

3. **Gestionar VM**:
   - Usar **Manage Lab VM** para iniciar/detener/reiniciar

4. **Conectarse a la VM**:
   ```bash
   ssh -i ~/.ssh/id_rsa azureuser@<IP_PUBLICA_VM>
   ```

5. **Iniciar Jupyter Notebook**:
   ```bash
   tmux new -s jupyterlab
   jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser
   ```
   - Acceder: `http://<IP_PUBLICA_VM>:8888`

---

## 🔐 Buenas Prácticas

- Mantener `terraform.yml` en ejecución manual para evitar despliegues accidentales.
- Restringir accesos a puertos en el NSG solo para IPs autorizadas.
- Usar volúmenes Docker para persistencia de datos.
- Limpiar datasets y colecciones/tablas antes de cargas masivas para evitar duplicados.

---

## 📎 Recursos

- [Terraform — Documentación oficial](https://developer.hashicorp.com/terraform/docs)
- [Docker — Documentación oficial](https://docs.docker.com/)
- [Azure CLI](https://learn.microsoft.com/cli/azure/)
- [GitHub Actions](https://docs.github.com/actions)
