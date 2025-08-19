#!/usr/bin/env bash
# scripts/init_data_plane.sh
# Inicializa la data plane del lab de forma idempotente.
# Corrige la creacion de tabla MySQL: usa lab.dw_messages (5 clases de sentimiento).

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
    if [[ "$(container_status kafka)" == "running" ]]; then
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

# 3) Esquema MySQL (tabla correcta: dw_messages)
if [[ "${CREATE_MYSQL_SCHEMA}" == "true" ]]; then
  log "creando/verificando esquema MySQL en DB=${MYSQL_DB}..."
  docker ps --format '{{.Names}}' | grep -qx mysql || { err "mysql no esta corriendo"; exit 1; }
  docker exec -i mysql mysql -uroot -ppass <<SQL
CREATE DATABASE IF NOT EXISTS ${MYSQL_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ${MYSQL_DB};

-- Tabla DWH con 5 clases: vneg,neg,neu,pos,vpos
CREATE TABLE IF NOT EXISTS dw_messages (
  id               VARCHAR(64)  NOT NULL PRIMARY KEY,
  user_id          VARCHAR(64)  NOT NULL,
  comment          TEXT         NOT NULL,
  ingest_ts        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  sentiment_label  ENUM('vneg','neg','neu','pos','vpos') NOT NULL,
  sentiment_score  FLOAT        NOT NULL,
  raw_json         JSON         NULL,
  INDEX idx_ingest_ts (ingest_ts DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Crear indice por tiempo si faltara (idempotente via SQL dinamico)
SET @idx_exists := (
  SELECT COUNT(1) FROM information_schema.statistics
  WHERE table_schema='${MYSQL_DB}' AND table_name='dw_messages' AND index_name='idx_ingest_ts'
);
SET @sql := IF(@idx_exists=0, 'CREATE INDEX idx_ingest_ts ON dw_messages (ingest_ts DESC);', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SQL
  ok "esquema MySQL verificado en DB=${MYSQL_DB} (tabla dw_messages)"
else
  log "CREATE_MYSQL_SCHEMA=false (omitido)"
fi

# 4) Topico Kafka
if [[ "${CREATE_KAFKA_TOPIC}" == "true" ]]; then
  log "creando/verificando topico Kafka: ${TOPIC}..."
  docker ps --format '{{.Names}}' | grep -qx kafka || { err "kafka no esta corriendo"; exit 1; }
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
