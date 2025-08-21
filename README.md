# 📐 Arquitectura del proyecto

> **Objetivo**: montar, poblar y exponer un _pipeline_ de análisis de sentimiento casi en tiempo real usando servicios en Docker sobre una VM de Azure, orquestado por GitHub Actions. El resultado se visualiza en **Metabase** a partir de datos consolidados en **MySQL**.

---

## 1) Visión general (alto nivel)

```
[Productor (Kafka)]  →  [Consumer → MongoDB]  →  [Worker DL (clasifica)]  →  [MySQL (DW)]  →  [Metabase]
                                      │                                  
                                    (Kafka UI / Mongo Express / Jupyter para pruebas)
```

- **Kafka** recibe mensajes (comentarios/texto).
- **consumer_to_mongo.py** persiste esos mensajes crudos en **MongoDB**.
- **sentiment_dl_worker.py** aplica un modelo (DL/ML) y genera **sentiment_label** / **sentiment_score**.
- Los resultados se **materializan en MySQL** (tabla de hechos tipo *Dw Messages*).
- **Metabase** lee MySQL para KPIs y dashboards.

Servicios de apoyo: **Kafka UI**, **Mongo Express**, **Redis/RedisInsight** (opcional), **Jupyter** para pruebas y notebooks.

---

## 2) Infraestructura y despliegue

### 2.1 Azure + Terraform
- Carpeta **`terraform/`**: crea **Resource Group**, **VNet/NSG**, y una **VM Linux**.
- **`cloud-init.yml`**: arranque inicial (instala Docker, usuarios, etc.).
- Workflow **`.github/workflows/00-terraform.yml`**: CI/CD para `init/plan/apply` (ejecución manual protegida).

### 2.2 VM + Docker
- Todos los contenedores viven en la red Docker **`labnet`** para descubrirse por nombre: `mysql`, `mongodb`, `kafka`, `metabase`, etc.
- Puertos expuestos (por defecto):
  - **Metabase** `3000`, **MySQL** `3306`, **MongoDB** `27017`, **Kafka UI** `9000`, **Mongo Express** `8081`, **RedisInsight** `8001`, **Jupyter** `8888`.
- Volúmenes relevantes:
  - **Metabase**: `-v metabase-data:/metabase-data` (`MB_DB_FILE=/metabase-data/metabase.db`).

---

## 3) Plano de datos (contenedores y roles)

| Servicio | Contenedor | Rol principal |
|---|---|---|
| Kafka | `kafka` | _Broker_ + listeners interno/externo, recibe mensajes de texto |
| Kafka UI | `kafka-ui` | Observabilidad y pruebas de topics |
| MongoDB | `mongodb` | Almacén crudo / *staging* (colección de mensajes) |
| Mongo Express | `mongo-express` | Admin web Mongo |
| MySQL | `mysql` | *Data Warehouse* ligero (tabla **Dw Messages**) |
| Metabase | `metabase` | Visualización/BI (dashboards/KPIs) |
| Redis / RedisInsight | `redis`, `redisinsight` | Cache/labs (opcional) |
| HBase (opcional) | `hbase` | Experimentos (no crítico al flujo E2E) |
| Jupyter | (en VM) | Notebooks de exploración y utilidades |

**Red interna**: todos unidos a `labnet`, por lo que los *hosts* se refieren por **nombre de contenedor** (p.ej., `mysql:3306`, `mongodb:27017`, `kafka:9092`).

---

## 4) Flujo de datos E2E

1. **Ingesta**
   - **`send_kafka_burst.py`** y/o **`export_sentiment140.py`** publican mensajes (texto) en un _topic_ de Kafka.
2. **Stage en Mongo**
   - **`consumer_to_mongo.py`** consume el topic y escribe documentos en **MongoDB** (colección cruda con `comment`, `user_id`, `created_at`, etc.).
3. **Inferencia de sentimiento**
   - **`sentiment_dl_worker.py`** lee desde **Mongo**, infiere `sentiment_label` (`pos/neg/neu/vpos...`) y `sentiment_score` (0–1).
4. **Consolidación en MySQL**
   - El worker inserta/actualiza la tabla **`Dw Messages`** en **MySQL** (hechos listos para BI).
5. **BI y dashboard**
   - **Metabase** se conecta a `mysql:3306` (usuario app) y muestra:
     - Total de mensajes.
     - Conteo por sentimiento.
     - Serie temporal por día.

> **Nota**: también se puede usar el notebook **`notebook/01-Proyecto-sentiment_dl_pipeline_mongo_to_mysql.ipynb`** para pruebas, EDA y *sanity checks*.

---

## 5) Automatización (GitHub Actions)

Carpeta **`.github/workflows/`** (ejecución remota contra la VM):

