#!/usr/bin/env bash
# scripts/install_lab_prereqs.sh
# Prepara la VM para que restart_lab_services.sh funcione sin cambios.
# - tmux, python3, python3-pip, sudo
# - Docker Engine (habilitado)
# - Jupyter Notebook 6.x para APP_USER (pip --user)
# - PATH: $HOME/.local/bin en shells de login y no-login
# - Pre-pull de imagenes EXACTAMENTE como las usa restart_lab_services.sh
#
# Uso:
#   sudo bash scripts/install_lab_prereqs.sh <APP_USER>
#     APP_USER: usuario no root que usara tmux/jupyter (default: azureuser)

set -Eeuo pipefail

APP_USER="${1:-azureuser}"

log(){ echo "[$(date +'%F %T')] $*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

# Validaciones basicas
id "$APP_USER" >/dev/null 2>&1 || die "El usuario ${APP_USER} no existe."

# Detectar gestor de paquetes
PKG=""
if   have apt-get; then PKG="apt"
elif have dnf;     then PKG="dnf"
elif have yum;     then PKG="yum"
else die "No se detecto apt/dnf/yum."
fi

pkg_update(){
  case "$PKG" in
    apt) export DEBIAN_FRONTEND=noninteractive; apt-get update -y -qq ;;
    dnf) dnf -y -q makecache ;;
    yum) yum -y -q makecache ;;
  esac
}
pkg_install(){
  case "$PKG" in
    apt) apt-get install -y -qq "$@" ;;
    dnf) dnf install -y -q "$@" ;;
    yum) yum install -y -q "$@" ;;
  esac
}
enable_service(){
  systemctl enable "$1" >/dev/null 2>&1 || true
  systemctl start "$1"  >/dev/null 2>&1 || true
}

as_user(){ su - "$APP_USER" -c "$*"; }

# 1) Paquetes base (incluye sudo porque restart usa sudo -u)
log "Instalando paquetes base..."
pkg_update
case "$PKG" in
  apt) pkg_install sudo tmux python3 python3-pip ca-certificates curl ;;
  dnf|yum) pkg_install sudo tmux python3 python3-pip ca-certificates curl ;;
esac

# 2) Docker Engine (requerido por restart)
if ! have docker; then
  log "Instalando Docker Engine..."
  case "$PKG" in
    apt)
      pkg_install docker.io docker-compose-plugin
      ;;
    dnf|yum)
      have curl || pkg_install curl
      curl -fsSL https://get.docker.com | sh
      ;;
  esac
  enable_service docker
  # No es necesario para Run Command, pero util para sesiones del usuario
  getent group docker >/dev/null 2>&1 && usermod -aG docker "$APP_USER" || true
else
  log "Docker ya instalado."
fi

# 3) Asegurar PATH global para $HOME/.local/bin (shells no-login)
if [ ! -f /etc/profile.d/10-localbin.sh ]; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' > /etc/profile.d/10-localbin.sh
  chmod 644 /etc/profile.d/10-localbin.sh
fi

# 4) Jupyter Notebook 6.x para APP_USER (compat con --NotebookApp.*)
log "Instalando Jupyter Notebook 6.x para ${APP_USER}..."
as_user "python3 -m pip install --user --upgrade pip"
as_user "python3 -m pip install --user 'notebook<7'"

# Asegurar PATH en shells de login del usuario
USR_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
BASHRC="${USR_HOME}/.bashrc"
PROFILE="${USR_HOME}/.profile"
grep -q 'export PATH=\$HOME/.local/bin:\$PATH' "$BASHRC" 2>/dev/null || \
  echo 'export PATH=$HOME/.local/bin:$PATH' >> "$BASHRC"
grep -q 'export PATH=\$HOME/.local/bin:\$PATH' "$PROFILE" 2>/dev/null || \
  echo 'export PATH=$HOME/.local/bin:$PATH' >> "$PROFILE"

# 5) Verificacion en contexto del usuario
log "Verificando jupyter para ${APP_USER}..."
as_user 'command -v jupyter >/dev/null || (echo "jupyter no esta en PATH" && exit 1)'
as_user 'jupyter --version || true'
as_user "python3 - <<'PY'
import notebook
maj = notebook.__version__.split('.')[0]
assert maj == '6', f'Se requiere notebook 6.x; encontrado {notebook.__version__}'
print('OK notebook', notebook.__version__)
PY"

# 6) Verificacion de Docker y pre-pull de imagenes EXACTAS del restart
log "Verificando docker..."
docker version >/dev/null 2>&1 || die "Docker no responde."

log "Descargando imagenes Docker usadas por restart_lab_services.sh..."
IMAGES=(
  "mongo:6.0"
  "mongo-express:latest"
  "redis:7.2"
  "redislabs/redisinsight:1.14.0"
  "harisekhon/hbase:latest"
)
for img in "${IMAGES[@]}"; do
  log "docker pull $img"
  docker pull "$img" >/dev/null || die "Fallo pull de $img"
done

log "Instalacion finalizada con exito."
log "Prerequisitos listos para ejecutar restart_lab_services.sh sin cambios."
