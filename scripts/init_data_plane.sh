#!/usr/bin/env bash
# scripts/init_data_plane.sh
# Inicializa la data plane del lab de forma idempotente.

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

if ! have docker; then
  err "docker no esta instalado o no esta en PATH"
  exit 1
fi
systemctl start docker >/dev/null 2>&1 || true

container_status(){
  docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null || echo "notfound"
}

wait_for_kafka(){
  # Espera hasta que Kafka responda comandos; timeout por defecto 240s
  local timeout="${1:-240}"
  local start now
  start=$(date +%s)
  while true; do
    # Debe estar en running
    if [[ "$(container_status kafka)" == "running" ]]; then
      # Probar un comando ligero
      if docker exec kafka /opt/bitnami/kafka/bin/kafka-topics.sh \
          --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
        return 0
      fi
    fi
    now=$(date +%s)
    if (( now - start > timeout )); then
      return 1
    fi
    sleep 3
  done
}

# 1) Asegurar MySQL y Metabase
if [[ "${ENSURE_EXTRAS}" == "true" ]]; then
  log "asegurando MySQL y Metabase..."
  if ! docker ps --format '{{.Names}}' | grep -qx mysql; then
    log "iniciando MySQL con helper..."
    [[ -x /opt/lab/bin/start_mysql.sh ]] || { err "no existe /opt/lab/bin/start_mysql.sh"; exit 1; }
    bash /opt/lab/bin/start_mysql.sh
  else
    ok "mysql ya esta corriendo"
  fi
  if ! docker ps --format '{{.Names}}' | grep -qx metabase; then
    log "iniciando Metabase con helper..."
    [[ -x /opt/lab/bin/start_metabase.sh ]] || { err "no existe /opt/lab/bin/start_metabase.sh"; exit 1; }
    bash /opt/lab/bin/start_metabase.sh
  else
    ok "metabase ya esta corriendo"
  fi
else
  log "ENSURE_EXTRAS=false (omitido)"
fi

# 2) Asegurar Kafka
if [[ "${ENSURE_KAFKA}" == "true" ]]; then
  log "asegurando Kafka y Kafka UI..."
  need_start=false
  docker ps --format '{{.Names}}' | grep -qx kafka || need_start=true
  docker ps --format '{{.Names}}' | grep -qx kafka-ui || need_start=true
  if [[ "${need_start}" == "true" ]]; then
    [[ -x /opt/lab/bin/start_kafka.sh ]] || { err "no existe /opt/lab/bin/start_kafka.sh"; exit 1; }
    bash /opt/lab/bin/start_kafka.sh
  else
    ok "kafka y kafka-ui ya estan corriendo"
  fi
else
  log "ENSURE_KAFKA=false (omitido)"
fi

# 3) Esquema MySQL
if [[ "${CREATE_MYSQL_SCHEMA}" == "true" ]]; then
  log "creando/verificando esquema MySQL en DB=${MYSQL_DB}..."
  docker ps --format '{{.Names}}' | grep -qx mysql || { err "mysql no esta corriendo"; exit 1; }
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

# 4) Topico Kafka
if [[ "${CREATE_KAFKA_TOPIC}" == "true" ]]; then
  log "creando/verificando topico Kafka: ${TOPIC}..."
  docker ps --format '{{.Names}}' | grep -qx kafka || { err "kafka no esta corriendo"; exit 1; }
  # Esperar readiness
  if ! wait_for_kafka 240; then
    err "Kafka no estuvo listo en el tiempo esperado. Logs recientes:"
    docker logs --tail 120 kafka >&2 || true
    exit 1
  fi
  docker exec kafka /opt/bitnami/kafka/bin/kafka-topics.sh \
    --create --if-not-exists --topic "${TOPIC}" --bootstrap-server localhost:9092
  ok "topico Kafka verificado: ${TOPIC}"
else
  log "CREATE_KAFKA_TOPIC=false (omitido)"
fi

ok "init_data_plane completado"
echo "Parametros:"
echo "  TOPIC=${TOPIC}"
echo "  MYSQL_DB=${MYSQL_DB}"
echo "  ENSURE_EXTRAS=${ENSURE_EXTRAS}"
echo "  ENSURE_KAFKA=${ENSURE_KAFKA}"
echo "  CREATE_MYSQL_SCHEMA=${CREATE_MYSQL_SCHEMA}"
echo "  CREATE_KAFKA_TOPIC=${CREATE_KAFKA_TOPIC}"
