#!/usr/bin/env bash
# =============================================================================
# SYNOPSIS
#   Crea y activa un entorno virtual de Python (.venv) y, si existe,
#   instala requirements.txt. Funciona en Linux, macOS, WSL y Git Bash.
#
# USO
#   source ./venv-activate.sh
#
# NOTA
#   Debe ejecutarse con 'source' (o '.'). Si lo ejecutas sin 'source',
#   la activacion no persistira en tu shell actual.
# =============================================================================

set -euo pipefail

# 0) Verificar que se este usando 'source'
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: ejecuta este script con:  source ./venv-activate.sh"
  exit 1
fi

# 1) Detectar Python
PY_BIN=""
if command -v python3 >/dev/null 2>&1; then
  PY_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PY_BIN="python"
else
  echo "ERROR: Python no encontrado. Instala Python 3.x y reintenta."
  return 1
fi

# 2) Crear venv si no existe
VENV_DIR=".venv"
if [[ ! -d "${VENV_DIR}" ]]; then
  echo "Creando entorno virtual en ${VENV_DIR} ..."
  "${PY_BIN}" -m venv "${VENV_DIR}"
fi

# 3) Activar (maneja Linux/macOS y Windows Git Bash)
if [[ -f "${VENV_DIR}/bin/activate" ]]; then
  # Linux/macOS/WSL
  # shellcheck source=/dev/null
  source "${VENV_DIR}/bin/activate"
elif [[ -f "${VENV_DIR}/Scripts/activate" ]]; then
  # Windows (Git Bash)
  # shellcheck source=/dev/null
  source "${VENV_DIR}/Scripts/activate"
else
  echo "ERROR: no se encontro el script de activacion del venv."
  echo "Busca en ${VENV_DIR}/bin/activate o ${VENV_DIR}/Scripts/activate"
  return 1
fi

# 4) Actualizar pip basico
python -m pip install -U pip setuptools wheel >/dev/null

# 5) Instalar requirements.txt si existe
if [[ -f "requirements.txt" ]]; then
  echo "Instalando dependencias de requirements.txt ..."
  python -m pip install -r requirements.txt
else
  echo "Nota: no se encontro requirements.txt; puedes instalar paquetes manualmente con 'pip install ...'."
fi

# 6) Resumen
echo "Entorno activado."
echo "python: $(python --version 2>/dev/null)"
echo "pip   : $(pip --version 2>/dev/null)"
echo "ruta  : $(python -c 'import sys; print(sys.executable)')"
