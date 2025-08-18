#!/usr/bin/env bash
# scripts/init_data_plane.sh
# Inicializa la "data plane" del lab:
# - Opcional: asegura que esten arriba MySQL/Metabase (helpers de cloud-init)
# - Opcional: asegura que esten arriba Kafka/Kafka UI (helper de cloud-init)
# - Opcional: crea DB y tabla base en MySQL (lab.sentiment_events)
# - Opcional: crea topico Kafka
#
# Uso (parametros opcionales con defaults):
#   bash scripts/init_data_plane.sh <TOPIC> <MYSQL_DB> <ENSURE_EXTRAS> <ENSURE_KAFKA> <CREATE_MYSQL_SCHEMA> <CREATE_KAFKA_TOPIC>
#
# Ejemplo:
#   bash scripts/init_data_plane.sh "user-topic" "lab" "true" "false" "true" "true"

set -Eeuo pipefail

TOPIC="${1:-user-topic}"
MYSQL_DB="${2:-lab}"
ENSURE_EXTRAS="${3:-true}"          # true/false -> MySQL y Metabase
ENSURE_KAFKA="${4:-false}"          # true/false -> Kafka y Kafka UI
CREATE_MYSQL_SCHEMA="${5:-true}"    # true/false
CREATE_KAFKA_TOPIC="${6:-true}"     # true/false

log(){ echo "[INFO] $*"; }
ok(){ echo "[OK] $*"; }
err(){ echo "[ERROR] $*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }

trap 'err "fallo en la linea $LINENO"' ERR

# 0) Requisitos basicos
if ! have docker; then
  err "docker no esta instalado o no esta en PATH"
  exit 1
fi
systemctl start docker >/dev/null 2>&1 || true

# 1) Asegurar extras si se solicito
if [[ "${ENSURE_EXTRAS}" == "true" ]]; then
  log "asegurando MySQL y Metabase..."
  # MySQL
  if ! docker ps --format '{{.Names}}' | grep -qx mysql; then
    log "iniciando MySQL con helper..."
    if [[ -x /opt/lab/bin/start_mysql.sh ]]; then
      bash /opt/lab/bin/start_mysql.sh
    else
      err "no existe /opt/lab/bin/start_mysql.sh"
      exit 1
    fi
  else
    ok "mysql ya esta corriendo"
  fi
  # Metabase
  if ! docker ps --format '{{.Names}}' | grep -qx metabase; then
    log "iniciando Metabase con helper..."
    if [[ -x /opt/lab/bin/start_metabase.sh ]]; then
      bash /opt/lab/bin/start_metabase.sh
    else
      err "no existe /opt/lab/bin/start_metabase.sh"
      exit 1
    fi
  else
    ok "metabase ya esta corriendo"
  fi
else
  log "ENSURE_EXTRAS=false (omitido)"
fi

# 2) Asegurar Kafka si se solicito
if [[ "${ENSURE_KAFKA}" == "true" ]]; then
  log "asegurando Kafka y Kafka UI..."
  need_start=false
  docker ps --format '{{.Names}}' | grep -qx kafka || need_start=true
  docker ps --format '{{.Names}}' | grep -qx kafka-ui || need_start=true

  if [[ "${need_start}" == "true" ]]; then
    if [[ -x /opt/lab/bin/start_kafka.sh ]]; then
      bash /opt/lab/bin/start_kafka.sh
    else
      err "no existe /opt/lab/bin/start_kafka.sh"
      exit 1
    fi
  else
    ok "kafka y kafka-ui ya estan corriendo"
  fi
else
  log "ENSURE_KAFKA=false (omitido)"
fi

# 3) Crear esquema MySQL si se solicito
if [[ "${CREATE_MYSQL_SCHEMA}" == "true" ]]; then
  log "creando/verificando esquema MySQL en DB=${MYSQL_DB}..."
  if ! docker ps --format '{{.Names}}' | grep -qx mysql; then
    err "mysql no esta corriendo; inicia ENSURE_EXTRAS=true o arranca el helper"
    exit 1
  fi

  docker exec -i mysql mysql -uroot -ppass <<SQL
CREATE DATABASE IF NOT EXISTS ${MYSQL_DB};
USE ${MYSQL_DB};
CREATE TABLE IF NOT EXISTS sentiment_events (
  id_mongo VARCHAR(64),
  ts DATETIME,
  user_id VARCHAR(64),
  text TEXT,
  label VARCHAR(16),
  p_negative FLOAT,
  p_neutral  FLOAT,
  p_positive FLOAT
);
SQL
  ok "esquema MySQL verificado en DB=${MYSQL_DB}"
else
  log "CREATE_MYSQL_SCHEMA=false (omitido)"
fi

# 4) Crear topico Kafka si se solicito
if [[ "${CREATE_KAFKA_TOPIC}" == "true" ]]; then
  log "creando/verificando topico Kafka: ${TOPIC}..."
  if ! docker ps --format '{{.Names}}' | grep -qx kafka; then
    err "kafka no esta corriendo; inicia ENSURE_KAFKA=true o arranca el helper"
    exit 1
  fi

  docker exec kafka /opt/bitnami/kafka/bin/kafka-topics.sh \
    --create --if-not-exists --topic "${TOPIC}" --bootstrap-server localhost:9092
  ok "topico Kafka verificado: ${TOPIC}"
else
  log "CREATE_KAFKA_TOPIC=false (omitido)"
fi

echo
ok "init_data_plane completado"
echo "Parametros:"
echo "  TOPIC=${TOPIC}"
echo "  MYSQL_DB=${MYSQL_DB}"
echo "  ENSURE_EXTRAS=${ENSURE_EXTRAS}"
echo "  ENSURE_KAFKA=${ENSURE_KAFKA}"
echo "  CREATE_MYSQL_SCHEMA=${CREATE_MYSQL_SCHEMA}"
echo "  CREATE_KAFKA_TOPIC=${CREATE_KAFKA_TOPIC}"
