#!/usr/bin/env bash
# scripts/install_ml_deps.sh
# Proposito: instalar de forma IDEMPOTENTE las dependencias ML para el pipeline
#            en el usuario no root indicado.
#
# Uso:
#   sudo bash scripts/install_ml_deps.sh [--upgrade] [--app-user <usuario>]
# Ejemplos:
#   sudo bash scripts/install_ml_deps.sh
#   sudo bash scripts/install_ml_deps.sh --app-user azureuser
#   sudo bash scripts/install_ml_deps.sh --upgrade
#
# Comportamiento:
#   - Asegura que ~/.local/bin este en PATH del usuario
#   - Asegura pip en el usuario y lo actualiza
#   - Instala solo paquetes faltantes; si usa --upgrade, fuerza actualizacion
#   - Re-ejecutable sin efectos adversos (idempotente)

set -Eeuo pipefail

APP_USER="azureuser"
FORCE_UPGRADE="0"

log(){ echo "[$(date +'%F %T')] $*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }
as_user(){ su - "$APP_USER" -c "$*"; }

# Parseo simple de argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-user)
      [[ $# -ge 2 ]] || die "Falta valor para --app-user"
      APP_USER="$2"; shift 2 ;;
    --upgrade)
      FORCE_UPGRADE="1"; shift ;;
    *)
      # Permitir posicionar solo el usuario: scripts/install_ml_deps.sh <usuario>
      if [[ "$1" != "" && "$1" != -* ]]; then APP_USER="$1"; shift; else die "Argumento no reconocido: $1"; fi
      ;;
  esac
done

# Validaciones
id "$APP_USER" >/dev/null 2>&1 || die "El usuario $APP_USER no existe"
command -v python3 >/dev/null 2>&1 || die "python3 no encontrado en el sistema"

USER_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"

log "Configurando PATH persistente para $APP_USER"
ensure_line(){ local file="$1" line="$2"; grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"; }
ensure_line "$USER_HOME/.profile" 'export PATH="$HOME/.local/bin:$PATH"'
ensure_line "$USER_HOME/.bashrc"  'export PATH="$HOME/.local/bin:$PATH"'
chown "$APP_USER:$APP_USER" "$USER_HOME/.profile" "$USER_HOME/.bashrc"

log "Verificando pip del usuario $APP_USER"
# Asegurar pip en el contexto del usuario
if ! as_user 'python3 -m pip --version' >/dev/null 2>&1; then
  log "pip no disponible; intentando instalar con ensurepip"
  as_user 'python3 -m ensurepip --user' || true
fi

# Actualizar pip/sets/wheel (idempotente)
log "Actualizando pip, setuptools y wheel (usuario $APP_USER)"
as_user 'python3 -m pip install --user --upgrade pip setuptools wheel'
as_user 'python3 -m pip --version' >/dev/null || die "pip no quedo instalado correctamente"

# Paquetes objetivo
PKGS=( torch transformers pymongo mysql-connector-python )

install_or_skip(){
  local pkg="$1"
  if as_user "python3 -m pip show $pkg" >/dev/null 2>&1; then
    if [[ "$FORCE_UPGRADE" == "1" ]]; then
      log "Paquete $pkg ya instalado; forzando --upgrade"
      as_user "python3 -m pip install --user --upgrade $pkg"
    else
      log "Paquete $pkg ya instalado; omitiendo (usar --upgrade para actualizar)"
    fi
  else
    log "Instalando paquete faltante: $pkg"
    as_user "python3 -m pip install --user $pkg"
  fi
}

log "Instalando/verificando paquetes: ${PKGS[*]}"
for p in "${PKGS[@]}"; do
  install_or_skip "$p"
done

log "Resumen de versiones instaladas"
as_user 'python3 -V && python3 -m pip -V'
as_user 'python3 -m pip show torch transformers pymongo mysql-connector-python | egrep "Name:|Version:" || true'

log "Completado de forma idempotente."
