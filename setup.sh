#!/usr/bin/env bash
set -euo pipefail

# ─────── CONFIGURABLES ─────────────────────────────────────────────────────────
# 1) Where we keep our stage‐markers
STATE_DIR="/var/tmp/setup_state"
# 2) Path to this script (for @reboot cron entry)
SCRIPT_PATH="$(readlink -f "$0")"
# 3) Path to the dotfiles repo (where this script is located)
DOTFILES_PATH="$(dirname "$SCRIPT_PATH")"
# 4) Enable TEST_MODE=true to skip the actual reboot
TEST_MODE="${TEST_MODE:-false}"
# 5) Detect if we're in a container
CONTAINER_MODE="${CONTAINER_MODE:-false}"
if [[ -f /.dockerenv ]] && [[ "$CONTAINER_MODE" != "false" ]]; then
  CONTAINER_MODE=true
fi
# ────────────────────────────────────────────────────────────────────────────────

# must be root
if (( EUID != 0 )); then
  echo "→ please run me with sudo or as root"; exit 1
fi

# Ensure we have a valid user to work with
if [[ -z "${SUDO_USER:-}" ]]; then
  if [[ "$CONTAINER_MODE" == "true" ]]; then
    SUDO_USER="${SUDO_USER:-testuser}"
    # Create the user if it doesn't exist
    if ! id "$SUDO_USER" &>/dev/null; then
      useradd -m -s /bin/bash "$SUDO_USER"
      echo "→ created test user: $SUDO_USER"
    fi
  else
    echo "→ please run with sudo (need \$SUDO_USER)"
    exit 1
  fi
fi

mkdir -p "$STATE_DIR"

stage_done()   { [[ -f "$STATE_DIR/$1" ]]; }
mark_stage()   { touch "$STATE_DIR/$1"; }

# Helper function to run commands as the target user
run_as_user() {
  if command -v sudo >/dev/null 2>&1; then
    sudo -u "$SUDO_USER" -H bash -c "$1"
  else
    # Fallback for environments without sudo
    su - "$SUDO_USER" -c "$1"
  fi
}

# Function to ensure cron is installed and running
ensure_cron() {
  if ! command -v crontab >/dev/null 2>&1; then
    echo "→ installing cron"
    apt update
    apt install -y cron
    
    # Start cron service if not in container mode
    if [[ "$CONTAINER_MODE" != "true" ]]; then
      systemctl enable --now cron
    else
      # In container, just start the service
      service cron start || true
    fi
  fi
}

schedule_reboot() {
  echo "→ scheduling resume after reboot via cron"
  ensure_cron
  
  ( crontab -l 2>/dev/null || true;
    echo "@reboot sleep 30 && $SCRIPT_PATH"
  ) | crontab -
  mark_stage "reboot_scheduled"
  echo "→ rebooting now…"
  if [[ "$TEST_MODE" == "true" ]]; then
    echo "→ TEST_MODE: skipping actual reboot"
  else
    reboot
  fi
}

remove_reboot_schedule() {
  echo "→ cleaning up @reboot entry"
  if command -v crontab >/dev/null 2>&1; then
    # Get current crontab, remove our entry, and reinstall
    TEMP_CRON=$(mktemp)
    crontab -l 2>/dev/null | grep -Fv "$SCRIPT_PATH" > "$TEMP_CRON" || true
    crontab "$TEMP_CRON" 2>/dev/null || true
    rm -f "$TEMP_CRON"
  fi
  mark_stage "reboot_completed"
}

# ─────── Stage 0: install essential packages ───────────────────────────────────
if ! stage_done "install_essentials"; then
  echo "### Stage 0: installing essential packages"
  apt update
  apt install -y cron curl wget gnupg lsb-release sudo
  
  # Start cron if not in container mode
  if [[ "$CONTAINER_MODE" != "true" ]]; then
    systemctl enable --now cron
  else
    service cron start || true
  fi
  
  mark_stage "install_essentials"
fi

# ─────── Stage 1: apt update & upgrade (needs reboot) ──────────────────────────
if ! stage_done "update_upgrade"; then
  echo "### Stage 1: apt update && apt upgrade"
  apt update && apt -y upgrade
  mark_stage "update_upgrade"

  if [[ "$TEST_MODE" == "true" ]]; then
    echo "→ TEST_MODE: skipping reboot"
    # In test mode, we continue immediately - no actual reboot needed
  else
    schedule_reboot
    # This will reboot and the script will restart, so we exit here
    exit 0
  fi
fi

# ─────── Stage 2: post-reboot cleanup ──────────────────────────────────────────
if ! stage_done "reboot_completed"; then
  echo "### Stage 2: removing reboot‐schedule"
  remove_reboot_schedule
fi

