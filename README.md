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

2. **Applying Dark Theme for GTK Applications in i3**: Here is the [reference](https://wiki.archlinux.org/title/GTK#Configuration_tools). `sudo apt install gnome-tweaks` in my case. Then can open it with `DMenu` or launch from terminal with: `gnome-tweaks`. However, this did not change the theme of `gnome-control-centre` for me.
    - **Understanding GTK Versions**: Your system can have multiple versions of GTK (GTK 2, GTK 3, GTK 4), each serving different applications. GTK (GIMP Toolkit) is a toolkit for creating graphical user interfaces, widely used in Linux applications. GTK 2 is older and less commonly used, GTK 3 is prevalent in many current applications, and GTK 4 is the latest version.
    - **Setting Dark Theme**: If GNOME applications like `gnome-control-center` don't adhere to the dark theme in i3, manually set the dark theme for GTK 3 applications. Edit `~/.config/gtk-3.0/settings.ini` and add:

    ```bash
    [Settings]
    gtk-application-prefer-dark-theme=1
    ```

    - **Theme Application**: After updating `settings.ini`, restart the applications or log out and back in for the changes to take effect. This approach is particularly useful when graphical tools like GNOME Tweaks don't apply settings as expected in a non-GNOME environment like i3.

This forces applications using GTK 3 to use a dark theme if available.

3. **Set Desktop Background**: use `nitrogen` for now.

## TODO

- install nerd font
- aliases / ssh keys
- make setup.sh determine the os, if mac, use brew, if ubuntu apt-get
- install zsh with powerline
