# About

This little tool should help you with katello development. It makes virtual server configuration easy. It's basically a wrapper around virtual box with some useful tools.

Kvizer is a garble of "Katello virtualizer"

# Features

- virtual machines management, commands: run, stop, power-off, delete, clone
- automated creation of remote-enabled development machine from clean Fedora `kvizer build -s base`
- connecting to machines `kvizer ssh -m <part of a VM name>`
- automated CI `kvizer ci --git <git repo> --branch <a branch>` which does:
  - build katello rpms from given git and branch
  - install these rpms
  - runs katello-configure
  - run system tests
- machine hostnames are same as VM names
- auto-mounting of shared directories
  - `kvizer/remote_bin` for shared command line tools (commands are accessible on guest, the directory is added to path on guest) 
  - `kvizer/support` for other shared files
- platform independent (*nix systems only)
  - based on VirtualBox
- its all Ruby

# Architecture

All machines have access to outside world via NAT network. They are also placed on a private network created by Kvizer which is used to ssh connections.

*TODO* more documentation

## Shared folders

There are three shared folders: `redhat`, `remote_bin` and `support`. 

- `redhat` for git repositories with projects you would like to share with a virtual machine. 
- `remote_bin` is added to PATH on every machine so needed commands can be easily added to all kvizer virtual machines.
- `support` is used for support files. E.g. there is `.bash_profile` used by all kvizer virtual machines.

# Installation

## Dependencies

- latest VirtualBox > 4.2.4
- arp-scan

## Create katello base image

First you must create a base Fedora 16 virtual server. This will serve as origin image for other clones which you'll use for development.

- download image: `http://archive.fedoraproject.org/pub/fedora/linux/releases/16/Fedora/x86_64/iso/Fedora-16-x86_64-netinst.iso`
- create virtual machine named 'katello-base' in virtual box
- note that for katello virtual machine you should allocate ~40GB of diskspace, 1.5GB of RAM and 2 CPU cores is also a good option
- fill in these during installation
  - root password: katello 
    - minimal installation
    - Use `Customize now` and add packages:
      - Applications/editors
      - Servers/ServerConfigurationTools
      - BaseSystem/Base
      - BaseSystem/SystemTools
- create a snapshot of you virtual machine named "clean installation"
- install arp-scan on host (Kvizer actually uses this for detecting virtual machine ip address)

## Prepare Kvizer

- copy `bin/kvizer.template` to `bin/kvizer` and set your paths there, follow comments inside
- run `bundle install --path gems`
- configure Kvizer with `config.yml` by copying a template `config.template.yml`, follow comments inside
- add kvizer/bin to your PATH
- run `kvizer info` to test it, you should see list of your machines

### Setting up koji

*TODO*
 
## Creating base image

- run `kvizer build -s base`

## Run CI

- run `kvizer ci -b your_branch` to test if it builds, configures and runs system-tests successfully



