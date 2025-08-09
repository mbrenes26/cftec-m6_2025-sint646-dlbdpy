#!/bin/bash
# ==========================================================
# Script: start_tmux-jupyterlab.sh
# Descripción: Inicia JupyterLab en una sesión tmux persistente
# Autor: [Tu Nombre]
# ==========================================================

# Nombre de la sesión tmux
SESSION_NAME="jupyterlab"

# Puerto donde correrá JupyterLab
PORT=8888

# Función para verificar si tmux está instalado
check_tmux() {
    if ! command -v tmux &> /dev/null; then
        echo "❌ tmux no está instalado. Instálalo con:"
        echo "   sudo apt update && sudo apt install tmux -y"
        exit 1
    fi
}

# Verificar tmux
check_tmux

# Crear nueva sesión solo si no existe
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "⚠️ La sesión '$SESSION_NAME' ya está en ejecución."
    echo "Para adjuntarte: tmux attach -t $SESSION_NAME"
else
    echo "🚀 Iniciando sesión tmux '$SESSION_NAME' con JupyterLab..."
    tmux new-session -d -s "$SESSION_NAME" \
        "jupyter lab --ip=0.0.0.0 --port=$PORT --no-browser --NotebookApp.token='' --NotebookApp.password=''"
    echo "✅ JupyterLab iniciado en puerto $PORT dentro de tmux."
    echo "Para adjuntarte: tmux attach -t $SESSION_NAME"
fi
