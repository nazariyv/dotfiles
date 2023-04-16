#!/bin/bash
sudo apt-get update
sudo apt-get install software-properties-common
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt-get --yes install ansible

# Install git
sudo apt-get --yes install git

# Create ~/git folder if it doesn't exist
mkdir -p ~/git

# Clone the dotfiles repository
dotfiles_repo="https://github.com/nazariyv/dotfiles.git"
git clone "$dotfiles_repo" ~/git/dotfiles
