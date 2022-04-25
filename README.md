# ebs-backup

`ebs-backup(1)` is a shell script that backups up files onto an EBS volume on AWS

## TODO
- [X] Documentation:
  - [X] `rsync(1)` installation
  - [X] `jq(1)` installation
- [X] Rsync familiarity:
  - [X] Backup files to a hard-coded directory
  - [X] Restore files from a hard-coded directory
- [X] Configuration
  - [X] Specify region somehow
- [X] EC2:
  - [X] Start an identifiable AWS EC2 instance (for use with EBS)
  - [X] Attach EBS volume(s)
  - [X] Mount EBS volume(s)
  - [X] Close specific AWS EC2 instance
- [X] EBS Management:
  - [X] Create volumes if they don't exist
  - [X] Find created volumes
  - [X] Format volume if not-yet-formatted
- [X] Edge cases:
  - [X] Out of inodes
  - [X] Backup is too big

## Installation

1. If `rsync(1)` is not installed, then install it using the following instructions based on your OS (`#` indicates that the following command must be run with root permissions):
  - Arch:
    - `# pacman -S rsync`
  - CentOS, Fedora, Red Hat, and other `rpm`-based distributions:
    - `# yum install rsync`
  - MacOS:
    - `# brew install rsync`
  - Ubuntu:
    - `# apt-get install rsync`
  - Other system not listed:
    1. Download the latest version from [https://rsync.samba.org/](https://rsync.samba.org/).
    2. Run:

       `$ tar xvzf file`
       
       where `file` is the file downloaded from the `rsync` website.
    3. Follow the instructions in the `INSTALL.md` in the extracted directory.
2. If `jq(1)` is not installed, then install it using the following instructions based on your OS:
  - Arch:
    - `# pacman -S jq`
  - Debian/Ubuntu:
    - `# apt-get install jq`
  - Fedora:
    - `# dnf install jq`
  - FreeBSD:
    - `# pkg install jq` if you want to install from a pre-built binary package.
    - `make -C /usr/ports/textproc/jq install clean` to install the `jq(1)` port from source.
  - OS X:
    - `# brew install jq` if you use [Homebrew](http://brew.sh/)
    - `# port install jq` if you use [MacPorts](https://www.macports.org/)
  - openSUSE:
    - `# zypper install jq`
  - Solaris:
    - `# pkgutil -i jq` in in [OpenCSW](https://www.opencsw.org/p/jq) for Solaris 10+, Sparc and x86.
  - If the above commands do not work, or your system is not listed:
    - Follow the official download instructions [here](https://stedolan.github.io/jq/download/)
    - Make sure that `jq` is visible via the `$PATH`
3. `ebs-backup` can (probably) run in any directory, but it is probably most convenient to copy it to a directory listed in your `$PATH` variable.

   If you want to more permanently install `ebs-backup(1)`, then run `install.sh` (from the tar archive that contained `ebs-backup(1)`) as root.
