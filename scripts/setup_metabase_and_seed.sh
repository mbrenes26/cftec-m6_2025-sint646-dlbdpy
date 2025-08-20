--- a/scripts/setup_metabase_and_seed.sh
+++ b/scripts/setup_metabase_and_seed.sh
@@ -94,27 +94,54 @@
 curl_json GET "/api/session/properties"
-# puede ser JSON o vacio si algo raro; verifico cuando lo necesite
-SETUP_TOKEN="$(get_json_value "$RESP_BODY" 'setup_token')"
-[ -z "$SETUP_TOKEN" ] && SETUP_TOKEN="$(get_json_value "$RESP_BODY" 'setup-token' || true)"
-
-SESSION_ID=""
-
-if [ -n "$SETUP_TOKEN" ]; then
-  # Requiere setup
-  echo "[info] instancia sin configurar; realizando /api/setup"
-  FN="$(jescape "$ADMIN_NAME")"
-  EM="$(jescape "$ADMIN_EMAIL")"
-  PW="$(jescape "$ADMIN_PASS")"
-  SN="$(jescape 'Lab')"
-  TK="$(jescape "$SETUP_TOKEN")"
-
-  payload='{"token":"'"$TK"'","user":{"first_name":"'"$FN"'","last_name":"Admin","email":"'"$EM"'","password":"'"$PW"'"}, "prefs":{"site_name":"'"$SN"'"}}'
-
-  curl_json POST "/api/setup" "$payload"
-  code=$(cat "$RESP_CODE")
-  [ "$code" = "200" ] || { echo "Respuesta /api/setup (code=$code):"; cat "$RESP_BODY"; die "/api/setup fallo"; }
-  ensure_json_or_die "$RESP_BODY" "/api/setup"
-  SESSION_ID="$(get_json_value "$RESP_BODY" 'id')"
-  [ -z "$SESSION_ID" ] && die "No se obtuvo session id tras /api/setup"
-  echo "[ok] setup completado; session=$SESSION_ID"
-else
-  # Ya configurado -> login
-  echo "[info] instancia ya configurada; realizando login /api/session"
-  EM="$(jescape "$ADMIN_EMAIL")"
-  PW="$(jescape "$ADMIN_PASS")"
-  payload='{"username":"'"$EM"'","password":"'"$PW"'"}'
-  curl_json POST "/api/session" "$payload"
-  code=$(cat "$RESP_CODE")
-  [ "$code" = "200" ] || { echo "Respuesta /api/session (code=$code):"; cat "$RESP_BODY"; die "login fallo"; }
-  ensure_json_or_die "$RESP_BODY" "/api/session"
-  SESSION_ID="$(get_json_value "$RESP_BODY" 'id')"
-  [ -z "$SESSION_ID" ] && die "No se obtuvo session id tras /api/session"
-  echo "[ok] login; session=$SESSION_ID"
-fi
+# Puede ser JSON o vacio; obtengo indicadores de estado
+SETUP_TOKEN="$(get_json_value "$RESP_BODY" 'setup_token')"
+[ -z "$SETUP_TOKEN" ] && SETUP_TOKEN="$(get_json_value "$RESP_BODY" 'setup-token' || true)"
+HAS_USER_SETUP="$(get_json_value "$RESP_BODY" 'has_user_setup')"
+[ -z "$HAS_USER_SETUP" ] && HAS_USER_SETUP="$(get_json_value "$RESP_BODY" 'has-user-setup' || true)"
+
+SESSION_ID=""
+
+if [ "$HAS_USER_SETUP" = "true" ]; then
+  # Ya configurado -> login
+  echo "[info] instancia ya configurada; realizando login /api/session"
+  EM="$(jescape "$ADMIN_EMAIL")"
+  PW="$(jescape "$ADMIN_PASS")"
+  payload='{"username":"'"$EM"'","password":"'"$PW"'"}'
+  curl_json POST "/api/session" "$payload"
+  code=$(cat "$RESP_CODE")
+  [ "$code" = "200" ] || { echo "Respuesta /api/session (code=$code):"; cat "$RESP_BODY"; die "login fallo"; }
+  ensure_json_or_die "$RESP_BODY" "/api/session"
+  SESSION_ID="$(get_json_value "$RESP_BODY" 'id')"
+  [ -z "$SESSION_ID" ] && die "No se obtuvo session id tras /api/session"
+  echo "[ok] login; session=$SESSION_ID"
+else
+  # No configurado segun properties -> intento /api/setup (siempre que haya token)
+  if [ -z "$SETUP_TOKEN" ]; then
+    echo "[warn] no hay setup-token pero properties indica instancia no configurada; probare login por si ya existe usuario"
+    EM="$(jescape "$ADMIN_EMAIL")"
+    PW="$(jescape "$ADMIN_PASS")"
+    payload='{"username":"'"$EM"'","password":"'"$PW"'"}'
+    curl_json POST "/api/session" "$payload"
+    code=$(cat "$RESP_CODE")
+    [ "$code" = "200" ] || { echo "Respuesta /api/session (code=$code):"; cat "$RESP_BODY"; die "no se pudo ni setup ni login"; }
+    ensure_json_or_die "$RESP_BODY" "/api/session"
+    SESSION_ID="$(get_json_value "$RESP_BODY" 'id')"
+    [ -z "$SESSION_ID" ] && die "No se obtuvo session id tras /api/session"
+    echo "[ok] login; session=$SESSION_ID"
+  else
+    echo "[info] instancia sin configurar; realizando /api/setup"
+    FN="$(jescape "$ADMIN_NAME")"
+    EM="$(jescape "$ADMIN_EMAIL")"
+    PW="$(jescape "$ADMIN_PASS")"
+    SN="$(jescape 'Lab')"
+    TK="$(jescape "$SETUP_TOKEN")"
+    payload='{"token":"'"$TK"'","user":{"first_name":"'"$FN"'","last_name":"Admin","email":"'"$EM"'","password":"'"$PW"'"}, "prefs":{"site_name":"'"$SN"'"}}'
+    curl_json POST "/api/setup" "$payload"
+    code=$(cat "$RESP_CODE")
+    if [ "$code" = "403" ]; then
+      echo "[info] /api/setup devolvio 403; parece que ya existe un usuario. Intentando login."
+      EM="$(jescape "$ADMIN_EMAIL")"
+      PW="$(jescape "$ADMIN_PASS")"
+      payload='{"username":"'"$EM"'","password":"'"$PW"'"}'
+      curl_json POST "/api/session" "$payload"
+      code=$(cat "$RESP_CODE")
+      [ "$code" = "200" ] || { echo "Respuesta /api/session (code=$code):"; cat "$RESP_BODY"; die "login fallo tras 403 de setup"; }
+      ensure_json_or_die "$RESP_BODY" "/api/session"
+      SESSION_ID="$(get_json_value "$RESP_BODY" 'id')"
+      [ -z "$SESSION_ID" ] && die "No se obtuvo session id tras /api/session"
+      echo "[ok] login; session=$SESSION_ID"
+    else
+      [ "$code" = "200" ] || { echo "Respuesta /api/setup (code=$code):"; cat "$RESP_BODY"; die "/api/setup fallo"; }
+      ensure_json_or_die "$RESP_BODY" "/api/setup"
+      # Hago login explicito para obtener un session id fiable
+      EM="$(jescape "$ADMIN_EMAIL")"
+      PW="$(jescape "$ADMIN_PASS")"
+      payload='{"username":"'"$EM"'","password":"'"$PW"'"}'
+      curl_json POST "/api/session" "$payload"
+      code=$(cat "$RESP_CODE")
+      [ "$code" = "200" ] || { echo "Respuesta /api/session (code=$code):"; cat "$RESP_BODY"; die "login fallo tras setup"; }
+      ensure_json_or_die "$RESP_BODY" "/api/session"
+      SESSION_ID="$(get_json_value "$RESP_BODY" 'id')"
+      [ -z "$SESSION_ID" ] && die "No se obtuvo session id tras /api/session"
+      echo "[ok] setup completado y login; session=$SESSION_ID"
+    fi
+  fi
+fi
@@ -141,15 +168,23 @@
-# buscar por nombre
-DB_ID="$(python3 - "$RESP_BODY" "$DB_DISPLAY" <<'PY' || true
+# buscar por nombre (soporta respuesta como lista o como objeto con .data)
+DB_ID="$(python3 - "$RESP_BODY" "$DB_DISPLAY" <<'PY' || true
 import sys, json
 fn, name = sys.argv[1], sys.argv[2]
 try:
