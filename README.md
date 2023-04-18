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
