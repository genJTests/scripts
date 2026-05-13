#!/bin/bash

set -euo pipefail
set -x

LOGFILE=/tmp/genesys_install.log
exec > >(tee -a "$LOGFILE") 2>&1

USER_NAME=$(whoami)

DESKTOP_APP_DIR="$HOME/.local/share/applications/"
REPO_URL=https://github.com/rlcancian/Genesys-Simulator.git
REPO_DIR="$HOME/Documents"

# branch do executável do usuário
USER_BRANCH="master"

# arquivo de preferência do desenvolvedor
DEV_BRANCH_FILE="$HOME/.genesys_dev_branch"

# default para dev nutella
DEFAULT_DEV_BRANCH="currentStable"

# escolha do branch do desenvolvedor
if [ ! -f "$DEV_BRANCH_FILE" ]; then

    CHOICE=$(gxmessage -center -buttons \
        "Nutella(currentStable):0,Raiz(WorkInProgress):1" \
        -print \
        "Escolha qual branch deseja seguir para desenvolvimento.\n\nEssa configuração ficará salva em:\n$DEV_BRANCH_FILE")

    if [ "$CHOICE" = "Raiz" ]; then
        echo "WorkInProgress" > "$DEV_BRANCH_FILE"
    else
        echo "$DEFAULT_DEV_BRANCH" > "$DEV_BRANCH_FILE"
    fi

    gxmessage "Branch salvo em:\n$DEV_BRANCH_FILE"
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
# USUÁRIO FINAL = MAIN
# =========================
cd "$USER_REPO_PATH"

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 1

git fetch origin

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/$USER_BRANCH)

if [[ "$LOCAL" != "$REMOTE" || "$FIRST_INSTALL" == 1 ]]; then

    # usuário NÃO escolhe atualizar
    gxmessage -buttons "" -timeout 9999 "Atualizando GenESyS..." &
    PID=$!

    git pull origin "$USER_BRANCH"

    cmake --preset gui-app
    cmake --build --preset gui-app

    cp -a "$BUILD_GENESYS_GUI_APP_PATH" "$INSTALL_DIR"

    cmake --preset web-app
    cmake --build --preset web-app

    cp -a "$BUILD_GENESYS_WEB_APP_PATH" "$INSTALL_DIR"

    cp -a "$PROJECT_ICON_PATH" "$ICON_DIR"

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

    rm -rf "$USER_REPO_PATH/build/"

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

    if gxmessage -buttons Sim:0 \
             -default Sim \
             "Há uma nova versão disponível para desenvolvedores.\nSeu GenESyS será atualizado. Confirma, ixtepô?"; then

        gxmessage -buttons "" -timeout 9999 "Atualizando ambiente de desenvolvimento..." &
        PID=$!

        git pull origin "$DEV_BRANCH"

        kill $PID 2>/dev/null || true
    fi
fi
