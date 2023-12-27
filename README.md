# Dotfiles

Welcome to my dotfiles. To get started, execute

```bash
./setup.sh
```

next, run the ansible playbook

```bash
ansible-playbook ansible/main.yml --ask-become-pass
```

# Notes

1. **Changing Display Scaling in i3**: To adjust display scaling, edit `~/.Xresources` and set `Xft.dpi: 192` for 200% scaling. Merge changes with `xrdb -merge ~/.Xresources` and restart `i3` (`i3-msg restart`) to apply. This setting is particularly useful for high-resolution displays.

2. **Changing Default Theme To Dark**: Here is the [reference](https://wiki.archlinux.org/title/GTK#Configuration_tools). `sudo apt install gnome-tweaks` in my case. Then can open it with `DMenu` or launch from terminal with: `gnome-tweaks`.

## TODO

- install nerd font
- aliases / ssh keys
- make setup.sh determine the os, if mac, use brew, if ubuntu apt-get
- install zsh with powerline
