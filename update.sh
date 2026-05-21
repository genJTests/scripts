#!/usr/bin/env bash
set -euo pipefail

VERSION_FILE="/etc/genesys_ova_version"
CURRENT_VERSION="1.0"

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
  dpkg --compare-versions "$1" gt "$2"
}

update_1_0() {
  echo "[+] MIGRAÇÃO COMPLETA: INIT ANTIGO → NOVO SISTEMA"

  REAL_USER="vboxuser"
  USER_HOME="/home/vboxuser"

  mkdir -p "$USER_HOME/.local/bin"
  mkdir -p "$USER_HOME/.config/autostart"

  rm -f "$USER_HOME/.local/bin/genesys_startup.sh" || true

  apt-get update -y || true
  apt-get install -y wget curl git gxmessage tar || true

  INIT_URL="https://raw.githubusercontent.com/genJTests/scripts/refs/heads/main/init.sh"

  DOWNLOAD_OK=0
  for i in 1 2 3; do
    if wget -qO /usr/local/bin/genesys_init.sh "$INIT_URL"; then
      DOWNLOAD_OK=1
      break
    fi
    sleep 5
  done

  if [ "$DOWNLOAD_OK" -ne 1 ]; then
    return 0
  fi

  chmod 755 /usr/local/bin/genesys_init.sh

  cat > "$USER_HOME/.local/bin/genesys_startup.sh" <<EOF
#!/bin/bash
set -euo pipefail
exec /usr/local/bin/genesys_init.sh
EOF

  chmod +x "$USER_HOME/.local/bin/genesys_startup.sh"

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

  OLD_REPO="$USER_HOME/Documents/Genesys-Simulator"
  NEW_REPO="$USER_HOME/Documents/Genesys-Dev"

  if [ -d "$OLD_REPO/.git" ]; then
    if [ ! -e "$NEW_REPO" ]; then
      mv "$OLD_REPO" "$NEW_REPO"
    fi
  fi

  if [ -d "$NEW_REPO/.git" ]; then
    DEV_REPO_PATH="$NEW_REPO"
  elif [ -d "$OLD_REPO/.git" ]; then
    DEV_REPO_PATH="$OLD_REPO"
  else
    DEV_REPO_PATH=""
  fi

  DEV_BRANCH_FILE="$USER_HOME/.genesys_dev_branch"
  echo "currentStable" > "$DEV_BRANCH_FILE"

  if [ -n "$DEV_REPO_PATH" ]; then
    if cd "$DEV_REPO_PATH"; then
      if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git config genesys.lastAppliedBranch "currentStable"
      fi
    fi
  fi

  rm -f "$USER_HOME/.config/systemd/user/genesys-web.service"

  chown -R "$REAL_USER:$REAL_USER" \
    "$USER_HOME/.local" \
    "$USER_HOME/.config" \
    "$USER_HOME/Documents" || true

  chown "$REAL_USER:$REAL_USER" "$DEV_BRANCH_FILE" || true

  echo "[+] MIGRAÇÃO CONCLUÍDA"
}

update_1_1() {
  echo "[+] Update 1.1"
}

run_updates() {
  local INSTALLED
  INSTALLED=$(get_installed_version)

  for v in 1.0; do
    if version_gt "$v" "$INSTALLED"; then
      FUNC="update_${v//./_}"
      "$FUNC"
      set_version "$v"
    fi
  done
}

main() {
  require_root
  run_updates
}

main "$@"
