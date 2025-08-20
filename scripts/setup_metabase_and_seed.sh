#!/usr/bin/env sh
# scripts/setup_metabase_and_seed.sh
# Idempotente: inicializa Metabase (admin), crea conexion MySQL, 3 cards y 1 dashboard.
# Uso / Argumentos:
#  1 ADMIN_EMAIL
#  2 ADMIN_PASS
#  3 ADMIN_NAME            (usar underscores; aqui se convierten a espacios)
#  4 MB_URL                (ej: http://127.0.0.1:3000)
#  5 DB_HOST               (ej: mysql)
#  6 DB_PORT               (ej: 3306)
#  7 DB_NAME               (ej: lab)
#  8 DB_USER               (ej: metabase)
#  9 DB_PASS               (ej: mb_pass_123)
# 10 DB_DISPLAY            (nombre logico de la conexion en Metabase)
# 11 DASH_TITLE            (usar underscores; aqui se convierten a espacios)

set -eu

# -------------------------------
# Args
# -------------------------------
ADMIN_EMAIL="${1:?arg1 ADMIN_EMAIL requerido}"
ADMIN_PASS="${2:?arg2 ADMIN_PASS requerido}"
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

have() { command -v "$1" >/dev/null 2>&1; }

ensure_python3() {
  if ! have python3; then
    if have apt-get; then
      echo "[info] instalando python3 via apt-get"
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y python3 >/dev/null 2>&1 || true
    fi
  fi
  have python3 || die "python3 no disponible"
}

