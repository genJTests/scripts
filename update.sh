#!/usr/bin/env bash
set -euo pipefail

VERSION_FILE="/etc/genesys_ova_version"
CURRENT_VERSION="1.1" # Incremente ao fazer novo update

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Execute como root"
    exit 1
  fi
}

get_installed_version() {
  if [ -f "$VERSION_FILE" ]; then
    cat "$VERSION_FILE"
  else
    echo "0.0"
  fi
}

set_version() {
  echo "$1" > "$VERSION_FILE"
}

version_gt() {
  # retorna 0 (true) se $1 > $2
  dpkg --compare-versions "$1" gt "$2"
}

update_1_0() {
  echo "[+] Aplicando update 1.0"
  # exemplo: apt update
}

update_1_1() {
  echo "[+] MIGRAÇÃO COMPLETA: INIT ANTIGO → NOVO SISTEMA"

  REAL_USER="vboxuser"
  USER_HOME="/home/vboxuser"

  mkdir -p "$USER_HOME/.local/bin"
  mkdir -p "$USER_HOME/.config/autostart"
  mkdir -p "$USER_HOME/Documents/Genesys-Dev"

  echo "[+] Removendo bootstrap antigo..."
  rm -f "$USER_HOME/.local/bin/genesys_startup.sh" || true

  echo "[+] Instalando novo init.sh"
  INIT_URL="https://raw.githubusercontent.com/genJTests/scripts/refs/heads/main/init.sh"

  wget -qO /usr/local/bin/genesys_init.sh "$INIT_URL"
  chmod 755 /usr/local/bin/genesys_init.sh

  echo "[+] Criando launcher limpo"
  cat > "$USER_HOME/.local/bin/genesys_startup.sh" <<EOF
#!/bin/bash
set -euo pipefail
exec /usr/local/bin/genesys_init.sh
EOF

  chmod +x "$USER_HOME/.local/bin/genesys_startup.sh"

  echo "[+] Atualizando autostart"
  cat > "$USER_HOME/.config/autostart/genesys_init.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Genesys Init System
Exec=$USER_HOME/.local/bin/genesys_startup.sh
Icon=system-software-update
Terminal=false
X-GNOME-Autostart-enabled=true
Categories=Development;
EOF

  echo "[+] Migrando Genesys-Simulator para dentro de Genesys-Dev"

  OLD_REPO="$USER_HOME/Documents/Genesys-Simulator"
  NEW_PARENT="$USER_HOME/Documents/Genesys-Dev"
  NEW_REPO="$NEW_PARENT/Genesys-Simulator"

  if [ -d "$OLD_REPO" ]; then
    if [ ! -d "$NEW_REPO" ]; then
      mv "$OLD_REPO" "$NEW_PARENT/"
      echo "[+] Movido para $NEW_REPO"
    else
      echo "[!] Destino já existe, não movendo"
    fi
  else
    echo "[!] Nenhum repositório antigo encontrado"
  fi

  echo "[+] Limpando serviço antigo (apenas arquivo)"
  rm -f "$USER_HOME/.config/systemd/user/genesys-web.service"

  echo "[+] Garantindo dependências"
  apt-get update -y
  apt-get install -y curl wget git gxmessage tar

  echo "[+] Corrigindo permissões"
  chown -R "$REAL_USER:$REAL_USER" \
    "$USER_HOME/.local" \
    "$USER_HOME/.config" \
    "$USER_HOME/Documents"

  echo "[+] MIGRAÇÃO CONCLUÍDA"
}

run_updates() {
  local INSTALLED
  INSTALLED=$(get_installed_version)

  echo "[+] Versão instalada: $INSTALLED"
  echo "[+] Versão alvo: $CURRENT_VERSION"

  # Adicione novas versoes ao fazer updates (Ex: for v in 1.0 1.1 1.2 do)
  for v in 1.0 1.1; do
    if version_gt "$v" "$INSTALLED"; then
      FUNC="update_${v//./_}"

      if declare -f "$FUNC" >/dev/null; then
        "$FUNC"
        set_version "$v"
      else
        echo "[-] Função $FUNC não encontrada"
        exit 1
      fi
    fi
  done

  echo "[+] Sistema atualizado para $CURRENT_VERSION"
}

main() {
  require_root
  run_updates
}

main "$@"
