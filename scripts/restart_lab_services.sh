#!/usr/bin/env bash
# restart_lab_services.sh
# Reinicia contenedores y lanza Jupyter en tmux como usuario no root.
# Params:
#   $1 = APP_USER (default azureuser)
#   $2 = JUPYTER_PORT (default 8888)
#   $3 = TMUX_SESSION (default jupyterlab)
#   $4 = PUBLIC_IP_OVERRIDE (opcional)

set -Eeuo pipefail

APP_USER="${1:-${SUDO_USER:-azureuser}}"
JUPYTER_PORT="${2:-${JUPYTER_PORT:-8888}}"
TMUX_SESSION="${3:-${TMUX_SESSION:-jupyterlab}}"
PUBLIC_IP_OVERRIDE="${4:-}"

require_cmd() { command -v "$1" >/dev/null 2>&1; }
log()  { echo "[INFO] $*"; }
ok()   { echo "[OK] $*"; }
err()  { echo "[ERROR] $*" >&2; }

trap 'err "fallo en la linea $LINENO"' ERR

id "$APP_USER" >/dev/null 2>&1 || { err "El usuario ${APP_USER} no existe."; exit 1; }

log "User: ${APP_USER}"
log "Jupyter port: ${JUPYTER_PORT}"
log "tmux session: ${TMUX_SESSION}"

# tmux si falta
if ! require_cmd tmux; then
  export DEBIAN_FRONTEND=noninteractive
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y -qq && apt-get install -y -qq tmux
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q tmux
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q tmux
  fi
fi

# docker requerido
if ! require_cmd docker; then
  err "Docker is not installed or not in PATH."
  exit 1
fi
systemctl start docker >/dev/null 2>&1 || true

# curl para deteccion de IP publica
if ! require_cmd curl; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y -qq && apt-get install -y -qq curl
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q curl
  fi
fi

VM_PRIV_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

