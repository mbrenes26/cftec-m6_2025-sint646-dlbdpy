#!/usr/bin/env sh
# scripts/setup_metabase_and_seed.sh
# Idempotente. Inicializa Metabase (admin), agrega DB MySQL, crea 3 cards y un dashboard.
# Argumentos (en este orden):
#  1 ADMIN_EMAIL
#  2 ADMIN_PASS
#  3 ADMIN_NAME            (usar underscores en lugar de espacios al invocar; aqui se vuelven espacios)
#  4 MB_URL                (ej: http://127.0.0.1:3000)
#  5 DB_HOST               (ej: mysql)
#  6 DB_PORT               (ej: 3306)
#  7 DB_NAME               (ej: lab)
#  8 DB_USER               (ej: root)
#  9 DB_PASS               (ej: pass)
# 10 DB_DISPLAY            (nombre logico en Metabase; se usa tal cual)
# 11 DASH_TITLE            (usar underscores; aqui se vuelven espacios)

set -eu

# -------------------------------
# Args
# -------------------------------
ADMIN_EMAIL="${1:?arg1 ADMIN_EMAIL requerido}"
ADMIN_PASS="${2:?arg2 ADMIN_PASS requerido}"
# Convierto underscores a espacios para campos "bonitos"
ADMIN_NAME_RAW="${3:?arg3 ADMIN_NAME requerido}"
MB_URL="${4:?arg4 MB_URL requerido}"
DB_HOST="${5:?arg5 DB_HOST requerido}"
DB_PORT="${6:?arg6 DB_PORT requerido}"
DB_NAME="${7:?arg7 DB_NAME requerido}"
DB_USER="${8:?arg8 DB_USER requerido}"
DB_PASS="${9:?arg9 DB_PASS requerido}"
DB_DISPLAY="${10:?arg10 DB_DISPLAY requerido}"
DASH_TITLE_RAW="${11:?arg11 DASH_TITLE requerido}"

ADMIN_NAME=$(printf %s "$ADMIN_NAME_RAW" | tr '_' ' ')
DASH_TITLE=$(printf %s "$DASH_TITLE_RAW" | tr '_' ' ')

# -------------------------------
# Utils
# -------------------------------
TMPDIR="${TMPDIR:-/tmp}"
RESP_BODY="$TMPDIR/mb_resp_body.$$"
RESP_CODE="$TMPDIR/mb_resp_code.$$"

cleanup() {
  rm -f "$RESP_BODY" "$RESP_CODE" 2>/dev/null || true
}
trap cleanup EXIT

die() {
  echo "ERROR: $*" >&2
  exit 1
}

