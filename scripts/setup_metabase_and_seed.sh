#!/usr/bin/env bash
# Configura Metabase y crea 3 visualizaciones + dashboard (idempotente).
# Requiere: docker, curl, python3. Usa helpers /opt/lab/bin/start_*.sh si existen.

set -eu

# Parametros
ADMIN_EMAIL="${1:-admin@example.local}"
ADMIN_PASS="${2:-Metabase!123}"            # PASAR POR SECRETO EN EL ACTION
ADMIN_NAME="${3:-Admin User}"
MB_URL="${4:-http://127.0.0.1:3000}"

# Conexion a MySQL (DWH)
DB_HOST="${5:-mysql}"                      # nombre del contenedor, misma red
DB_PORT="${6:-3306}"
DB_NAME="${7:-lab}"
DB_USER="${8:-root}"
DB_PASS="${9:-pass}"
DB_DISPLAY_NAME="${10:-DWH}"

DASHBOARD_NAME="${11:-Sentiment Streaming (Kafka->Mongo->DL->MySQL)}"

log(){ echo "[$(date +'%F %T')] $*"; }
err(){ echo "ERROR: $*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }

trap 'err "fallo en la linea $LINENO"' ERR

# 0) Pre-chequeos
have docker || { err "docker no esta en PATH"; exit 1; }
have curl   || { err "curl no esta en PATH"; exit 1; }
have python3|| { err "python3 no esta en PATH"; exit 1; }

# 1) Asegurar MySQL y Metabase (helpers existentes)
if [[ -x /opt/lab/bin/start_mysql.sh ]]; then
  bash /opt/lab/bin/start_mysql.sh
fi
if [[ -x /opt/lab/bin/start_metabase.sh ]]; then
  bash /opt/lab/bin/start_metabase.sh
else
  # Fallback directo si no hubiese helper
  docker rm -f metabase >/dev/null 2>&1 || true
  mkdir -p /data/metabase
  docker run -d --name metabase \
    -p 3000:3000 \
    -v /data/metabase:/metabase-data \
    -e MB_DB_FILE=/metabase-data/metabase.db \
    --restart unless-stopped \
    metabase/metabase:latest
fi

# 2) Esperar Metabase
wait_up(){
  local url="$1" timeout="${2:-180}" start now
  start=$(date +%s)
  while true; do
    if curl -fsS "$url" >/dev/null 2>&1; then return 0; fi
    now=$(date +%s); (( now-start > timeout )) && return 1
    sleep 3
  done
}
log "esperando Metabase en ${MB_URL} ..."
wait_up "${MB_URL}/api/session/properties" 300 || { err "Metabase no respondio a tiempo"; exit 1; }

# 3) Descubrir estado de setup
props="$(curl -fsS "${MB_URL}/api/session/properties")"
is_setup="$(printf '%s' "$props" | python3 - <<'PY'
import sys,json
d=json.load(sys.stdin)
val=d.get("is_setup", d.get("setup-done", d.get("setup_done", False)))
print("true" if bool(val) else "false")
PY
)"
setup_token="$(printf '%s' "$props" | python3 - <<'PY'
import sys,json
d=json.load(sys.stdin)
print(d.get("setup_token", d.get("setup-token","")))
PY
)"

MB_SESSION=""

# 4) Setup inicial o login
if [[ "$is_setup" == "false" ]]; then
  log "Metabase sin configurar. Ejecutando /api/setup ..."
  payload="$(python3 - <<PY
import json, os
print(json.dumps({
  "token": os.environ["SETUP_TOKEN"],
  "user": {
    "first_name": os.environ["ADMIN_NAME"].split(" ")[0],
    "last_name": "Admin",
    "email": os.environ["ADMIN_EMAIL"],
    "password": os.environ["ADMIN_PASS"],
    "site_name": "Sentiment Dashboard"
  },
  "prefs": { "allow_tracking": False },
  "database": {
    "engine": "mysql",
    "name": os.environ["DB_DISPLAY_NAME"],
    "details": {
      "host": os.environ["DB_HOST"],
      "port": int(os.environ["DB_PORT"]),
      "db":   os.environ["DB_NAME"],
      "user": os.environ["DB_USER"],
      "password": os.environ["DB_PASS"],
      "ssl": False
    },
    "is_full_sync": True,
    "is_on_demand": True
  }
}))
PY
)"
  SETUP_TOKEN="$setup_token" ADMIN_NAME="$ADMIN_NAME" ADMIN_EMAIL="$ADMIN_EMAIL" ADMIN_PASS="$ADMIN_PASS" \
  DB_DISPLAY_NAME="$DB_DISPLAY_NAME" DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_NAME="$DB_NAME" DB_USER="$DB_USER" DB_PASS="$DB_PASS" \
  curl -fsS -X POST "${MB_URL}/api/setup" -H "Content-Type: application/json" -d "$payload" >/dev/null

  # Iniciar sesion
  MB_SESSION="$(curl -fsS -X POST "${MB_URL}/api/session" -H "Content-Type: application/json" \
    -d "{\"username\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASS}\"}" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
  log "setup completo y sesion creada."
else
  log "Metabase ya configurado. Iniciando sesion ..."
  MB_SESSION="$(curl -fsS -X POST "${MB_URL}/api/session" -H "Content-Type: application/json" \
    -d "{\"username\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASS}\"}" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
  log "sesion OK."
fi

api_get(){ curl -fsS -H "X-Metabase-Session: ${MB_SESSION}" "$@"; }
api_post(){ curl -fsS -X POST -H "X-Metabase-Session: ${MB_SESSION}" -H "Content-Type: application/json" "$@"; }

# 5) Asegurar base de datos DWH (por nombre)
db_id="$(api_get "${MB_URL}/api/database" | python3 - <<'PY'
import sys, json, os
name=os.environ["DB_DISPLAY_NAME"]
dbs=json.load(sys.stdin)
for d in dbs:
  if d.get("name")==name:
    print(d.get("id")); break
PY
)"
if [[ -z "${db_id:-}" ]]; then
  log "agregando base ${DB_DISPLAY_NAME} -> ${DB_HOST}:${DB_PORT}/${DB_NAME}"
  payload="$(python3 - <<PY
import json, os
print(json.dumps({
  "engine":"mysql",
  "name":os.environ["DB_DISPLAY_NAME"],
  "details":{
    "host":os.environ["DB_HOST"],
    "port":int(os.environ["DB_PORT"]),
    "db":os.environ["DB_NAME"],
    "user":os.environ["DB_USER"],
    "password":os.environ["DB_PASS"],
    "ssl":False
  },
  "is_full_sync": True,
  "is_on_demand": True
}))
PY
)"
  db_id="$(api_post "${MB_URL}/api/database" -d "$payload" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
  log "creada database id=${db_id}"
