# 🧪 Laboratorio 1 — Deep Learning y Big Data con Python (SINT646)

Este repositorio contiene el desarrollo completo del **Laboratorio #1** del curso _Deep Learning y Big Data con Python_ de la Universidad CENFOTEC, ciclo 2025.

## 🎯 Objetivo

Investigar, implementar y comparar el desempeño de **tres bases de datos NoSQL** (MongoDB, Redis y HBase) en un entorno controlado mediante el despliegue de contenedores Docker sobre una máquina virtual en Azure. Las pruebas se realizaron utilizando un dataset real de más de 2.6 millones de registros de transacciones en una tienda de electrónicos.

---

## ⚙️ Tecnologías utilizadas

- **Infraestructura como Código (IaC)**: Terraform + Azure
- **Contenedores**: Docker
- **Bases de Datos**:
  - MongoDB + Mongo Express
  - Redis + RedisInsight
  - Apache HBase
- **Lenguaje de consulta**: Python 3.8
- **Entorno de análisis**: Jupyter Notebook
- **Librerías clave**: `pandas`, `pymongo`, `redis`, `happybase`, `thriftpy2`, `matplotlib`

---

## 📦 Estructura del proyecto

---
```
/
├── terraform/             # Código Terraform para crear la VM en Azure
├── docs/                 # Informe técnico, capturas y conclusiones
├── notebook/             # Jupyter Notebook con carga y consultas
├── scripts/              # Script para reiniciar servicios tras reinicio
├── datasets/ (opcional)  # Dataset procesado (si se habilita)
├── .github/workflows/    # GitHub Actions para CI/CD del laboratorio
└── requerimientos.json   # Tareas y requisitos del laboratorio
```

---

## 📊 Consultas realizadas

Se desarrollaron scripts para ejecutar las siguientes consultas en cada base de datos:

1. ¿Cuál es la **categoría más vendida**?
2. ¿Cuál **marca** generó más ingresos brutos?
3. ¿Qué **mes** tuvo más ventas (en UTC)?

---

## 📈 Resultados comparativos

| Consulta              | MongoDB               | Redis                  | HBase                 |
|-----------------------|-----------------------|------------------------|-----------------------|
| Categoría más vendida | `nan` (612,202)       | `electronics.smartphone` (357,682) | `electronics.smartphone` (213,002) |
| Marca con más ingresos| `samsung` ($90M)      | `samsung` ($90M)       | `samsung` ($54M)      |
| Mes con más ventas    | `2020-06` (403,632)   | `2020-06` (403,632)    | `2020-06` (211,552)   |

⏱️ **MongoDB fue el motor más eficiente en todas las consultas.**  
📉 **Redis**, pese a ser en memoria, presentó los tiempos más altos debido al tipo de estructura de datos utilizada.

---

## 📄 Documentación

El informe técnico incluye:

- Arquitectura de cómputo
- Infraestructura como Código (Terraform)
- Registros técnicos detallados
- Capturas de pantalla de entornos y herramientas
- Análisis de rendimiento con gráficos y tablas
- Hipótesis y conclusiones

📄 [`Lab1_Informe_Completo.md`](docs/Lab1_Informe_Completo.md)

---

## 🚀 Cómo reproducir el laboratorio

1. Clona este repositorio
2. Despliega la infraestructura con Terraform (`terraform apply`)
3. Accede a la VM por SSH
4. Ejecuta `restart_lab_services.sh` para levantar los contenedores
5. Abre `Jupyter Notebook` en el navegador y ejecuta el notebook

---

## 🔗 Accesos de prueba (ejemplo en entorno Azure)

| Servicio         | URL de acceso                    |
|------------------|----------------------------------|
| Mongo Express    | http://<IP>:8081                 |
| RedisInsight     | http://<IP>:8001                 |
| HBase UI         | http://<IP>:16010                |
| Jupyter Notebook | http://<IP>:8888 (pass: `pass`)  |

---

## 🧑‍🎓 Autor

**Mario Brenes**  
Estudiante del curso SINT646 — CENFOTEC  
[GitHub Profile](https://github.com/mbrenes26)

---

## 📘 Licencia

Este proyecto es de carácter educativo y se comparte bajo la licencia MIT.