jescape() {
  # Escapa string para JSON (sin jq)
  # - backslash
  # - comillas dobles
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# curl_json METHOD PATH [DATA]
# Deja:
#  - cuerpo en $RESP_BODY
#  - codigo http en $RESP_CODE
curl_json() {
  method="$1"; path="$2"; data="${3:-}"
  url="$MB_URL$path"
  if [ -n "$data" ]; then
    # data ya debe venir como JSON
    curl -sS -m 10 -w '%{http_code}' -o "$RESP_BODY" \
      -H 'Content-Type: application/json' \
      -X "$method" "$url" --data "$data" > "$RESP_CODE" || true
  else
    curl -sS -m 10 -w '%{http_code}' -o "$RESP_BODY" \
      -H 'Content-Type: application/json' \
      -X "$method" "$url" > "$RESP_CODE" || true
  fi
}

# curl_json_auth METHOD PATH TOKEN [DATA]
curl_json_auth() {
  method="$1"; path="$2"; token="$3"; data="${4:-}"
  url="$MB_URL$path"
  if [ -n "$data" ]; then
    curl -sS -m 15 -w '%{http_code}' -o "$RESP_BODY" \
      -H 'Content-Type: application/json' \
      -H "X-Metabase-Session: $token" \
      -X "$method" "$url" --data "$data" > "$RESP_CODE" || true
  else
    curl -sS -m 15 -w '%{http_code}' -o "$RESP_BODY" \
      -H 'Content-Type: application/json' \
      -H "X-Metabase-Session: $token" \
      -X "$method" "$url" > "$RESP_CODE" || true
  fi
}

# get_json_value FILE KEY   -> imprime valor si existe, sino vacio
get_json_value() {
  file="$1"; key="$2"
  python3 - "$file" "$key" <<'PY' || true
import sys, json
fn, key = sys.argv[1], sys.argv[2]
try:
    with open(fn, 'r', encoding='utf-8') as f:
        s=f.read().strip()
        if not s:
            print("")
            sys.exit(0)
        obj=json.loads(s)
        # soporta claves con guion bajo o medio
        if key in obj: print(obj.get(key,"")); sys.exit(0)
        alt = key.replace('_','-')
        if alt in obj: print(obj.get(alt,"")); sys.exit(0)
        # buscar recursivo superficial
        if isinstance(obj, dict):
            for k,v in obj.items():
                if isinstance(v, dict) and key in v:
                    print(v.get(key,"")); sys.exit(0)
        print("")
except Exception:
    print("")
PY
}

# valida que archivo tenga JSON valido
ensure_json_or_die() {
  f="$1"; ctx="$2"
  python3 - "$f" <<'PY' || ( echo "Respuesta no JSON en: $ctx" >&2; exit 1 )
import sys, json
fn=sys.argv[1]
s=open(fn,'r',encoding='utf-8').read().strip()
if s:
    json.loads(s)
PY
}

# -------------------------------
# 0) Espera rapida (por si no lo hizo el workflow)
# -------------------------------
# health = 200 -> listo
curl_json GET "/api/health"
code=$(cat "$RESP_CODE")
if [ "$code" != "200" ]; then
  echo "[info] esperando Metabase en $MB_URL ..."
  start=$(date +%s)
  while :; do
    curl_json GET "/api/health"
    code=$(cat "$RESP_CODE")
    [ "$code" = "200" ] && break
    now=$(date +%s)
    [ $((now-start)) -ge 240 ] && die "Metabase no listo tras 240s (code=$code)"
    sleep 3
  done
fi
echo "[ok] /api/health 200"

# -------------------------------
# 1) Detectar si ya esta configurado
# -------------------------------
curl_json GET "/api/session/properties"
# puede ser JSON o vacio si algo raro; verifico cuando lo necesite
SETUP_TOKEN="$(get_json_value "$RESP_BODY" 'setup_token')"
[ -z "$SETUP_TOKEN" ] && SETUP_TOKEN="$(get_json_value "$RESP_BODY" 'setup-token' || true)"

SESSION_ID=""

if [ -n "$SETUP_TOKEN" ]; then
  # Requiere setup
  echo "[info] instancia sin configurar; realizando /api/setup"
  FN="$(jescape "$ADMIN_NAME")"
  EM="$(jescape "$ADMIN_EMAIL")"
  PW="$(jescape "$ADMIN_PASS")"
  SN="$(jescape 'Lab')"
  TK="$(jescape "$SETUP_TOKEN")"

  # antes (mal): ... "preferences":{...}, last_name:""
  # despues (bien): "prefs":{...}, last_name:"Admin"
  payload='{"token":"'"$TK"'","user":{"first_name":"'"$FN"'","last_name":"Admin","email":"'"$EM"'","password":"'"$PW"'"}, "prefs":{"site_name":"'"$SN"'"}}'

  curl_json POST "/api/setup" "$payload"
  code=$(cat "$RESP_CODE")
  [ "$code" = "200" ] || { echo "Respuesta /api/setup (code=$code):"; cat "$RESP_BODY"; die "/api/setup fallo"; }
  ensure_json_or_die "$RESP_BODY" "/api/setup"
  SESSION_ID="$(get_json_value "$RESP_BODY" 'id')"
  [ -z "$SESSION_ID" ] && die "No se obtuvo session id tras /api/setup"
  echo "[ok] setup completado; session=$SESSION_ID"
else
  # Ya configurado -> login
  echo "[info] instancia ya configurada; realizando login /api/session"
  EM="$(jescape "$ADMIN_EMAIL")"
  PW="$(jescape "$ADMIN_PASS")"
  payload='{"username":"'"$EM"'","password":"'"$PW"'"}'
  curl_json POST "/api/session" "$payload"
  code=$(cat "$RESP_CODE")
  [ "$code" = "200" ] || { echo "Respuesta /api/session (code=$code):"; cat "$RESP_BODY"; die "login fallo"; }
  ensure_json_or_die "$RESP_BODY" "/api/session"
  SESSION_ID="$(get_json_value "$RESP_BODY" 'id')"
  [ -z "$SESSION_ID" ] && die "No se obtuvo session id tras /api/session"
  echo "[ok] login; session=$SESSION_ID"
fi

# -------------------------------
# 2) Crear conexion a MySQL si no existe
# -------------------------------
curl_json_auth GET "/api/database" "$SESSION_ID"
code=$(cat "$RESP_CODE")
[ "$code" = "200" ] || { echo "Respuesta /api/database (GET) code=$code:"; cat "$RESP_BODY"; die "listar DBs fallo"; }

# buscar por nombre
DB_ID="$(python3 - "$RESP_BODY" "$DB_DISPLAY" <<'PY' || true
import sys, json
fn, name = sys.argv[1], sys.argv[2]
try:
    arr=json.loads(open(fn,'r',encoding='utf-8').read())
    for d in arr:
        if isinstance(d, dict) and d.get('name')==name:
            print(d.get('id',''))
            break
except Exception:
    pass
PY
)"
if [ -z "$DB_ID" ]; then
  echo "[info] creando conexion MySQL '${DB_DISPLAY}'"
  # payload para motor mysql
  # ssl false; ajusta si necesitas
  payload=$(cat <<JSON
{
  "engine": "mysql",
  "name": "$(jescape "$DB_DISPLAY")",
  "details": {
    "host": "$(jescape "$DB_HOST")",
    "port": $DB_PORT,
    "dbname": "$(jescape "$DB_NAME")",
    "user": "$(jescape "$DB_USER")",
    "password": "$(jescape "$DB_PASS")",
    "ssl": false
  },
  "is_full_sync": true,
  "is_on_demand": false,
  "schedules": {}
}
JSON
)
  curl_json_auth POST "/api/database" "$SESSION_ID" "$payload"
  code=$(cat "$RESP_CODE")
  [ "$code" = "200" ] || [ "$code" = "201" ] || { echo "Respuesta /api/database (POST) code=$code:"; cat "$RESP_BODY"; die "crear DB fallo"; }
  ensure_json_or_die "$RESP_BODY" "/api/database POST"
  DB_ID="$(get_json_value "$RESP_BODY" 'id')"
  [ -z "$DB_ID" ] && die "No se obtuvo DB_ID tras crear DB"
else
  echo "[ok] DB ya existe id=$DB_ID"
fi

# -------------------------------
# 3) Crear 3 tarjetas (SQL nativas) y dashboard
# -------------------------------
make_card() {
  title="$1"; sql="$2"
  payload=$(cat <<JSON
{
  "name": "$(jescape "$title")",
 
