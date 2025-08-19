#!/usr/bin/env bash
# scripts/install_jupyter_widgets.sh
# Instala/activa ipywidgets para Jupyter (Notebook 6.x) de forma idempotente.
# Uso:
#   sudo bash scripts/install_jupyter_widgets.sh <APP_USER>
# Ejemplo:
#   sudo bash scripts/install_jupyter_widgets.sh azureuser

set -Eeuo pipefail

APP_USER="${1:-azureuser}"

log(){ echo "[$(date +'%F %T')] $*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }
as_user(){ su - "$APP_USER" -c "$*"; }

id "$APP_USER" >/dev/null 2>&1 || die "Usuario $APP_USER no existe"

# Asegurar PATH para binarios --user
USER_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"
grep -q '\.local/bin' "$USER_HOME/.profile" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.profile"
grep -q '\.local/bin' "$USER_HOME/.bashrc" 2>/dev/null   || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.bashrc"
chown "$APP_USER:$APP_USER" "$USER_HOME/.profile" "$USER_HOME/.bashrc"

# Asegurar Jupyter Notebook 6.x (compatible con widgetsnbextension)
if ! as_user 'command -v jupyter >/dev/null 2>&1'; then
  log "Instalando Jupyter Notebook (6.x)"
  as_user 'python3 -m pip install --user "notebook<7"'
fi

# Instalar ipywidgets 8.x y widgetsnbextension 4.x (idempotente)
log "Instalando/actualizando ipywidgets y widgetsnbextension"
as_user 'python3 -m pip install --user --upgrade "ipywidgets>=8,<9" "widgetsnbextension>=4,<5" tqdm'

# Habilitar la extension de widgets para Notebook clasico
log "Habilitando widgetsnbextension para el usuario"
as_user 'jupyter nbextension enable --py widgetsnbextension --user || true'

# Mostrar estado
log "Versiones instaladas:"
as_user 'python3 -m pip show ipywidgets widgetsnbextension | egrep "Name:|Version:" || true'
log "nbextensions registradas:"
as_user 'jupyter nbextension list || true'

log "Prueba rapida de import"
as_user "python3 - <<'PY'
from tqdm.auto import tqdm
import ipywidgets
print('ok: ipywidgets', ipywidgets.__version__, 'tqdm', tqdm.__module__)
PY"
log "Listo."
