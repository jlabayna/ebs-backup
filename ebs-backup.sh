#!/bin/sh

alias error='echo 1>&2'

# Check if rsync is installed as a safety measure in case of incorrect
# installation.
# TODO: Remove me if non-exitance of rsync won't cause issue.
if ! command -v rsync >/dev/null; then
  error "Please install rsync(1)"
  exit 1
fi
