# Installation

This little tool should help you with katello development. It makes virtual server configuration easy. It's basically a wrapper
around virtual box with CLI.

# Howto

## Create katello base image

First you must create a base Fedora 16 virtual server. This will serve as origin image for other clones which you'll use for development.

- download image: `http://archive.fedoraproject.org/pub/fedora/linux/releases/16/Fedora/x86_64/iso/Fedora-16-x86_64-netinst.iso`
- create virtual machine in virtual box, fill in these during installation
  - root password: katello 
    - minimal installation
    - Use `Customize now` and add packages:
      - Applications/editors
      - Servers/ServerConfigurationTools
      - BaseSystem/Base
      - BaseSystem/SystemTools
- install arp-scan on host (kvizer actually uses this for detecting virtual machine ip address)

## Creating base image

- configuration is placed in `config.yml`, you can use config.template.yml as a template
- add kvizer/bin to PATH
- create a snapshot of you virtual machine named "clean installation"
- run `kvizer execute -s base`

note that for katello virtual machine you should allocate ~40GB of diskspace, 1.5GB of RAM and 2 CPU cores is also a good option

# Features

- automates building of remote-enabled development machine from clean fedora
- automates CI by `kvizer ci --git <git repo> --branch <a branch>` which does:
  - build katello rpms from given git and branch
  - install these rpms
  - runs katello-configure
  - run system tests
- platform independent (*nix systems only)
  - based on VirtualBox

# TODO rest of the Documentation
