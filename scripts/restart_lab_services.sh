#!/bin/bash
set -e

echo "🚀 Reiniciando servicios del laboratorio..."

# MongoDB
docker rm -f mongodb || true
docker run -d \
  --name mongodb \
  -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=pass \
  --restart unless-stopped \
  mongo:6.0

# Mongo Express
docker rm -f mongo-express || true
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
docker rm -f redis || true
docker run -d \
  --name redis \
  -p 6379:6379 \
  --restart unless-stopped \
  redis:7.2

# RedisInsight
docker rm -f redisinsight || true
docker run -d \
  --name redisinsight \
  -p 8001:8001 \
  --restart unless-stopped \
  redislabs/redisinsight:1.14.0

# HBase
docker rm -f hbase || true
docker run -d \
  --name hbase \
  -p 2181:2181 \
  -p 16000:16000 \
  -p 16010:16010 \
  -p 16030:16030 \
  -p 9090:9090 \
  --restart unless-stopped \
  harisekhon/hbase:latest

# Jupyter Notebook con tmux
tmux kill-session -t jupyterlab 2>/dev/null || true
tmux new-session -d -s jupyterlab \
  "jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser"

echo "✅ Todos los servicios están arriba."
