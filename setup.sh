#!/usr/bin/env bash
set -euo pipefail

# ─────── CONFIGURABLES ─────────────────────────────────────────────────────────
STATE_DIR="/var/tmp/setup_state"
SCRIPT_PATH="$(readlink -f "$0")"
DOTFILES_PATH="$(dirname "$SCRIPT_PATH")"
TEST_MODE="${TEST_MODE:-false}"
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

schedule_reboot() {
  echo "→ scheduling resume after reboot via cron"
  ensure_cron
  (crontab -l 2>/dev/null || true; echo "@reboot sleep 30 && $SCRIPT_PATH") | crontab -
  mark_stage reboot_scheduled
  echo "→ rebooting now…"
  [[ "$TEST_MODE" == "true" ]] && echo "→ TEST_MODE: skipping actual reboot" || reboot
}

remove_reboot_schedule() {
  echo "→ cleaning up @reboot entry"
  if command -v crontab &>/dev/null; then
    tmp=$(mktemp)
    crontab -l 2>/dev/null | grep -Fv "$SCRIPT_PATH" >"$tmp" || true
    crontab "$tmp" 2>/dev/null || true
    rm -f "$tmp"
  fi
  mark_stage reboot_completed
}

# ─────── helpers ───────────────────────────────────────────────────────────────
install_latest_neovim() {
  local want_ver="0.10.1"                             # don’t bother if nvim ≥ 0.10

  local arch; arch="$(dpkg --print-architecture)"
  if [[ "$arch" != "amd64" ]]; then            # arm64, ppc64el, s390x, …
    echo "→ $arch detected – installing from PPA instead of GitHub binary"
    add-apt-repository -y ppa:neovim-ppa/unstable       # already have software-properties-common
    apt-get update -qq
    apt-get install -y neovim
    return
  fi

  if command -v nvim &>/dev/null &&
     dpkg --compare-versions "$(nvim --version | awk 'NR==1{print $2}')" ge "$want_ver"
  then
    echo "→ Neovim already recent enough"
    return
  fi

  echo "→ fetching the latest Neovim release (GitHub API)"
  local tmp asset_url
  tmp="$(mktemp -d)"

  # 1. Discover the correct asset URL
  asset_url="$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest \
               | grep -oP '"browser_download_url":\s*"\K[^"]*nvim-linux64\.tar\.gz')"

  # 2. Download with retries & fail-fast
  if ! curl -Lf --retry 3 --retry-delay 2 -o "$tmp/nvim.tar.gz" "$asset_url"; then
    echo "⚠️  GitHub download failed – falling back to PPA"
    add-apt-repository -y ppa:neovim-ppa/unstable     # needs software-properties-common (already installed)
    apt update
    apt install -y neovim
    rm -rf "$tmp"
    return
  fi

  # 3. Sanity-check that we really received a gzip file
  if ! gzip -t "$tmp/nvim.tar.gz" &>/dev/null; then
    echo "⚠️  Downloaded file is not a valid gzip archive – falling back to PPA"
    add-apt-repository -y ppa:neovim-ppa/unstable
    apt update
    apt install -y neovim
    rm -rf "$tmp"
    return
  fi

  # 4. Extract & install
  tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"
  install -m 0755 "$tmp"/nvim-linux64/bin/nvim /usr/local/bin/nvim
  rm -rf "$tmp"
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

# ─────── Stage 0: essentials ──────────────────────────────────────────────────
if ! stage_done install_essentials; then
  echo "### Stage 0: installing essential packages"
  apt update
  apt install -y cron curl wget gnupg lsb-release sudo software-properties-common
  [[ "$CONTAINER_MODE" != "true" ]] && systemctl enable --now cron || service cron start || true
  mark_stage install_essentials
fi

# ─────── Stage 1: full upgrade ────────────────────────────────────────────────
if ! stage_done update_upgrade; then
  echo "### Stage 1: apt update && apt upgrade"
  apt update && apt -y upgrade
  mark_stage update_upgrade
  [[ "$TEST_MODE" == "true" ]] || { schedule_reboot; exit 0; }
fi

# ─────── Stage 2: cron cleanup after reboot ───────────────────────────────────
if ! stage_done reboot_completed; then
  echo "### Stage 2: removing reboot-schedule"
  remove_reboot_schedule
fi

# ─────── Stage 3: core tools + Docker ─────────────────────────────────────────
if ! stage_done install_docker; then
  echo "### Stage 3: installing prerequisites & Docker"
  apt install -y \
    apt-transport-https ca-certificates curl gnupg lsb-release \
    git build-essential clang zsh btop fzf tmux snapd

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  apt update && apt install -y docker-ce docker-ce-cli containerd.io

  [[ "$CONTAINER_MODE" != "true" ]] && systemctl enable --now docker || { dockerd >/var/log/dockerd.log 2>&1 & sleep 5; }
  usermod -aG docker "$SUDO_USER"
  mark_stage install_docker
fi

# ─────── Stage 4: shell, Node, zoxide, Neovim binary, tmux plugins ────────────
if ! stage_done configure_shell; then
  echo "### Stage 4: configuring zsh, nvm/Node, Neovim binary, zoxide, tmux-tpm"
  USER_HOME="/home/$SUDO_USER"

  # Oh-My-Zsh (non-interactive)
  run_as_user '
    export RUNZSH=no CHSH=no
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" || true
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" || true
  '

  install_nvm_and_node          # NEW
  apt install -y zoxide
  echo 'eval "$(zoxide init zsh)"' >>"$USER_HOME/.zshrc"

  # Latest Neovim binary (works in container too)  NEW
  install_latest_neovim

  # TPM
  run_as_user 'git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm' || true

  # Link dotfiles
  for df in .tmux.conf .zshrc .vimrc .gitconfig .bashrc; do
    [[ -e "$DOTFILES_PATH/$df" ]] && run_as_user "ln -sf '$DOTFILES_PATH/$df' '$USER_HOME/$df'" && echo "→ linked $df"
  done

  mark_stage configure_shell
fi

# ─────── Stage 5: Neovim config ───────────────────────────────────────────────
if ! stage_done configure_neovim; then
  echo "### Stage 5: setting up Neovim config"
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

# ─────── Stage 6: final tweaks ────────────────────────────────────────────────
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

