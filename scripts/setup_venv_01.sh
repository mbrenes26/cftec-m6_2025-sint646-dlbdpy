#!/usr/bin/env bash
# setup_venv_01.sh
# Crea y prepara un entorno virtual de Python e instala dependencias.

set -euo pipefail

VENV_DIR=".venv"
PYBIN=""                 # python a usar; autodetecta si se deja vacio
REQ_FILE=""             # ruta a requirements.txt (opcional)
PKGS_DEFAULT="kafka-python requests datasets pyarrow"
PKGS=""                 # lista de paquetes a instalar si no se usa -r

usage() {
  cat <<'USAGE'
Usage: setup_venv_01.sh [options]
  -v, --venv DIR          Directorio del virtualenv (default: .venv)
  -p, --python BIN        Binario de Python (default: autodetecta py -3, python3 o python)
  -r, --requirements FILE Instalar desde requirements.txt
      --pkgs "A B C"      Paquetes a instalar (si no se usa -r).
                          Default: kafka-python requests datasets pyarrow
  -h, --help              Mostrar ayuda

Ejemplos:
  bash scripts/setup_venv_01.sh
  bash scripts/setup_venv_01.sh -r requirements.txt
  bash scripts/setup_venv_01.sh --venv .venv --python "py -3" --pkgs "kafka-python requests datasets"
USAGE
}

# Parseo de argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--venv) VENV_DIR="$2"; shift 2 ;;
    -p|--python) PYBIN="$2"; shift 2 ;;
    -r|--requirements) REQ_FILE="$2"; shift 2 ;;
    --pkgs) PKGS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opcion desconocida: $1"; usage; exit 1 ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }
py_works() {
  # Verifica que el candidato ejecute Python >= 3.8 y no sea el stub de WindowsApps
  local cmd="$1"
  # shellcheck disable=SC2086
  $cmd - <<'PY' >/dev/null 2>&1 || return 1
import sys
maj, min = sys.version_info[:2]
assert maj == 3 and min >= 8
PY
}

pick_python() {
  # Orden de prueba: py -3 (Windows), python3, python
  local candidates=()
  if have py; then candidates+=("py -3"); fi
  if have python3; then candidates+=("python3"); fi
  if have python; then candidates+=("python"); fi
  for c in "${candidates[@]}"; do
    if py_works "$c"; then echo "$c"; return 0; fi
  done
  return 1
}

# Autodetectar Python si no se paso
if [[ -z "$PYBIN" ]]; then
  if ! PYBIN="$(pick_python)"; then
    echo "ERROR: no se encontro un Python 3 valido (py -3 / python3 / python). Instala Python 3.x y reintenta." >&2
    exit 1
  fi
fi

echo "==> Python: $PYBIN"
echo "==> Venv:   $VENV_DIR"

# Crear venv si no existe
if [[ ! -d "$VENV_DIR" ]]; then
  echo "==> Creando entorno virtual..."
  # shellcheck disable=SC2086
  $PYBIN -m venv "$VENV_DIR"
else
  echo "==> Reutilizando entorno virtual existente."
fi

# Activar venv (Linux/macOS y Git Bash/WSL en Windows)
if [[ -f "$VENV_DIR/bin/activate" ]]; then
  # shellcheck disable=SC1090
  source "$VENV_DIR/bin/activate"
elif [[ -f "$VENV_DIR/Scripts/activate" ]]; then
  # shellcheck disable=SC1090
  source "$VENV_DIR/Scripts/activate"
else
  echo "ERROR: no se encontro script de activacion en '$VENV_DIR/bin/activate' ni '$VENV_DIR/Scripts/activate'." >&2
  exit 1
fi

# Asegurar pip actualizado y toolchain basico
echo "==> Actualizando pip/setuptools/wheel..."
python -m pip install -U pip setuptools wheel

# Instalar dependencias
if [[ -n "$REQ_FILE" ]]; then
  if [[ ! -f "$REQ_FILE" ]]; then
    echo "ERROR: no existe el archivo de requirements: $REQ_FILE" >&2
    exit 1
  fi
  echo "==> Instalando dependencias desde $REQ_FILE ..."
  python -m pip install -r "$REQ_FILE"
else
  LISTA="${PKGS:-$PKGS_DEFAULT}"
  echo "==> Instalando paquetes: $LISTA"
  # shellcheck disable=SC2086
  python -m pip install $LISTA
fi

echo
echo "Listo."
echo "Para activar el entorno en esta terminal:"
if [[ -f "$VENV_DIR/bin/activate" ]]; then
  echo "  source $VENV_DIR/bin/activate"
else
  echo "  source $VENV_DIR/Scripts/activate"
fi
echo "Para desactivar:"
echo "  deactivate"
