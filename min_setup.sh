#!/usr/bin/env bash
set -euo pipefail

# -------- CONFIGURÁVEIS --------
USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo vboxuser)}"
USER_HOME="/home/$USER_NAME"
KEYBOARD_CONF="/etc/default/keyboard"
ZERO_FILL="${ZERO_FILL:-1}"
# --------------------------------

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Execute como root: use 'su -' ou 'sudo -i'"
    exit 1
  fi
}

install_sudo_and_user() {
  echo "[+] Instalando sudo e configurando usuário (${USER_NAME})"
  apt update
  apt install -y sudo
  usermod -aG sudo "${USER_NAME}" || true
}

install_clion() {
  sudo -u "$USER_NAME" bash <<EOF
cd "$USER_HOME"

wget -O - https://download.jetbrains.com/cpp/CLion-2026.1.tar.gz | tar -xz
mv clion-* clion

cd clion/plugins

rm -rf angular-plugin react-plugin vuejs-plugin
rm -rf python-ce javascript-* nodeJS
rm -rf DatabaseTools clouds-* docker-*
rm -rf web* css* html* sass* less*
rm -rf tailwindcss postcss webpack styled-components
rm -rf color-scheme-* keymap-* localization-*
rm -rf qodana intellij-rust
rm -rf nextjs prettierJS tslint qml-plugin
rm -rf restClient gateway-plugin remote-dev-server
EOF
}

install_gui_minimal() {
  echo "[+] Instalando GUI mínima (Xorg + Openbox + LXSession + LightDM)"
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    xorg openbox lxsession lightdm lxterminal
}

install_prereqs() {
  echo "[+] Instalando pré-requisitos (Qt6 + build tools)"
  apt install -y --no-install-recommends \
    git g++ vim cmake ninja-build gxmessage \
    qt6-base-dev qt6-base-dev-tools \
    qt6-tools-dev qt6-tools-dev-tools \
    qt6-charts-dev \
    graphviz
}

install_firefox_minimal() {
  echo "[+] Instalando Firefox ESR mínimo"

  apt install -y --no-install-recommends firefox-esr

  # Definir como padrão (sem xdg)
  sudo -u "$USER_NAME" bash <<EOF
mkdir -p "$USER_HOME/.config"
cat > "$USER_HOME/.config/mimeapps.list" <<EOL
[Default Applications]
x-scheme-handler/http=firefox-esr.desktop
x-scheme-handler/https=firefox-esr.desktop
text/html=firefox-esr.desktop
EOL
EOF

  # Remover extras do Firefox
  rm -rf /usr/lib/firefox-esr/browser/features/* || true
  rm -rf /usr/lib/firefox-esr/browser/extensions/* || true
  rm -rf /usr/lib/firefox-esr/crashreporter || true
}

set_keyboard() {
  echo "[+] Configurando teclado ABNT2 (br)"

  if [ -f "${KEYBOARD_CONF}" ]; then
    sed -i \
      -e 's/^XKBMODEL=.*/XKBMODEL="abnt2"/' \
      -e 's/^XKBLAYOUT=.*/XKBLAYOUT="br"/' \
      "${KEYBOARD_CONF}"
  else
    cat > "${KEYBOARD_CONF}" <<EOF
XKBMODEL="abnt2"
XKBLAYOUT="br"
EOF
  fi

  setupcon || true
  localectl set-x11-keymap br abnt2 || true
}

configure_shortcuts() {
  echo "[+] Configurando Ctrl+Alt+T"

  OPENBOX_CONF="/etc/xdg/openbox/rc.xml"

  if [ -f "$OPENBOX_CONF" ]; then
    if ! grep -q '<keybind key="C-A-T">' "$OPENBOX_CONF"; then
      sed -i '/<\/keyboard>/i \
    <keybind key="C-A-T">\
      <action name="Execute">\
        <command>lxterminal</command>\
      </action>\
    </keybind>' "$OPENBOX_CONF"
    fi

    USER_CONF="/home/${USER_NAME}/.config/openbox"
    mkdir -p "$USER_CONF"
    cp "$OPENBOX_CONF" "$USER_CONF/lxde-rc.xml"
    chown -R ${USER_NAME}:${USER_NAME} "$USER_CONF"
  fi
}

setup_startup_script() {
  echo "[+] Configurando script remoto no boot"

  STARTUP_SCRIPT="/usr/local/bin/startup.sh"
  SERVICE_FILE="/etc/systemd/system/genesys_updater.service"
  SCRIPT_URL="https://raw.githubusercontent.com/genJTests/scripts/refs/heads/main/init.sh"
  USER_HOME="/home/$USER_NAME"

  wget -qO "$STARTUP_SCRIPT" "$SCRIPT_URL"
  chmod +x "$STARTUP_SCRIPT"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Genesys Startup Script
After=graphical.target network-online.target
Wants=graphical.target network-online.target

[Service]
Type=simple
User=root
Environment=DISPLAY=:0
Environment=XAUTHORITY=$USER_HOME/.Xauthority
ExecStart=$STARTUP_SCRIPT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable genesys_updater.service
}

cleanup_system_aggressive() {
  echo "[+] Limpeza AGRESSIVA"

  apt clean
  apt autoremove --purge -y

  rm -rf /usr/share/doc/*
  rm -rf /usr/share/man/*
  rm -rf /usr/share/info/*

  find /usr/share/locale -mindepth 1 -maxdepth 1 \
    ! -name "en*" ! -name "pt*" -exec rm -rf {} +

  rm -rf /usr/share/icons/*
  rm -rf /usr/share/themes/*

  rm -rf /var/cache/*
  rm -rf /var/lib/apt/lists/*

  journalctl --vacuum-time=1s || true
  rm -rf /var/log/*

  rm -rf /root/.bash_history || true
  rm -rf /home/*/.bash_history || true
}

trim_and_zerofill() {
  echo "[+] fstrim"
  fstrim -av || true

  if [ "${ZERO_FILL}" -eq 1 ]; then
    echo "[+] Zero fill"
    dd if=/dev/zero of=/zero.fill bs=1M status=progress || true
    rm -f /zero.fill
  fi
}

main() {
  require_root

  install_sudo_and_user
  install_clion
  install_gui_minimal
  install_prereqs
  install_firefox_minimal

  set_keyboard
  configure_shortcuts
  setup_startup_script

  cleanup_system_aggressive
  trim_and_zerofill

  echo "[+] Sistema otimizado. Reinicie a VM."
}

main "$@"
