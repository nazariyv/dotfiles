# Dotfiles for quick new machine set up

to test with a docker container, run:

`./test-setup.sh`

on a clean machine, git clone this whole repo (then pull the submodule `git submodule update --init --recursive`) and run `sudo ./setup.sh` normally

it will restart the machine

if there are no updates to progress (`ls -l /var/tmp/setup_state`), run `sudo ./setup.sh` again (it will pick up from where it left off)
