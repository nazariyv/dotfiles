#!/usr/bin/env bash
set -euo pipefail

# ─────── CONFIGURABLES ─────────────────────────────────────────────────────────
STATE_DIR="/var/tmp/setup_state"
SCRIPT_PATH="$(readlink -f "$0")"
DOTFILES_PATH="$(dirname "$SCRIPT_PATH")"
CONTAINER_MODE="${CONTAINER_MODE:-false}"
if [[ -f /.dockerenv ]] && [[ "$CONTAINER_MODE" != "false" ]]; then
  CONTAINER_MODE=true
fi
# ───────────────────────────────────────────────────────────────────────────────

[[ $EUID -ne 0 ]] && { echo "→ please run me with sudo or as root"; exit 1; }

if [[ -z "${SUDO_USER:-}" ]]; then
  if [[ "$CONTAINER_MODE" == "true" ]]; then
    SUDO_USER="testuser"
    id "$SUDO_USER" &>/dev/null || { useradd -m -s /bin/bash "$SUDO_USER"; echo "→ created test user: $SUDO_USER"; }
  else
    echo "→ please run with sudo (need \$SUDO_USER)"; exit 1
  fi
fi

mkdir -p "$STATE_DIR"
stage_done() { [[ -f "$STATE_DIR/$1" ]]; }
mark_stage() { touch "$STATE_DIR/$1"; }
run_as_user() { command -v sudo &>/dev/null && sudo -u "$SUDO_USER" -H bash -c "$1" || su - "$SUDO_USER" -c "$1"; }

ensure_cron() {
  command -v crontab &>/dev/null && return
  echo "→ installing cron"
  apt update
  apt install -y cron
  [[ "$CONTAINER_MODE" != "true" ]] && systemctl enable --now cron || service cron start || true
}

# ─────── helpers ───────────────────────────────────────────────────────────────
install_latest_neovim() {
  add-apt-repository -y ppa:neovim-ppa/unstable       # already have software-properties-common
  apt-get update -qq
  apt-get install -y neovim

  echo "→ installed $(nvim --version | head -n1)"
}

install_nvm_and_node() {
  local nvm_dir
  nvm_dir="/home/$SUDO_USER/.nvm"
  run_as_user "
    mkdir -p '$nvm_dir'
    if [ ! -d '$nvm_dir/.git' ]; then
      git clone https://github.com/nvm-sh/nvm.git '$nvm_dir'
    fi
    cd '$nvm_dir' && git fetch --tags --quiet && git checkout \$(git describe --abbrev=0 --tags)
    . '$nvm_dir/nvm.sh'
    nvm install --lts
    nvm alias default lts/*
  "

  # Make Node available for ALL future shells (bash & zsh)
  cat >/etc/profile.d/nvm.sh <<'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
# preload default silently so `node` is on PATH
command -v nvm &>/dev/null && nvm use --silent default &>/dev/null || true
EOF
  chmod +x /etc/profile.d/nvm.sh
}

if ! stage_done install_essentials; then
  echo "### Stage 0: installing essential packages"
  apt update
  apt install -y cron curl wget gnupg lsb-release sudo software-properties-common
  [[ "$CONTAINER_MODE" != "true" ]] && systemctl enable --now cron || service cron start || true
  mark_stage install_essentials
fi

if ! stage_done update_upgrade; then
  echo "### Stage 1: apt update && apt upgrade"
  apt update && apt -y upgrade
  mark_stage update_upgrade
fi

if ! stage_done install_docker; then
  echo "### Stage 2: installing prerequisites & Docker"
  apt install -y \
    apt-transport-https ca-certificates curl gnupg lsb-release \
    git build-essential clang zsh btop fzf tmux snapd libluajit-5.1-dev liblua5.1-dev

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  apt update && apt install -y docker-ce docker-ce-cli containerd.io

  [[ "$CONTAINER_MODE" != "true" ]] && systemctl enable --now docker || { dockerd >/var/log/dockerd.log 2>&1 & sleep 5; }
  usermod -aG docker "$SUDO_USER"
  mark_stage install_docker
fi

if ! stage_done configure_shell; then
  echo "### Stage 3: configuring zsh, nvm/Node, Neovim binary, zoxide, tmux-tpm"
  USER_HOME="/home/$SUDO_USER"

  # Oh-My-Zsh (non-interactive)
  run_as_user '
    export RUNZSH=no CHSH=no
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" || true
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" || true
  '

  install_nvm_and_node
  cat >/etc/zsh/zprofile <<'EOF'
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh" --silent
EOF
  apt install -y zoxide
  echo 'eval "$(zoxide init zsh)"' >>"$USER_HOME/.zshrc"

  # Latest Neovim binary (works in container too)
  install_latest_neovim

  # TPM
  run_as_user 'git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm' || true

  # Link dotfiles
  for df in .tmux.conf .zshrc .vimrc .gitconfig .bashrc; do
    [[ -e "$DOTFILES_PATH/$df" ]] && run_as_user "ln -sf '$DOTFILES_PATH/$df' '$USER_HOME/$df'" && echo "→ linked $df"
  done

  mark_stage configure_shell
fi

if ! stage_done configure_neovim; then
  echo "### Stage 4: setting up Neovim config"
  USER_HOME="/home/$SUDO_USER"
  run_as_user "mkdir -p '$USER_HOME/.config'"
  if [[ -d "$DOTFILES_PATH/nvim" ]]; then
    run_as_user "ln -sf '$DOTFILES_PATH/nvim' '$USER_HOME/.config/nvim'"
  else
    for nv in init.vim init.lua; do
      [[ -f "$DOTFILES_PATH/$nv" ]] && { run_as_user "mkdir -p '$USER_HOME/.config/nvim'"; run_as_user "ln -sf '$DOTFILES_PATH/$nv' '$USER_HOME/.config/nvim/$nv'"; }
    done
  fi
  mark_stage configure_neovim
fi

if ! stage_done install_rust; then
  echo "### Stage 5: installing Rust via rustup"
  # run rustup install as the target user
  run_as_user 'curl https://sh.rustup.rs -sSf | sh -s -- -y'
  # ensure cargo bin is on the PATH for all login shells
  cat >/etc/profile.d/rust.sh <<'EOF'
export PATH="$HOME/.cargo/bin:$PATH"
EOF
  chmod +x /etc/profile.d/rust.sh
  mark_stage install_rust
fi

if ! stage_done final_setup; then
  echo "### Stage 6: final setup"
  chsh -s "$(command -v zsh)" "$SUDO_USER"
  chown -R "$SUDO_USER:$SUDO_USER" "/home/$SUDO_USER"
  mark_stage final_setup
fi

echo
echo "✅ All done! Log out and back in (or start a new shell)."
echo "→ Dotfiles from $DOTFILES_PATH are linked"
echo "→ You’re in the docker group (effective after re-login)"
echo "→ Default shell changed to zsh"

