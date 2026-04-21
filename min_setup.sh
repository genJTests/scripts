#!/usr/bin/env bash
set -euo pipefail

# -------- CONFIGURÁVEIS --------
USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo vboxuser)}"
KEYBOARD_CONF="/etc/default/keyboard"
ZERO_FILL="${ZERO_FILL:-1}"   # 1 = habilita dd zero-fill
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

install_gui() {
  echo "[+] Instalando Xorg + LXDE + LightDM"
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    xorg lxde-core lightdm
}

install_prereqs() {
  echo "[+] Instalando pré-requisitos (git, g++, Qt6, Graphviz)"
  apt install -y \
    git g++ vim cmake ninja-build gxmessage \
    qt6-base-dev qt6-base-dev-tools \
    qt6-tools-dev qt6-tools-dev-tools \
    qt6-charts-dev \
    graphviz
}

set_keyboard() {
  echo "[+] Configurando teclado ABNT2 (br)"
  if [ -f "${KEYBOARD_CONF}" ]; then
    sed -i \
      -e 's/^XKBMODEL=.*/XKBMODEL="abnt2"/' \
      -e 's/^XKBLAYOUT=.*/XKBLAYOUT="br"/' \
      "${KEYBOARD_CONF}"
  else
    echo "Arquivo ${KEYBOARD_CONF} não encontrado; criando..."
    cat > "${KEYBOARD_CONF}" <<EOF
XKBMODEL="abnt2"
XKBLAYOUT="br"
EOF
  fi

  # aplicar imediatamente (quando possível)
  setupcon || true
  localectl set-x11-keymap br abnt2 || true
}

cleanup_system() {
  echo "[+] Limpeza de pacotes e arquivos"
  apt clean
  apt autoremove --purge -y
  rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/* || true
}

trim_and_zerofill() {
  echo "[+] fstrim"
  fstrim -av || true

  if [ "${ZERO_FILL}" -eq 1 ]; then
    echo "[+] Preenchendo espaço livre com zeros (para melhorar compressão da OVA)"
    dd if=/dev/zero of=/zero.fill bs=1M status=progress || true
    rm -f /zero.fill
  fi
}

configure_shortcuts() {
  echo "[+] Configurando atalho Ctrl+Alt+T para abrir terminal"

  OPENBOX_CONF="/etc/xdg/openbox/rc.xml"

  if [ -f "$OPENBOX_CONF" ]; then
    # Evita duplicação
    if ! grep -q '<keybind key="C-A-T">' "$OPENBOX_CONF"; then
      sed -i '/<\/keyboard>/i \
    <keybind key="C-A-T">\
      <action name="Execute">\
        <command>xterm</command>\
      </action>\
    </keybind>' "$OPENBOX_CONF"
  
    # Propaga para usuário
    USER_CONF="/home/${USER_NAME}/.config/openbox"
    mkdir -p "$USER_CONF"
    cp "$OPENBOX_CONF" "$USER_CONF/lxde-rc.xml"
    chown -R ${USER_NAME}:${USER_NAME} /home/${USER_NAME}/.config
  fi
  else
    echo "Arquivo $OPENBOX_CONF não encontrado"
  fi
}

setup_startup_script() {
  echo "[+] Configurando script remoto para executar no boot (systemd)"

  STARTUP_SCRIPT="/usr/local/bin/startup.sh"
  SERVICE_FILE="/etc/systemd/system/genesys_updater.service"
  SCRIPT_URL="https://raw.githubusercontent.com/joaomeloo/Genesys-Simulator/refs/heads/2026-1/scripts/init.sh"
  USER_NAME="vboxuser"
  USER_HOME="/home/$USER_NAME"

  # Baixa o script remoto
  if ! wget -qO "$STARTUP_SCRIPT" "$SCRIPT_URL"; then
    echo "Erro ao baixar script"
    exit 1
  fi

  chmod +x "$STARTUP_SCRIPT"

  # Cria o serviço systemd
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

main() {
  require_root

  install_sudo_and_user
  install_gui
  install_prereqs
  set_keyboard
  configure_shortcuts
  setup_startup_script
  cleanup_system
  trim_and_zerofill

  echo "[+] Concluído. Reinicie a VM para aplicar completamente."
}

main "$@"