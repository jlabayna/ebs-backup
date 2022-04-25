#!/bin/sh

if [ "$(id -u)" != 0 ]; then
  echo >&2 "Run install script as root."
  exit 1
fi

if ! cp ebs-backup.sh /usr/bin/ebs-backup; then
  echo >&2 'Failed to copy script to /usr/bin/'
  exit 1
fi

if ! cp ebs-backup.man /usr/share/man/man1/ebs-backup.1.gz; then
  echo >&2 'Failed to copy man pages'
  exit 1
fi