- **`00-terraform.yml`** – Provisiona/actualiza la infraestructura en Azure.
- **`01-ensure-prereqs.yml`** – Verifica prerequisitos (Docker, permisos, paquetes base).
- **`02-restart-lab-services.yml`** – Crea/red (`labnet`), arranca/ reinicia contenedores base.
- **`03-start-extras.yml`** – Servicios opcionales (Redis, HBase, etc.).
- **`04-init-data-plane.yml`** – Inicializa topics/colecciones/tablas y datos de ejemplo.
- **`05-install-ml-deps.yml`** – Instala dependencias de ML/DL (PyTorch, tokenizers, etc.).
- **`06-setup-metabase.yml`** – *Seed* local: healthcheck, *setup/login*, registrar MySQL, crear tarjetas y dashboard.
- **`07-Manage_Lab_VM.yml`** – Utilidades de mantenimiento (apagar/encender, logs, etc.).
- **`step10-start-services.yml`** – Arranque de servicios principales para demo.
- **`step11-setup-metabase-public.yml`** – Variante para exponer Metabase via IP pública (seguros/NSG).
- **`step12-bringup-demo-e2e.yml`** – Orquestación de punta a punta (ingesta→BI).
- **`step13-sanity-checks.yml`** – Chequeos básicos (salud de APIs, conteos, etc.).

Cada workflow usa **`az vm run-command`** para ejecutar scripts dentro de la VM (sin abrir SSH manualmente), o Terraform para IaC.

---

## 6) Scripts clave (carpeta `scripts/`)

- **`init_data_plane.sh`**: prepara red Docker `labnet`, levanta contenedores base (Kafka, Mongo, etc.), variables y puertos.
- **`restart_lab_services.sh`**: reinicio seguro de contenedores.
- **`install_ml_deps.sh`**: instala dependencias de ML usadas por el worker.
- **`setup_metabase_and_seed.sh`**: idempotente. _Setup_ / login Metabase, registra MySQL y crea 3 tarjetas + dashboard.
- **`consumer_to_mongo.py`**: consumidor Kafka → Mongo.
- **`send_kafka_burst.py`**: productor de mensajes a Kafka.
- **`export_sentiment140.py`**: carga dataset de ejemplo al topic.
- **`sentiment_dl_worker.py`**: clasifica sentimiento y escribe a MySQL.

---

## 7) Modelo de datos (DW ligero en MySQL)

Tabla **`Dw Messages`** (nombres ilustrativos):
- `id` (hash/uuid del mensaje)
- `user_id`
- `comment`
- `ingest_ts` (fecha/hora de ingesta)
- `sentiment_label` (e.g., `pos/neg/neu/vpos`)
- `sentiment_score` (float 0–1)
- `raw_json` (opcional)

> **Propósito**: tabla de hechos simple optimizada para consultas en Metabase.

---

## 8) Seguridad y credenciales (demo)

- **MySQL**: usuario app `metabase` con permisos **read‑only** sobre `lab.*` (creado por SQL de bootstrap) y `root:pass` para administración local.
- **Metabase**: persistido en volumen `metabase-data`. Config original se hace vía API local (`127.0.0.1:3000`) desde la VM.
- **NSG**: abrir solo los puertos necesarios (idealmente restringidos por IP). Para exposición pública de Metabase, usar el workflow de *public setup*.
- **Jupyter**: sin token por defecto en modo laboratorio → proteger vía NSG / túnel SSH.

> En producción, mover secretos a **Key Vault**, TLS/SSL, y usuarios/roles mínimos.

---

## 9) Operación (cómo correr la demo)

1) **Provisionar**: `Step00 - Terraform CI/CD` (o `terraform apply`).
2) **Arrancar servicios**: `step10-start-services.yml` (o `02-restart-lab-services.yml`).
3) **Sembrar datos / DL**: `04-init-data-plane.yml` y `05-install-ml-deps.yml`.
4) **Metabase**: `06-setup-metabase.yml` (local) o `step11-setup-metabase-public.yml` (público controlado).
5) **E2E**: `step12-bringup-demo-e2e.yml` para correr todo y validar con `step13-sanity-checks.yml`.

---

## 10) Visualizaciones base (Metabase)

- **Total mensajes** – KPI (count).
- **Conteo por sentimiento** – barras.
- **Mensajes por día** – línea (agregación por día sobre `ingest_ts`).

Las 3 tarjetas se agregan al tablero **`Sentiment_Streaming_Kafka_Mongo_DL_MySQL`**.

---

## 11) Directorio del repo (resumen práctico)

- **`.github/workflows/`** – automatización y orquestación.
- **`scripts/`** – _bootstrap_, productores/consumidores y workers.
- **`notebook/`** – cuadernos de exploración y pruebas.
- **`docs/`** – guías, arquitectura y evidencias.
- **`terraform/`** – IaC Azure.

---

## 12) Extensiones y variantes

- Sustituir **MySQL** por **PostgreSQL** o **Databricks** manteniendo Metabase.
- Añadir **Airflow** para orquestación programada.
- Sustituir el worker DL por un **serving** en contenedor (FastAPI/Triton) y llamar vía REST.

---

### 🧭 En una frase
**Kafka → Mongo (crudo) → DL (clasifica) → MySQL (DW) → Metabase (BI)**, todo reproducible desde GitHub Actions y Docker en una VM de Azure.



