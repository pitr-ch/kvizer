# Kvizer

## About

This little tool should help you with katello development. It makes virtual machines configuration easy. It's basically a wrapper around virtual box with some useful tools.

Kvizer is a garble of "Katello virtualizer"

Bugs, planed enhancements, questions can be found on [github issues](https://github.com/pitr-ch/kvizer/issues).

## Features

- virtual machines management, commands: run, stop, power-off, delete, clone
- automated creation of remote-enabled development machine from clean Fedora `kvizer build-base --vm clean-f16 --name katello-base`
- connecting to machines `kvizer ssh -m <part of a VM name>`
- runs *complete test cycle* with one command `kvizer ci --git <git repo url/local> --branch <a branch>` which does:
  - *build* katello rpms from given git and branch *locally* or in *Koji*
  - *install* these rpms
  - runs *katello-configure*
  - run *system-tests*
- machine hostnames are same as VM names
- auto-mounting of shared directories
  - `kvizer/remote_bin` for shared command line tools (commands are accessible on guest, the directory is added to path on guest) 
  - `kvizer/support` for builds and other shared files
- platform independent-ish (*nix systems only)
  - based on VirtualBox
- its all Ruby

## Architecture

All machines have access to outside world via NAT network. They are also placed on a private network created by Kvizer which is used to ssh connections.

Kvizer uses as basic building blocks jobs which are defined in `jobs.rb` (other paths can be added in configuration). Jobs are organized into sequential collections which are used to build a development machine and to run a `ci` command.

### Typical VM workflow is:

- clean-fedora16 
  - snapshots: "clean installation"
- katello-base 
  - cloned from clean-fedora16 at "clean installation" snapshot
  - used as a base for cloning other machines
  - snapshots: clean installation, base, update, add-user, install-guest-additions, setup-shared-folders, install-htop, install-packaging, install-katello-nightly, configure-katello, turnoff-services, relax-security, setup-development"
- katello-dev[\d] 
  - cloned from katello-base at "setup-development" snapshot
- ci-[a-branch-name]
  - cloned from katello-base at "install-packaging" snapshot
  - used for running complete test cycles

### Shared folders

There are three shared folders: `redhat`, `remote_bin` and `support`. 

- `redhat` for git repositories with projects you would like to share with a virtual machine. 
- `remote_bin` is added to PATH on every machine so needed commands can be easily added to all kvizer virtual machines.
- `support` is used for support files. E.g. there is `.bash_profile` used by all kvizer virtual machines.

## Installation

### Dependencies

- latest VirtualBox > 4.2.4
- arp-scan

### Create katello base image

First you must create a base Fedora 16 virtual server. This will serve as origin image for other clones which you'll use for development.

- download image: `http://archive.fedoraproject.org/pub/fedora/linux/releases/16/Fedora/x86_64/iso/Fedora-16-x86_64-netinst.iso`
- create virtual machine named 'clean-f16' in virtual box
- note that for katello virtual machine you should allocate ~40GB of diskspace, 1.5GB of RAM and 2 CPU cores is also a good option
- fill in these during installation
  - root password: katello 
    - minimal installation
    - Use `Customize now` and add packages:
      - Applications/editors (not for RHEL?)
      - Servers/ServerConfigurationTools
      - BaseSystem/Base (not for RHEL?)
      - BaseSystem/SystemTools
- create a snapshot of you virtual machine named "clean installation"
- install arp-scan on host (Kvizer actually uses this for detecting virtual machine ip address)

### RHEL based image

- tested with RHEL 6.3
- during minimal installation choose Servers/ServerConfigurationTools and BaseSystem/SystemTools
- make sure networking is started on boot (/etc/sysconfig/networking-scripts/* ONBOOT)
- enable PermitRootLogin in sshd config
- create snapshot "clean installation"

### Prepare Kvizer

- copy `bin/kvizer.template` to `bin/kvizer` and set your paths there, follow comments inside
- run `bundle install --path gems`
- configure Kvizer with `config.yml` by copying a template `config.template.yml`, follow comments inside
- add kvizer/bin to your PATH
- run `kvizer info` to test it, you should see list of your machines

#### Setting up koji

- copy `support/koji/katello-config.template` to `support/koji/katello-config`
- copy your certificate for koji to `support/koji/`, e.g. `support/koji/pchalupa.pem`
- update path to this certificate in `support/koji/katello-config`
- now you can build in koji with kvizer from its machines
 
### Creating base image

Run `kvizer build-base --vm clean-f16 --name katello-base` to create base development image from cleanly installed machine.

## Cloning a machine for development

- Run `kvizer clone --vm a_base --name katello-dev --snapshot setup-development` to clone a machine for development. 
- Run the machine `kvizer run --vm katello-dev`.
- Setup Katello on a host machine to connect to the development machine (`kvizer info` will help you to find correct ip).
- Now you can run Katello process locally against services on a development machine.

## Run CI

- run `kvizer ci -b your_branch` to test if it builds, configures and runs system-tests successfully
- to use Koji for RPM build add `--use-koji` option
- run `kvizer ci --help` for more information



