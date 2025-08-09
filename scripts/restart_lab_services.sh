#!/usr/bin/env bash
# Restart containers and start Jupyter inside tmux as a non-root user
# Params:
#   $1 = APP_USER (default azureuser)
#   $2 = JUPYTER_PORT (default 8888)
#   $3 = TMUX_SESSION (default jupyterlab)

set -Eeuo pipefail

APP_USER="${1:-${SUDO_USER:-azureuser}}"
JUPYTER_PORT="${2:-${JUPYTER_PORT:-8888}}"
TMUX_SESSION="${3:-${TMUX_SESSION:-jupyterlab}}"

echo "[INFO] User: ${APP_USER}"
echo "[INFO] Jupyter port: ${JUPYTER_PORT}"
echo "[INFO] tmux session: ${TMUX_SESSION}"

require_cmd() { command -v "$1" >/dev/null 2>&1; }

# Ensure tmux is available (quiet install if missing)
if ! require_cmd tmux; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y -qq
  apt-get install -y -qq tmux
fi

# Ensure Docker is available
if ! require_cmd docker; then
  echo "[ERROR] Docker is not installed or not in PATH."
  exit 1
fi

# MongoDB
docker rm -f mongodb >/dev/null 2>&1 || true
docker run -d \
  --name mongodb \
  -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=pass \
  --restart unless-stopped \
  mongo:6.0

# Mongo Express
docker rm -f mongo-express >/dev/null 2>&1 || true
docker run -d \
  --name mongo-express \
  -p 8081:8081 \
  -e ME_CONFIG_MONGODB_ADMINUSERNAME=admin \
  -e ME_CONFIG_MONGODB_ADMINPASSWORD=pass \
  -e ME_CONFIG_MONGODB_SERVER=mongodb \
  --link mongodb:mongo \
  --restart unless-stopped \
  mongo-express:latest

# Redis
docker rm -f redis >/dev/null 2>&1 || true
docker run -d \
  --name redis \
  -p 6379:6379 \
  --restart unless-stopped \
  redis:7.2

# RedisInsight
docker rm -f redisinsight >/dev/null 2>&1 || true
docker run -d \
  --name redisinsight \
  -p 8001:8001 \
  --restart unless-stopped \
  redislabs/redisinsight:1.14.0

# HBase
docker rm -f hbase >/dev/null 2>&1 || true
docker run -d \
  --name hbase \
  -p 2181:2181 \
  -p 16000:16000 \
  -p 16010:16010 \
  -p 16030:16030 \
  -p 9090:9090 \
  --restart unless-stopped \
  harisekhon/hbase:latest

echo "[INFO] Preparing Jupyter in tmux as ${APP_USER}"

su_exec() { sudo -u "$APP_USER" -H bash -lc "$*"; }

su_exec "mkdir -p ~/.jupyter"

# Locate jupyter for the target user; install if missing
JUPYTER_CMD="$(su_exec 'command -v jupyter || true')"
if [[ -z "$JUPYTER_CMD" ]]; then
  su_exec "python3 -m pip install --user --upgrade pip"
  su_exec "python3 -m pip install --user notebook"
  JUPYTER_CMD="$(su_exec 'command -v jupyter')"
fi

# Kill previous tmux session if any
if su_exec "tmux has-session -t ${TMUX_SESSION} 2>/dev/null"; then
  su_exec "tmux kill-session -t ${TMUX_SESSION}"
fi

JUPYTER_OPTS="--ip=0.0.0.0 --port=${JUPYTER_PORT} --no-browser --NotebookApp.token='' --NotebookApp.password=''"

# Start Jupyter inside tmux and log to user's home
su_exec "tmux new -d -s ${TMUX_SESSION} '${JUPYTER_CMD} notebook ${JUPYTER_OPTS} >> ~/.jupyter/jupyterlab.log 2>&1'"

VM_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "[OK] Jupyter Notebook in tmux (session: ${TMUX_SESSION})"
echo "Internal URL: http://${VM_IP}:${JUPYTER_PORT}"
echo "Attach via SSH: tmux attach -t ${TMUX_SESSION}"
echo "Logs: ~${APP_USER}/.jupyter/jupyterlab.log"
echo "[OK] Services restarted."
