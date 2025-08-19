#!/usr/bin/env bash
# scripts/install_ml_deps.sh
# Instala dependencias ML para el pipeline DL en el usuario no root.
# Uso:
#   sudo bash scripts/install_ml_deps.sh <APP_USER>
# Ejemplo:
#   sudo bash scripts/install_ml_deps.sh azureuser

set -Eeuo pipefail

APP_USER="${1:-azureuser}"

log(){ echo "[$(date +'%F %T')] $*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }

# Validaciones
id "$APP_USER" >/dev/null 2>&1 || die "Usuario $APP_USER no existe"

USER_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"

log "Asegurando PATH de $APP_USER (~/.local/bin)"
grep -q '\.local/bin' "$USER_HOME/.profile" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.profile"
grep -q '\.local/bin' "$USER_HOME/.bashrc" 2>/dev/null   || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.bashrc"
chown "$APP_USER:$APP_USER" "$USER_HOME/.profile" "$USER_HOME/.bashrc"

log "Actualizando pip"
su - "$APP_USER" -c 'python3 -m pip install --user --upgrade pip'

PKGS=( torch transformers pymongo mysql-connector-python )

log "Instalando paquetes: ${PKGS[*]}"
su - "$APP_USER" -c "python3 -m pip install --user ${PKGS[*]}"

log "Versiones instaladas:"
su - "$APP_USER" -c 'python3 -V && python3 -m pip -V'
su - "$APP_USER" -c 'python3 -m pip show torch transformers pymongo mysql-connector-python | egrep "Name:|Version:" || true'

log "Listo."
