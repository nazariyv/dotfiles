# Dotfiles for quick new machine set up

to test with a docker container, run:

`./test-setup.sh`

# How To Run On A Clean Prod Machine

1/ clone this repo

`git clone --recursive https://github.com/nazariyv/dotfiles.git`

2/ run the setup script

`sudo ./setup.sh`

progress gets written to `/var/tmp/setup_state`, so it's possible to check the progress by running

`ls -l /var/tmp/setup_state`

also note, that it's fine to re-run `sudo ./setup.sh`, it will pick up from where it left off