jescape() {
  # Escapa para JSON sin jq
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# curl_json METHOD PATH [DATA_JSON]
curl_json() {
  method="$1"; path="$2"; data="${3:-}"; url="$MB_URL$path"
  if [ -n "$data" ]; then
    curl -sS -m 20 -w '%{http_code}' -o "$RESP_BODY" \
      -H 'Content-Type: application/json' \
      -X "$method" "$url" --data "$data" > "$RESP_CODE" || true
  else
    curl -sS -m 20 -w '%{http_code}' -o "$RESP_BODY" \
      -H 'Content-Type: application/json' \
      -X "$method" "$url" > "$RESP_CODE" || true
  fi
}

# curl_json_auth METHOD PATH TOKEN [DATA_JSON]
curl_json_auth() {
  method="$1"; path="$2"; token="$3"; data="${4:-}"; url="$MB_URL$path"
  if [ -n "$data" ]; then
    curl -sS -m 25 -w '%{http_code}' -o "$RESP_BODY" \
      -H 'Content-Type: application/json' \
      -H "X-Metabase-Session: $token" \
      -X "$method" "$url" --data "$data" > "$RESP_CODE" || true
  else
    curl -sS -m 25 -w '%{http_code}' -o "$RESP_BODY" \
      -H 'Content-Type: application/json' \
      -H "X-Metabase-Session: $token" \
      -X "$method" "$url" > "$RESP_CODE" || true
  fi
}

# get_json_value FILE KEY
get_json_value() {
  file="$1"; key="$2"
  python3 - "$file" "$key" <<'PY' || true
import sys, json
fn, key = sys.argv[1], sys.argv[2]
try:
    s=open(fn,'r',encoding='utf-8').read().strip()
    if not s:
        print(""); sys.exit(0)
    obj=json.loads(s)
    if isinstance(obj, dict):
        if key in obj:
            print(obj.get(key,"")); sys.exit(0)
        alt = key.replace('_','-')
        if alt in obj:
            print(obj.get(alt,"")); sys.exit(0)
        for v in obj.values():
            if isinstance(v, dict) and key in v:
                print(v.get(key,"")); sys.exit(0)
    print("")
except Exception:
    print("")
PY
}

ensure_json_or_die() {
  f="$1"; ctx="$2"
  python3 - "$f"<<'PY' || { echo "Respuesta no JSON en: $ctx" >&2; exit 1; }
import sys, json
fn = sys.argv[1]
s = open(fn,'r',encoding='utf-8').read().strip()
if s:
    json.loads(s)
PY
}


ensure_python3

# -------------------------------
# 0) Healthcheck Metabase
# -------------------------------
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
# 1) Decidir setup vs login
# -------------------------------
curl_json GET "/api/session/properties"
SETUP_TOKEN="$(get_json_value "$RESP_BODY" 'setup_token')"
[ -z "$SETUP_TOKEN" ] && SETUP_TOKEN="$(get_json_value "$RESP_BODY" 'setup-token' || true)"
HAS_USER_SETUP="$(get_json_value "$RESP_BODY" 'has_user_setup')"
[ -z "$HAS_USER_SETUP" ] && HAS_USER_SETUP="$(get_json_value "$RESP_BODY" 'has-user-setup' || true)"

SESSION_ID=""

login() {
  EM="$(jescape "$ADMIN_EMAIL")"
  PW="$(jescape "$ADMIN_PASS")"
  payload='{"username":"'"$EM"'","password":"'"$PW"'"}'
  curl_json POST "/api/session" "$payload"
  c=$(cat "$RESP_CODE")
  [ "$c" = "200" ] || { echo "Respuesta /api/session (code=$c):"; cat "$RESP_BODY"; die "login fallo"; }
  ensure_json_or_die "$RESP_BODY" "/api/session"
  SESSION_ID="$(get_json_value "$RESP_BODY" 'id')"
  [ -z "$SESSION_ID" ] && die "No se obtuvo session id tras /api/session"
  echo "[ok] login; session=$SESSION_ID"
}

if [ "$HAS_USER_SETUP" = "true" ]; then
  echo "[info] instancia ya configurada; login"
  login
else
  if [ -z "$SETUP_TOKEN" ]; then
    echo "[warn] no hay setup-token; intentare login directo"
    login
  else
    echo "[info] instancia sin configurar; /api/setup"
    FN="$(jescape "$ADMIN_NAME")"
    EM="$(jescape "$ADMIN_EMAIL")"
    PW="$(jescape "$ADMIN_PASS")"
    SN="$(jescape 'Lab')"
    TK="$(jescape "$SETUP_TOKEN")"
    payload='{"token":"'"$TK"'","user":{"first_name":"'"$FN"'","last_name":"Admin","email":"'"$EM"'","password":"'"$PW"'"}, "prefs":{"site_name":"'"$SN"'"}}'
    curl_json POST "/api/setup" "$payload"
    c=$(cat "$RESP_CODE")
    if [ "$c" = "403" ]; then
      echo "[info] /api/setup 403; parece que ya existe usuario; login"
      login
    else
      [ "$c" = "200" ] || { echo "Respuesta /api/setup (code=$c):"; cat "$RESP_BODY"; die "/api/setup fallo"; }
      ensure_json_or_die "$RESP_BODY" "/api/setup"
      # Login explicito para obtener session id fiable
      login
    fi
  fi
fi

# -------------------------------
# 2) Asegurar conexion MySQL
# -------------------------------
curl_json_auth GET "/api/database" "$SESSION_ID"
c=$(cat "$RESP_CODE")
[ "$c" = "200" ] || { echo "Respuesta /api/database (GET) code=$c:"; cat "$RESP_BODY"; die "listar DBs fallo"; }

DB_ID="$(python3 - "$RESP_BODY" "$DB_DISPLAY" <<'PY' || true
import sys, json
fn, name = sys.argv[1], sys.argv[2]
try:
    obj=json.loads(open(fn,'r',encoding='utf-8').read())
    if isinstance(obj, list):
        arr = obj
    elif isinstance(obj, dict):
        arr = obj.get('data', [])
    else:
        arr = []
    for d in arr:
        if isinstance(d, dict) and d.get('name') == name:
            print(d.get('id','')); break
except Exception:
    pass
PY
)"

