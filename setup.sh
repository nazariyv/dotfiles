#!/usr/bin/env bash
set -euo pipefail

# ─────── CONFIGURABLES ─────────────────────────────────────────────────────────
# 1) Where we keep our stage‐markers
STATE_DIR="/var/tmp/setup_state"
# 2) Path to this script (for @reboot cron entry)
SCRIPT_PATH="$(readlink -f "$0")"
# 3) Your GitHub repos (edit!)
DOTFILES_REPO="https://github.com/yourusername/dotfiles.git"
NVIM_CONF_REPO="https://github.com/yourusername/nvim-config.git"
# 4) Enable TEST_MODE=true to skip the actual reboot
TEST_MODE="${TEST_MODE:-false}"
# ────────────────────────────────────────────────────────────────────────────────

# must be root
if (( EUID != 0 )); then
  echo "→ please run me with sudo or as root"; exit 1
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
  reboot
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

  mark_stage "install_docker"
fi

# ─────── Stage 4: shell, nvm/node, zoxide, neovim, tmux plugins ───────────────
if ! stage_done "configure_shell"; then
  echo "### Stage 4: configuring zsh, nvm, node, zoxide, neovim, tmux‐tpm"

  # Oh My Zsh (non-interactive)
  export RUNZSH=no CHSH=no
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  ZSH_CUSTOM="${ZSH_CUSTOM:-/root/.oh-my-zsh/custom}"
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  # enable both in /root/.zshrc (you can tweak further)

  # NVM & latest LTS Node (as your sudo‐user)
  # NOTE: replace $SUDO_USER with real if you don't use sudo
  sudo -u "$SUDO_USER" -H bash <<'EOSU'
    git clone https://github.com/nvm-sh/nvm.git ~/.nvm
    cd ~/.nvm && git checkout v0.39.5
    . ~/.nvm/nvm.sh
    nvm install --lts
EOSU

  # zoxide (modern 'z')
  apt install -y zoxide
  echo 'eval "$(zoxide init zsh)"' >> "/home/$SUDO_USER/.zshrc"

  # Neovim via snap
  snap install --classic neovim

  # TPM (Tmux Plugin Manager) + clone your tmux.conf
  git clone https://github.com/tmux-plugins/tpm "/home/$SUDO_USER/.tmux/plugins/tpm"
  sudo -u "$SUDO_USER" -H bash <<'EOSU'
    git clone "$DOTFILES_REPO" ~/dotfiles
    ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf
EOSU

  mark_stage "configure_shell"
fi

# ─────── Stage 5: pull Neovim config ───────────────────────────────────────────
if ! stage_done "configure_neovim"; then
  echo "### Stage 5: cloning Neovim config"
  sudo -u "$SUDO_USER" -H bash <<'EOSU'
    git clone "$NVIM_CONF_REPO" ~/.config/nvim
EOSU
  mark_stage "configure_neovim"
fi

echo
echo "✅ All done!  Log out and log back in (or start a new shell) to begin using Zsh, Docker, Neovim & co."

