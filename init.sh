#!/bin/bash

set -euo pipefail
set -x

LOGFILE=/tmp/genesys_install.log
exec > >(tee -a "$LOGFILE") 2>&1

USER_NAME=$(whoami)

DESKTOP_APP_DIR="$HOME/.local/share/applications/"
REPO_URL=https://github.com/rlcancian/Genesys-Simulator.git
REPO_DIR="$HOME/Documents"

# endereco dos releases
USER_VERSION_FILE="$HOME/.genesys_user_version"

LATEST_RELEASE_API="https://api.github.com/repos/joaomeloo/Genesys-Simulator/releases/latest"

USER_RELEASE_DOWNLOAD_URL="https://github.com/joaomeloo/Genesys-Simulator/releases/latest/download/genesys-linux.tar.gz"

# branch do executável do usuário
USER_BRANCH="master"

# arquivo de preferência do desenvolvedor
DEV_BRANCH_FILE="$HOME/.genesys_dev_branch"

# default para dev nutella
DEFAULT_DEV_BRANCH="currentStable"

# escolha do branch do desenvolvedor
if [ ! -f "$DEV_BRANCH_FILE" ]; then

    CHOICE=$(gxmessage -center -buttons \
        "currentStable:0,WorkInProgress:1" \
        -print \
        $'Escolha qual branch deseja seguir para desenvolvimento.\n\nEssa configuração ficará salva em:\n'"$DEV_BRANCH_FILE")

    if [ "$CHOICE" = "Raiz" ]; then
        echo "WorkInProgress" > "$DEV_BRANCH_FILE"
    else
        echo "$DEFAULT_DEV_BRANCH" > "$DEV_BRANCH_FILE"
    fi

    gxmessage $'Branch salvo em:\n'"$DEV_BRANCH_FILE"
fi

DEV_BRANCH=$(cat "$DEV_BRANCH_FILE")

# Diretórios separados
USER_REPO_PATH="$REPO_DIR/Genesys-User"
DEV_REPO_PATH="$REPO_DIR/Genesys-Dev"

# Executavel do Genesys QT GUI
GENESYS_GUI_APP_DISPLAY_NAME=GenESySQt
GENESYS_GUI_APP_EXEC=genesys_qt_gui_application

BUILD_GENESYS_GUI_APP_PATH="$USER_REPO_PATH/build/gui-app/source/applications/gui/qt/GenesysQtGUI/$GENESYS_GUI_APP_EXEC"

GENESYS_WEB_APP_EXEC="genesys_web_app"
BUILD_GENESYS_WEB_APP_PATH="$USER_REPO_PATH/build/web-app/source/applications/web/$GENESYS_WEB_APP_EXEC"

ICON_NAME=genesysico.gif
PROJECT_ICON_PATH="$USER_REPO_PATH/source/applications/gui/qt/GenesysQtGUI/resources/icons/$ICON_NAME"

INSTALL_DIR="$HOME/.local/bin/"
mkdir -p "$INSTALL_DIR"

ICON_DIR="$HOME/.local/share/icons/"
mkdir -p "$ICON_DIR"

until getent hosts github.com >/dev/null 2>&1; do
  sleep 1
done

mkdir -p "$REPO_DIR"

FIRST_INSTALL=0

# =========================
# REPOSITÓRIO DO USUÁRIO
# =========================
cd "$REPO_DIR"

if [ ! -d "$USER_REPO_PATH" ]; then
    gxmessage -buttons "" -timeout 9999 "Clonando versão de usuário (main)..." &
    PID=$!

    git clone -b "$USER_BRANCH" "$REPO_URL" "$USER_REPO_PATH"

    kill $PID 2>/dev/null || true
    FIRST_INSTALL=1
fi

# =========================
# REPOSITÓRIO DEV
# =========================
if [ ! -d "$DEV_REPO_PATH" ]; then
    gxmessage -buttons "" -timeout 9999 "Clonando versão de desenvolvimento ($DEV_BRANCH)..." &
    PID=$!

    git clone -b "$DEV_BRANCH" "$REPO_URL" "$DEV_REPO_PATH"

    kill $PID 2>/dev/null || true