else
  log "database '${DB_DISPLAY_NAME}' ya existe (id=${db_id})"
fi

# 6) Crear (o reutilizar) tarjetas (cards) SQL
create_card(){
  local name="$1" sql="$2" display="$3"
  local cid
  cid="$(api_get "${MB_URL}/api/search?type=card&q=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$name")" \
    | python3 - <<'PY'
import sys,json,os
name=os.environ.get("CARD_NAME")
data=json.load(sys.stdin)
for it in data.get("data",[]):
  if it.get("model")=="card" and it.get("name")==name:
    print(it.get("id")); break
PY
CARD_NAME="$name"
)"
  if [[ -n "$cid" ]]; then
    echo "$cid"; return 0
  fi
  local payload
  payload="$(python3 - <<PY
import json, os
print(json.dumps({
  "name": os.environ["CARD_NAME"],
  "dataset_query": {
    "type": "native",
    "native": {"query": os.environ["CARD_SQL"], "template-tags": {}},
    "database": int(os.environ["DB_ID"])
  },
  "display": os.environ["CARD_DISPLAY"],
  "visualization_settings": {}
}))
PY
CARD_NAME="$name" CARD_SQL="$sql" CARD_DISPLAY="$display" DB_ID="$db_id"
)"
  cid="$(api_post "${MB_URL}/api/card" -d "$payload" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
  echo "$cid"
}

SQL1="SELECT sentiment_label, COUNT(*) AS n FROM dw_messages GROUP BY sentiment_label ORDER BY n DESC;"
SQL2="SELECT DATE_FORMAT(ingest_ts, '%Y-%m-%d %H:%i:00') AS minute, sentiment_label, COUNT(*) AS n FROM dw_messages GROUP BY minute, sentiment_label ORDER BY minute ASC;"
SQL3="SELECT user_id, COUNT(*) AS n_neg FROM dw_messages WHERE sentiment_label IN ('vneg','neg') GROUP BY user_id ORDER BY n_neg DESC LIMIT 10;"

CARD1_ID="$(create_card '01 Distribucion por sentimiento' "$SQL1" 'bar')"
CARD2_ID="$(create_card '02 Serie por minuto (stacked)' "$SQL2" 'area')"
CARD3_ID="$(create_card '03 Top usuarios negativos' "$SQL3" 'bar')"
log "cards: $CARD1_ID, $CARD2_ID, $CARD3_ID"

# 7) Crear (o reutilizar) dashboard y agregar cards
dash_id="$(api_get "${MB_URL}/api/dashboard" | python3 - <<'PY'
import sys,json,os
name=os.environ["DASHBOARD_NAME"]
for d in json.load(sys.stdin):
  if d.get("name")==name:
    print(d.get("id")); break
PY
DASHBOARD_NAME="$DASHBOARD_NAME"
)"
if [[ -z "${dash_id:-}" ]]; then
  dash_id="$(api_post "${MB_URL}/api/dashboard" -d "$(python3 - <<PY
import json, os
print(json.dumps({"name": os.environ["DASHBOARD_NAME"], "parameters": []}))
PY
DASHBOARD_NAME="$DASHBOARD_NAME"
)" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
  log "dashboard creado id=${dash_id}"
else
  log "dashboard ya existe (id=${dash_id})"
fi

add_card(){
  local did="$1" cid="$2" row="$3" col="$4" sx="$5" sy="$6"
  # evitar duplicados: listar ordered_cards
  local present
  present="$(api_get "${MB_URL}/api/dashboard/${did}" | python3 - <<'PY'
import sys,json,os
cid=int(os.environ["CID"])
oc=json.load(sys.stdin).get("ordered_cards",[])
print("yes" if any(c.get("card_id")==cid for c in oc) else "no")
PY
CID="$cid"
)"
  if [[ "$present" == "yes" ]]; then return 0; fi
  api_post "${MB_URL}/api/dashboard/${did}/cards" -d "$(python3 - <<PY
import json, os
print(json.dumps({"cardId": int(os.environ["CID"]), "row": int(os.environ["ROW"]), "col": int(os.environ["COL"]),
                  "sizeX": int(os.environ["SX"]), "sizeY": int(os.environ["SY"])}))
PY
CID="$cid" ROW="$row" COL="$col" SX="$sx" SY="$sy"
)" >/dev/null
}

# Layout simple
add_card "$dash_id" "$CARD1_ID" 0 0 12 8
add_card "$dash_id" "$CARD2_ID" 8 0 24 10
add_card "$dash_id" "$CARD3_ID" 0 12 12 8

log "Listo. Dashboard '${DASHBOARD_NAME}' y 3 visualizaciones configuradas."
echo "URL (via tunel): ${MB_URL}"