if [ -z "$DB_ID" ]; then
  echo "[info] creando conexion MySQL '${DB_DISPLAY}'"
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
  c=$(cat "$RESP_CODE")
  [ "$c" = "200" ] || [ "$c" = "201" ] || { echo "Respuesta /api/database (POST) code=$c:"; cat "$RESP_BODY"; die "crear DB fallo"; }
  ensure_json_or_die "$RESP_BODY" "/api/database POST"
  DB_ID="$(get_json_value "$RESP_BODY" 'id')"
  [ -z "$DB_ID" ] && die "No se obtuvo DB_ID tras crear DB"
  # Disparar sincronizacion de esquema (opcional)
  curl_json_auth POST "/api/database/$DB_ID/sync_schema" "$SESSION_ID" '{}'
  sc=$(cat "$RESP_CODE")
  if [ "$sc" = "200" ] || [ "$sc" = "202" ]; then
    echo "[ok] sync_schema disparado para DB id=$DB_ID"
  else
    echo "[warn] sync_schema code=$sc (continuo)"
  fi
else
  echo "[ok] DB ya existe id=$DB_ID"
fi

# -------------------------------
# 3) Crear tarjetas SQL nativas y dashboard (idempotente, stdout=solo IDs)
# -------------------------------

# helper: urlencode
urlencode() {
  python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

# Busca una card por nombre. Imprime ID o vacio (solo ID en stdout).
find_card_by_name() {
  title="$1"
  q="$(urlencode "$title")"
  curl_json_auth GET "/api/search?q=$q&type=card&archived=false" "$SESSION_ID"
  code=$(cat "$RESP_CODE")
  if [ "$code" != "200" ]; then
    echo "[warn] /api/search (card) code=$code" >&2
    cat "$RESP_BODY" >&2
    echo "" >&2
    return 0
  fi
  ensure_json_or_die "$RESP_BODY" "/api/search (card)"
  python3 - "$RESP_BODY" "$title" <<'PY' || true
import sys, json
fn, want = sys.argv[1], sys.argv[2]
try:
    arr = json.loads(open(fn,'r',encoding='utf-8').read())
    for it in arr:
        if isinstance(it, dict) and it.get('model')=='card' and it.get('name')==want:
            print(it.get('id',''))
            break
except Exception:
    pass
PY
}

# Crea card nativa si no existe. Imprime ID (solo ID en stdout).
make_card() {
  title="$1"; sql="$2"

  CID="$(find_card_by_name "$title" || true)"
  if [ -n "$CID" ]; then
    echo "[ok] card existe '$title' id=$CID" >&2
    printf '%s\n' "$CID"
    return 0
  fi

  payload=$(cat <<JSON
{
  "name": "$(jescape "$title")",
  "dataset_query": {
    "type": "native",
    "native": { "query": "$(jescape "$sql")" },
    "database": $DB_ID
  },
  "display": "table",
  "collection_id": null,
  "visualization_settings": {}
}
JSON
)
  curl_json_auth POST "/api/card" "$SESSION_ID" "$payload"
  code=$(cat "$RESP_CODE")
  if [ "$code" = "200" ] || [ "$code" = "201" ]; then
    ensure_json_or_die "$RESP_BODY" "/api/card POST"
    CID="$(get_json_value "$RESP_BODY" 'id')"
    [ -z "$CID" ] && die "No se obtuvo card id tras crear '$title'"
    echo "[ok] card creada '$title' id=$CID" >&2
    printf '%s\n' "$CID"
    return 0
  fi

  echo "[warn] crear card '$title' code=$code" >&2
  cat "$RESP_BODY" >&2
  CID="$(find_card_by_name "$title" || true)"
  [ -n "$CID" ] && { echo "[ok] card ya existia '$title' id=$CID" >&2; printf '%s\n' "$CID"; return 0; }
  die "crear card fallo para '$title'"
}

# Dashboard: buscar por nombre. Imprime ID o vacio.
find_dashboard_by_name() {
  title="$1"
  q="$(urlencode "$title")"
  curl_json_auth GET "/api/search?q=$q&type=dashboard&archived=false" "$SESSION_ID"
  code=$(cat "$RESP_CODE")
  if [ "$code" != "200" ]; then
    echo "[warn] /api/search (dashboard) code=$code" >&2
    cat "$RESP_BODY" >&2
    echo "" >&2
    return 0
  fi
  ensure_json_or_die "$RESP_BODY" "/api/search (dashboard)"
  python3 - "$RESP_BODY" "$title" <<'PY' || true
import sys, json
fn, want = sys.argv[1], sys.argv[2]
try:
    arr = json.loads(open(fn,'r',encoding='utf-8').read())
    for it in arr:
        if isinstance(it, dict) and it.get('model')=='dashboard' and it.get('name')==want:
            print(it.get('id',''))
            break
except Exception:
    pass
PY
}

# Crea dashboard. Imprime ID.
create_dashboard() {
  title="$1"
  payload='{ "name": "'"$(jescape "$title")"'" }'
  curl_json_auth POST "/api/dashboard" "$SESSION_ID" "$payload"
  code=$(cat "$RESP_CODE")
  [ "$code" = "200" ] || [ "$code" = "201" ] || { echo "Respuesta /api/dashboard code=$code:" >&2; cat "$RESP_BODY" >&2; die "crear dashboard fallo"; }
  ensure_json_or_die "$RESP_BODY" "/api/dashboard POST"
  get_json_value "$RESP_BODY" 'id'
}

# Devuelve 0 si el dashboard ya contiene la card, 1 si no.
dashboard_has_card() {
  dash_id="$1"; card_id="$2"
  curl_json_auth GET "/api/dashboard/$dash_id" "$SESSION_ID"
  code=$(cat "$RESP_CODE")
  [ "$code" = "200" ] || { echo "Respuesta /api/dashboard/$dash_id code=$code:" >&2; cat "$RESP_BODY" >&2; die "leer dashboard fallo"; }
  ensure_json_or_die "$RESP_BODY" "/api/dashboard GET"
  python3 - "$RESP_BODY" "$card_id" <<'PY'
import sys, json
fn, cid = sys.argv[1], int(sys.argv[2])
obj = json.loads(open(fn,'r',encoding='utf-8').read())
cards = obj.get('ordered_cards') or obj.get('dashcards') or []
print(any(isinstance(dc, dict) and dc.get('card_id') == cid for dc in cards))
PY
}

# Agrega una card con PUT /api/dashboard/:id/cards (idempotente)
add_card_to_dashboard() {
  dash_id="$1"; card_id="$2"; x="$3"; y="$4"; w="$5"; h="$6"

  if [ "$(dashboard_has_card "$dash_id" "$card_id")" = "True" ]; then
    echo "[ok] dashboard $dash_id ya contiene card $card_id" >&2
    return 0
  fi

  payload=$(cat <<JSON
{
  "ordered_tabs": [],
  "cards": [
    {
      "id": -1,
      "card_id": $card_id,
      "row": $y,
      "col": $x,
      "size_x": $w,
      "size_y": $h,
      "series": [],
      "parameter_mappings": [],
      "visualization_settings": {}
    }
  ]
}
JSON
)
  curl_json_auth PUT "/api/dashboard/$dash_id/cards" "$SESSION_ID" "$payload"
  code=$(cat "$RESP_CODE")
  [ "$code" = "200" ] || { echo "Respuesta /api/dashboard/$dash_id/cards code=$code:" >&2; cat "$RESP_BODY" >&2; die "agregar card al dashboard fallo"; }
  echo "[ok] card $card_id agregada al dashboard $dash_id" >&2
}

# ---- Definicion de consultas SQL (MySQL) -