-    arr=json.loads(open(fn,'r',encoding='utf-8').read())
+    obj=json.loads(open(fn,'r',encoding='utf-8').read())
+    if isinstance(obj, list):
+        arr = obj
+    elif isinstance(obj, dict):
+        arr = obj.get('data', [])
+    else:
+        arr = []
     for d in arr:
         if isinstance(d, dict) and d.get('name')==name:
             print(d.get('id',''))
             break
 except Exception:
     pass
 PY
 )"
@@ -177,6 +212,13 @@
   ensure_json_or_die "$RESP_BODY" "/api/database POST"
   DB_ID="$(get_json_value "$RESP_BODY" 'id')"
   [ -z "$DB_ID" ] && die "No se obtuvo DB_ID tras crear DB"
+  # opcional: lanzar sincronizacion de esquema
+  curl_json_auth POST "/api/database/$DB_ID/sync_schema" "$SESSION_ID" '{}'
+  sc_code=$(cat "$RESP_CODE")
+  if [ "$sc_code" = "200" ] || [ "$sc_code" = "202" ]; then
+    echo "[ok] sync_schema disparado para DB id=$DB_ID"
+  else
+    echo "[warn] sync_schema code=$sc_code (continuo)"
   else
   echo "[ok] DB ya existe id=$DB_ID"
 fi
