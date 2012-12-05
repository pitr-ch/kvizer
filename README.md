
# README

## Create katello base image
- download image: `http://archive.fedoraproject.org/pub/fedora/linux/releases/16/Fedora/x86_64/iso/Fedora-16-x86_64-netinst.iso`
- create virtual machine 
  - root password: katello 
    - minimal installation
    - Use `Customize now` and add packages:
      - Applications/editors
      - Servers/ServerConfigurationTools
      - BaseSystem/Base
      - BaseSystem/SystemTools

## Usage

- configure in `config.yml`
- Add bin to PATH and run `kvizer --help`

## Features

- automates building of remote-enabled development machine from clean fedora
- automates CI by `kvizer ci --git <git repo> --branch <a branch>` which does:
  - build katello rpms from given git and branch
  - install these rpms
  - runs katello-configure
  - run system tests
- platform independent (*nix systems only)
  - based on VirtualBox

## TODO Documentation
