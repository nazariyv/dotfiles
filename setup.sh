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
# ────────────────────────────────────────────────────────────────────────────────

# must be root
if (( EUID != 0 )); then
  echo "→ please run me with sudo or as root"; exit 1
fi

# Ensure we have a valid user to work with
if [[ -z "${SUDO_USER:-}" ]]; then
  echo "→ please run with sudo (need \$SUDO_USER)"
  exit 1
fi

mkdir -p "$STATE_DIR"

stage_done()   { [[ -f "$STATE_DIR/$1" ]]; }
mark_stage()   { touch "$STATE_DIR/$1"; }
schedule_reboot() {
  echo "→ scheduling resume after reboot via cron"
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
  crontab -l 2>/dev/null \
    | grep -Fv "$SCRIPT_PATH" \
    | crontab -
  mark_stage "reboot_completed"
}

# ─────── Stage 1: apt update & upgrade (needs reboot) ──────────────────────────
if ! stage_done "update_upgrade"; then
  echo "### Stage 1: apt update && apt upgrade"
  apt update && apt -y upgrade
  mark_stage "update_upgrade"

  if [[ "$TEST_MODE" == "true" ]]; then
    echo "→ TEST_MODE: skipping reboot"
  else
    schedule_reboot
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
  systemctl enable --now docker
  
  # Add user to docker group
  usermod -aG docker "$SUDO_USER"

  mark_stage "install_docker"
fi

# ─────── Stage 4: shell, nvm/node, zoxide, neovim, tmux plugins ───────────────
if ! stage_done "configure_shell"; then
  echo "### Stage 4: configuring zsh, nvm, node, zoxide, neovim, tmux‐tpm"
  
  USER_HOME="/home/$SUDO_USER"

  # Oh My Zsh (non-interactive) for the user
  sudo -u "$SUDO_USER" -H bash <<EOSU
    export RUNZSH=no CHSH=no
    sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    
    # Install zsh plugins
    ZSH_CUSTOM="\${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}"
    git clone https://github.com/zsh-users/zsh-autosuggestions "\$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "\$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
EOSU

  # NVM & latest LTS Node
  sudo -u "$SUDO_USER" -H bash <<EOSU
    git clone https://github.com/nvm-sh/nvm.git ~/.nvm
    cd ~/.nvm && git checkout v0.39.5
    . ~/.nvm/nvm.sh
    nvm install --lts
EOSU

  # zoxide (modern 'z')
  apt install -y zoxide
  echo 'eval "$(zoxide init zsh)"' >> "$USER_HOME/.zshrc"

  # Neovim via snap
  snap install --classic neovim

  # TPM (Tmux Plugin Manager)
  sudo -u "$SUDO_USER" -H bash <<EOSU
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
EOSU

  # Link dotfiles from the repo
  if [[ -f "$DOTFILES_PATH/.tmux.conf" ]]; then
    sudo -u "$SUDO_USER" ln -sf "$DOTFILES_PATH/.tmux.conf" "$USER_HOME/.tmux.conf"
    echo "→ linked .tmux.conf"
  fi
  
  if [[ -f "$DOTFILES_PATH/.zshrc" ]]; then
    sudo -u "$SUDO_USER" ln -sf "$DOTFILES_PATH/.zshrc" "$USER_HOME/.zshrc"
    echo "→ linked .zshrc"
  fi

  # Link other dotfiles if they exist
  for dotfile in .vimrc .gitconfig .bashrc; do
    if [[ -f "$DOTFILES_PATH/$dotfile" ]]; then
      sudo -u "$SUDO_USER" ln -sf "$DOTFILES_PATH/$dotfile" "$USER_HOME/$dotfile"
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
  sudo -u "$SUDO_USER" mkdir -p "$USER_HOME/.config"
  
  if [[ -d "$DOTFILES_PATH/nvim" ]]; then
    # If there's an nvim directory in the repo, link it
    sudo -u "$SUDO_USER" ln -sf "$DOTFILES_PATH/nvim" "$USER_HOME/.config/nvim"
    echo "→ linked nvim config directory"
  elif [[ -f "$DOTFILES_PATH/init.vim" ]] || [[ -f "$DOTFILES_PATH/init.lua" ]]; then
    # If there are nvim config files in the root, create nvim dir and link them
    sudo -u "$SUDO_USER" mkdir -p "$USER_HOME/.config/nvim"
    for nvim_file in init.vim init.lua; do
      if [[ -f "$DOTFILES_PATH/$nvim_file" ]]; then
        sudo -u "$SUDO_USER" ln -sf "$DOTFILES_PATH/$nvim_file" "$USER_HOME/.config/nvim/$nvim_file"
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
