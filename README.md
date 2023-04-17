# Dotfiles

Welcome to my dotfiles. To get started, execute

```bash
./setup.sh
```

next, run the ansible playbook

```bash
ansible-playbook ansible/main.yml --ask-become-pass
```

## TODO

- install nerd font
- aliases / ssh keys
- make setup.sh determine the os, if mac, use brew, if ubuntu apt-get
- install zsh with powerline
- make terminal start in tmux straight up (this gets appended to .zsh):

```bash
# Call tmux for every interactive shell. Cause tmux is awesome.
if [[ -z "$TMUX" ]]; then
    ID=$(/usr/bin/tmux ls | grep -vm1 attached | cut -d: -f1)
    if [[ -z "${ID}" ]]; then
        /usr/bin/tmux new-session
    else
        /usr/bin/tmux attach-session -t "${ID}"
    fi
fi
```