fi

# atualiza branch dev silenciosamente
cd "$DEV_REPO_PATH"
git fetch origin || true
git checkout "$DEV_BRANCH" || true
git pull origin "$DEV_BRANCH" || true

# =========================
# USER VIA GITHUB RELEASES
# =========================

INSTALLED_VERSION=$(cat "$USER_VERSION_FILE" 2>/dev/null || echo "none")

LATEST_VERSION=$(curl -s "$LATEST_RELEASE_API" \
    | grep '"tag_name"' \
    | cut -d '"' -f4)

if [[ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]]; then

    gxmessage -buttons "" -timeout 9999 \
        $'Baixando nova versão do GenESyS...\n\nVersão: '"$LATEST_VERSION" &
    PID=$!

    TMP_DIR=$(mktemp -d)

    curl -L "$USER_RELEASE_DOWNLOAD_URL" \
        -o "$TMP_DIR/genesys-linux.tar.gz"

    tar -xzf "$TMP_DIR/genesys-linux.tar.gz" -C "$TMP_DIR"

    cp -a "$TMP_DIR/$GENESYS_GUI_APP_EXEC" "$INSTALL_DIR"
    cp -a "$TMP_DIR/$GENESYS_WEB_APP_EXEC" "$INSTALL_DIR"
    cp -a "$TMP_DIR/$ICON_NAME" "$ICON_DIR"

    chmod +x "$INSTALL_DIR/$GENESYS_GUI_APP_EXEC"
    chmod +x "$INSTALL_DIR/$GENESYS_WEB_APP_EXEC"

    mkdir -p "$DESKTOP_APP_DIR"

    printf '%s\n' \
        "[Desktop Entry]" \
        "Name=$GENESYS_GUI_APP_DISPLAY_NAME" \
        "Exec=$INSTALL_DIR/$GENESYS_GUI_APP_EXEC" \
        "Icon=$ICON_DIR/$ICON_NAME" \
        "Type=Application" \
        "Terminal=false" \
        "Categories=Development;" \
        > "${DESKTOP_APP_DIR}${GENESYS_GUI_APP_DISPLAY_NAME}.desktop"

    USER_SERVICE_DIR="$HOME/.config/systemd/user"
    mkdir -p "$USER_SERVICE_DIR"

    printf '[Unit]\nDescription=GenESyS Web Server\nAfter=network.target\n\n[Service]\nExecStart=%s/%s\nWorkingDirectory=%s\nRestart=always\n\n[Install]\nWantedBy=default.target\n' \
        "$INSTALL_DIR" \
        "$GENESYS_WEB_APP_EXEC" \
        "$INSTALL_DIR" \
        > "$USER_SERVICE_DIR/genesys-web.service"

    systemctl --user daemon-reload
    systemctl --user enable genesys-web.service
    systemctl --user restart genesys-web.service

    echo "$LATEST_VERSION" > "$USER_VERSION_FILE"

    rm -rf "$TMP_DIR"

    kill $PID 2>/dev/null || true
fi

# =========================
# NOTIFICAÇÃO PARA DEV
# =========================
cd "$DEV_REPO_PATH"

git fetch origin

LOCAL_DEV=$(git rev-parse HEAD)
REMOTE_DEV=$(git rev-parse origin/$DEV_BRANCH)

if [[ "$LOCAL_DEV" != "$REMOTE_DEV" ]]; then

    if gxmessage -buttons "Sim:0,Não:1" \
             -default Sim \
             $'Há uma nova versão disponível para desenvolvedores.\nSeu GenESyS será atualizado. Atualizar?'; then

        gxmessage -buttons "" -timeout 9999 "Atualizando ambiente de desenvolvimento..." &
        PID=$!

        git pull origin "$DEV_BRANCH"

        kill $PID 2>/dev/null || true
    fi
fi
