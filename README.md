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

- create a script to update all the dotfiles. If changes made in upstream, then
make a single command to pull everything and update