---

# Explicación del código: utilidades + carga de modelo (Transformers)

A continuación detallo **qué hace cada bloque** del fragmento que compartiste y qué necesitas para dejarlo listo para inferir sentimientos.

## 1) Importaciones
- `json, time, sys, datetime, timezone, typing` → utilidades estándar (serialización, tiempos, tipos).
- `mysql.connector` → cliente para escribir/leer en **MySQL**.
- `pymongo.MongoClient, ReturnDocument` → cliente para **MongoDB**.
- `transformers.AutoTokenizer, AutoModelForSequenceClassification` → carga de **tokenizador y modelo** de Hugging Face para clasificación de texto.
- `torch` y `torch.nn.functional as F` → ejecución del modelo en CPU/GPU y `softmax` para probabilidades.
- `tqdm.auto.tqdm` → barras de progreso.

## 2) Utilidades
```python
def utcnow_iso():
    return datetime.now(timezone.utc).isoformat()
```
Devuelve la hora **UTC** con formato ISO-8601 (útil para trazabilidad).

```python
def essential_str(v):
    return "" if v is None else str(v)
```
Normaliza valores a `str` evitando `None` (por ejemplo, al construir documentos/filas).

## 3) Autodiagnóstico de versiones
```python
print("Versiones:")
for pkg in ["torch","transformers","pymongo","mysql.connector","ipywidgets","tqdm"]:
    ...  # importa dinámicamente y muestra __version__
```
Intenta importar cada paquete y muestra su **versión**. Si alguno falla, imprime el error, lo que ayuda a detectar entornos incompletos.

## 4) Carga del modelo de sentimiento
```python
print("
Cargando modelo:", MODEL_NAME)
tok = AutoTokenizer.from_pretrained(MODEL_NAME)
mdl = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME)
mdl.eval()
id2label = getattr(
    mdl.config, "id2label",
    {0:"Very Negative",1:"Negative",2:"Neutral",3:"Positive",4:"Very Positive"}
)
print("Clases:", id2label)
```
- Espera que exista una variable **`MODEL_NAME`** (por ejemplo, `'cardiffnlp/twitter-roberta-base-sentiment-latest'` o similar).
- Descarga (o carga desde caché) el **tokenizador** y el **modelo** de clasificación.
- `mdl.eval()` pone el modelo en modo **evaluación** (desactiva dropout, etc.).
- Obtiene el mapeo de **índice → etiqueta** desde la configuración del modelo; si no existe, usa un mapeo por defecto de **5 clases** (`Very Negative`→`Very Positive`).

> ⚠️ Nota: ese mapeo por defecto solo es válido para modelos **5‑clase**. Si usas uno de **2 o 3 clases**, confía en `mdl.config.id2label` y **no** fuerces el fallback.

## 5) ¿Qué falta para inferir?
Los pasos mínimos para pasar de texto → predicción son:
1. **Elegir dispositivo** (CPU/GPU) y mover el modelo.
2. **Tokenizar** el/los textos con el tokenizador.
3. Pasar tensores al modelo en `torch.no_grad()` y aplicar `softmax`.
4. Convertir índices a **etiquetas** con `id2label` y, opcionalmente, guardar en Mongo/MySQL.

### Snippet de inferencia seguro
```python
import torch, torch.nn.functional as F

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
mdl.to(DEVICE)

texts = [
    "I love this product!",
    "meh, it's fine",
    "This is absolutely terrible"
]
enc = tok(texts, padding=True, truncation=True, max_length=256, return_tensors="pt")
enc = {k: v.to(DEVICE) for k, v in enc.items()}

with torch.no_grad():
    logits = mdl(**enc).logits
    probs = F.softmax(logits, dim=-1)

max_scores, max_idx = probs.max(dim=-1)
labels = [id2label[int(i)] for i in max_idx]
results = list(zip(texts, labels, max_scores.cpu().tolist()))
print(results)
```

## 6) Integración típica con Mongo/MySQL (idea general)
- **MongoDB**: guardar cada documento con `{ _id, text, pred_label, scores, proc: {ts: utcnow_iso(), model: MODEL_NAME} }`.
- **MySQL**: tabla tipo `dw_messages(id, user_id, comment, ingest_ts, sentiment_label, sentiment_score, raw_json)`.

## 7) Errores comunes y cómo evitarlos
- **`NameError: MODEL_NAME`** → define `MODEL_NAME` antes de cargar.
- **Descarga del modelo falla** (sin internet) → precachea el modelo o monta el directorio `~/.cache/huggingface`.
- **Clases no coinciden** → valida `mdl.config.id2label` y adapta tu mapeo/SQL.
- **GPU no usada** → mueve modelo y tensores con `.to(DEVICE)`.
- **Rendimiento** → procesa en lotes con `tqdm`, usa `batch_size` razonable y `torch.inference_mode()` para menos overhead.

¿Quieres que agregue el bloque de **persistencia** (insert a Mongo y upsert a MySQL) con manejo de reintentos y métricas? Lo puedo sumar aquí mismo.