# ─────── Stage 3: install core tools + Docker ──────────────────────────────────
if ! stage_done "install_docker"; then
  echo "### Stage 3: installing prerequisites & Docker"
  # core
  apt install -y \
    apt-transport-https ca-certificates curl gnupg lsb-release \
    git build-essential clang zsh btop fzf tmux snapd
  
  # Docker CE
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt update
  apt install -y docker-ce docker-ce-cli containerd.io
  
  # Handle Docker service in container vs host
  if [[ "$CONTAINER_MODE" != "true" ]]; then
    systemctl enable --now docker
  else
    # In container, try to start dockerd in background
    dockerd > /var/log/dockerd.log 2>&1 &
    sleep 5  # Give dockerd time to start
  fi
  
  # Add user to docker group
  usermod -aG docker "$SUDO_USER"

  mark_stage "install_docker"
fi

# ─────── Stage 4: shell, nvm/node, zoxide, neovim, tmux plugins ───────────────
if ! stage_done "configure_shell"; then
  echo "### Stage 4: configuring zsh, nvm, node, zoxide, neovim, tmux‐tpm"
  
  USER_HOME="/home/$SUDO_USER"

  # Oh My Zsh (non-interactive) for the user
  run_as_user '
    export RUNZSH=no CHSH=no
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    
    # Install zsh plugins
    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  '

  # NVM & latest LTS Node
  run_as_user '
    git clone https://github.com/nvm-sh/nvm.git ~/.nvm
    cd ~/.nvm && git checkout v0.39.5
    . ~/.nvm/nvm.sh
    nvm install --lts
  '

  # zoxide (modern 'z')
  apt install -y zoxide
  echo 'eval "$(zoxide init zsh)"' >> "$USER_HOME/.zshrc"

  # Neovim - try snap first, fallback to apt
  if command -v snap >/dev/null 2>&1 && [[ "$CONTAINER_MODE" != "true" ]]; then
    snap install --classic neovim
  else
    echo "→ snap not available or in container, installing neovim via apt"
    apt install -y neovim
  fi

  # TPM (Tmux Plugin Manager)
  run_as_user 'git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm'

  # Link dotfiles from the repo
  if [[ -f "$DOTFILES_PATH/.tmux.conf" ]]; then
    run_as_user "ln -sf '$DOTFILES_PATH/.tmux.conf' '$USER_HOME/.tmux.conf'"
    echo "→ linked .tmux.conf"
  fi
  
  if [[ -f "$DOTFILES_PATH/.zshrc" ]]; then
    run_as_user "ln -sf '$DOTFILES_PATH/.zshrc' '$USER_HOME/.zshrc'"
    echo "→ linked .zshrc"
  fi

  # Link other dotfiles if they exist
  for dotfile in .vimrc .gitconfig .bashrc; do
    if [[ -f "$DOTFILES_PATH/$dotfile" ]]; then
      run_as_user "ln -sf '$DOTFILES_PATH/$dotfile' '$USER_HOME/$dotfile'"
      echo "→ linked $dotfile"
    fi
  done

  mark_stage "configure_shell"
fi

# ─────── Stage 5: setup Neovim config ─────────────────────────────────────────
if ! stage_done "configure_neovim"; then
  echo "### Stage 5: setting up Neovim config"
  
  USER_HOME="/home/$SUDO_USER"
  
  # Create nvim config directory and link/copy config
  run_as_user "mkdir -p '$USER_HOME/.config'"
  
  if [[ -d "$DOTFILES_PATH/nvim" ]]; then
    # If there's an nvim directory in the repo, link it
    run_as_user "ln -sf '$DOTFILES_PATH/nvim' '$USER_HOME/.config/nvim'"
    echo "→ linked nvim config directory"
  elif [[ -f "$DOTFILES_PATH/init.vim" ]] || [[ -f "$DOTFILES_PATH/init.lua" ]]; then
    # If there are nvim config files in the root, create nvim dir and link them
    run_as_user "mkdir -p '$USER_HOME/.config/nvim'"
    for nvim_file in init.vim init.lua; do
      if [[ -f "$DOTFILES_PATH/$nvim_file" ]]; then
        run_as_user "ln -sf '$DOTFILES_PATH/$nvim_file' '$USER_HOME/.config/nvim/$nvim_file'"
        echo "→ linked $nvim_file"
      fi
    done
  fi
  
  mark_stage "configure_neovim"
fi

# ─────── Stage 6: final setup ─────────────────────────────────────────────────
if ! stage_done "final_setup"; then
  echo "### Stage 6: final setup"
  
  # Change default shell to zsh for the user
  chsh -s "$(which zsh)" "$SUDO_USER"
  
  # Set proper ownership for all user files
  chown -R "$SUDO_USER:$SUDO_USER" "/home/$SUDO_USER"
  
  mark_stage "final_setup"
fi

echo
echo "✅ All done! Log out and log back in (or start a new shell) to begin using Zsh, Docker, Neovim & co."
echo "→ Your dotfiles from $DOTFILES_PATH have been linked to your home directory"
echo "→ You've been added to the docker group (effective after re-login)"
echo "→ Default shell changed to zsh"