get_public_ip_imds() {
  require_cmd curl || return 1
  curl -sS -m 3 -H Metadata:true \
    "http://169.254.169.254/metadata/instance/network/interface?api-version=2021-02-01" \
  | tr -d '\r' \
  | grep -oE '"publicIpAddress"\s*:\s*"[^"]+"' \
  | head -n1 \
  | cut -d'"' -f4
}
get_public_ip_egress_ifconfig() { require_cmd curl || return 1; curl -sS -m 3 https://ifconfig.me || true; }
get_public_ip_egress_ipify()    { require_cmd curl || return 1; curl -sS -m 3 https://api.ipify.org || true; }

PUBIP=""
if [[ -n "$PUBLIC_IP_OVERRIDE" ]]; then
  PUBIP="$PUBLIC_IP_OVERRIDE"
else
  PUBIP="$(get_public_ip_imds || true)"
  [[ -z "$PUBIP" || "$PUBIP" == "null" ]] && PUBIP="$(get_public_ip_egress_ifconfig || true)"
  [[ -z "$PUBIP" || "$PUBIP" == "null" ]] && PUBIP="$(get_public_ip_egress_ipify || true)"
fi
[[ -z "$PUBIP" || "$PUBIP" == "null" ]] && PUBIP="<no-public-ip>"

ADV_IP="$VM_PRIV_IP"
if [[ "$PUBIP" != "<no-public-ip>" ]]; then ADV_IP="$PUBIP"; fi

# Red del lab
docker network create labnet >/dev/null 2>&1 || true

# MongoDB
docker rm -f mongodb >/dev/null 2>&1 || true
docker run -d \
  --name mongodb \
  --network labnet \
  -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=pass \
  --restart unless-stopped \
  mongo:6.0

# Mongo Express
docker rm -f mongo-express >/dev/null 2>&1 || true
docker run -d \
  --name mongo-express \
  --network labnet \
  -p 8081:8081 \
  -e ME_CONFIG_MONGODB_ADMINUSERNAME=admin \
  -e ME_CONFIG_MONGODB_ADMINPASSWORD=pass \
  -e ME_CONFIG_MONGODB_SERVER=mongodb \
  -e ME_CONFIG_MONGODB_PORT=27017 \
  --restart unless-stopped \
  mongo-express:latest

# Redis
docker rm -f redis >/dev/null 2>&1 || true
docker run -d \
  --name redis \
  --network labnet \
  -p 6379:6379 \
  --restart unless-stopped \
  redis:7.2

# RedisInsight
docker rm -f redisinsight >/dev/null 2>&1 || true
docker run -d \
  --name redisinsight \
  --network labnet \
  -p 8001:8001 \
  --restart unless-stopped \
  redislabs/redisinsight:1.14.0

# HBase
docker rm -f hbase >/dev/null 2>&1 || true
docker run -d \
  --name hbase \
  --network labnet \
  -p 2181:2181 \
  -p 16000:16000 \
  -p 16010:16010 \
  -p 16030:16030 \
  -p 9090:9090 \
  --restart unless-stopped \
  harisekhon/hbase:latest

# Kafka (KRaft) y Kafka UI
mkdir -p /data/kafka
docker rm -f kafka kafka-ui >/dev/null 2>&1 || true

docker run -d --name kafka --network labnet \
  -p 9092:9092 \
  -p 29092:29092 \
  -v /data/kafka:/bitnami/kafka \
  -e KAFKA_ENABLE_KRAFT=yes \
  -e KAFKA_CFG_NODE_ID=1 \
  -e KAFKA_CFG_PROCESS_ROLES=controller,broker \
  -e KAFKA_CFG_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=1@kafka:9093 \
  -e KAFKA_CFG_LISTENERS=PLAINTEXT://:9092,HOST://:29092,CONTROLLER://:9093 \
  -e KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092,HOST://127.0.0.1:29092 \
  -e KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,HOST:PLAINTEXT \
  -e KAFKA_CFG_INTER_BROKER_LISTENER_NAME=PLAINTEXT \
  -e KAFKA_CFG_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  -e KAFKA_CFG_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
  -e KAFKA_CFG_TRANSACTION_STATE_LOG_MIN_ISR=1 \
  --restart unless-stopped \
  bitnami/kafka:3.7

# Kafka UI con bootstrap interno

docker run -d --name kafka-ui --network labnet \
  -p 9000:8080 \
  -e KAFKA_CLUSTERS_0_NAME=local \
  -e KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS=kafka:9092 \
  --restart unless-stopped \
  provectuslabs/kafka-ui:latest

# Jupyter en tmux
log "Preparing Jupyter in tmux as ${APP_USER}"

su_exec() { sudo -u "$APP_USER" -H bash -lc "$*"; }

su_exec "mkdir -p ~/.jupyter"

JUPYTER_CMD="$(su_exec 'command -v jupyter || true')"
if [[ -z "$JUPYTER_CMD" ]]; then
  su_exec "python3 -m pip install --user --upgrade pip"
  su_exec "python3 -m pip install --user 'notebook<7'"
  JUPYTER_CMD="$(su_exec 'command -v jupyter')"
fi

if su_exec "tmux has-session -t ${TMUX_SESSION} 2>/dev/null"; then
  su_exec "tmux kill-session -t ${TMUX_SESSION}"
fi

JUPYTER_OPTS="--ip=0.0.0.0 --port=${JUPYTER_PORT} --no-browser --NotebookApp.token='' --NotebookApp.password=''"

su_exec "tmux new -d -s ${TMUX_SESSION} '${JUPYTER_CMD} notebook ${JUPYTER_OPTS} >> ~/.jupyter/jupyterlab.log 2>&1'"

# Resumen
ok "Jupyter Notebook in tmux (session: ${TMUX_SESSION})"
echo "Internal URL: http://${VM_PRIV_IP}:${JUPYTER_PORT}"
echo "Public  URL: http://${PUBIP}:${JUPYTER_PORT}"
echo "Attach via SSH: tmux attach -t ${TMUX_SESSION}"
echo "Logs: ~${APP_USER}/.jupyter/jupyterlab.log"
echo

echo "Service endpoints"
echo "-----------------"
printf "%-22s %-8s %s\n" "Mongo Express"       "8081"  "http://${PUBIP}:8081"
printf "%-22s %-8s %s\n" "RedisInsight"        "8001"  "http://${PUBIP}:8001"
printf "%-22s %-8s %s\n" "HBase Master UI"     "16010" "http://${PUBIP}:16010"
printf "%-22s %-8s %s\n" "HBase RegionServer"  "16030" "http://${PUBIP}:16030"
printf "%-22s %-8s %s\n" "Kafka UI"            "9000"  "http://${PUBIP}:9000"
printf "%-22s %-8s %s\n" "Kafka bootstrap VM"  "29092" "127.0.0.1:29092"
printf "%-22s %-8s %s\n" "Kafka bootstrap Int" "9092"  "kafka:9092"
printf "%-22s %-8s %s\n" "Jupyter Notebook"    "${JUPYTER_PORT}" "http://${PUBIP}:${JUPYTER_PORT}"
echo

echo "Credentials"
echo "-----------"
echo "Mongo Express -> user: admin  pass: pass"
echo "Jupyter Notebook -> sin token ni password; limitar por NSG o tunel SSH."
ok "Services restarted."