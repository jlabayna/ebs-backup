#!/bin/sh

# Set program name now in case params shift or something
program="$0"
mode="$1"
key="$2"
zone="$3"

# Rationale for functions in here rather than a
# separate file:
# - User can just put this script anywhere
# - Minimize chance of breakage (no other files
#   that need to be anywhere specific)

###
# Error Handling
###

alias error='echo >&2'

fail() {
  error "$*"
  exit 1
}

usage() {
  echo "usage: $program b keyname zone file..."
  echo "       $program r keyname zone"
  exit 1
}

###
# AWS Instance Handling
###

# SSH without host key checking or saving the new host
alias ssh-tmp='ssh -q \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=10'

# Commands to issue over ssh (mainly mkfs and disk mounting.
# error() not defined on instance.
ssh_commands='echo "Making mountpoint..."
if ! mkdir mnt; then
  echo "Failed to make mountpoint" >&2
  exit 2
fi
sudo chown ubuntu:ubuntu mnt
if ! sudo mount /dev/xvdf mnt; then
  echo "Failed to mount backup volume"
  exit 3
fi'

terminate() {
  echo "Terminating instance..."
  aws ec2 terminate-instances \
    --instance-ids "$instance" >/dev/null
}

# r instead of a due to errors with home directory perms
# can't change times
restore() {
  rsync -crvzP \
    -e 'ssh -q -o StrictHostKeyChecking=no
      -o UserKnownHostsFile=/dev/null
      -o ConnectTimeout=10' \
    "ubuntu@$iname:/home/ubuntu/mnt/backup.0/" /
  terminate
  exit 0
}

###
# Check if necessary commands exist
###

# Check if rsync is installed as a safety measure in case of incorrect
# installation.
# TODO: Remove me if non-exitance of rsync won't cause issue.
if ! command -v rsync >/dev/null; then
  error "Please install rsync(1)"
  exit 1
fi

# jq is used to parse aws output
if ! command -v jq >/dev/null; then
  error "Please install jq(1)"
  exit 1
fi

# TODO: Maybe add a check for aws, even if that's assumed to be installed?

###
# Check for parameters
###

# TODO: Assume default region is in config if not specified
# Rationale for forcing user to give zone name:
# - User zone *may* change between backups

# If backing up, expect params b, keyname, zone and file...
if [ "$mode" = "b" ] && [ $# -ge 4 ]; then
  shift 3
# If restoring, expect params r, keyname, zone:
elif [ "$mode" = "r" ] && [ $# = 3 ]; then
  :
else
  usage
  exit 1
fi

###
# Check availability zone
###

# List of available zones
zone_info=$(aws ec2 describe-availability-zones \
  | jq -r '.AvailabilityZones[] | select(.State == "available") | .ZoneName')

# printf for portability in unforeseen cases
if ! printf "%s" "$zone_info" | grep -qFx "$zone"; then
  error "Given zone not available."
  error "Available zones:"
  fail "$zone_info"
fi

###
# Check if backup volume(s) exist(s)
###

echo "Checking for backup volume(s)..."

ebs_vol=$(aws ec2 describe-volumes \
  | jq -r \
    --arg zone "$zone" \
    '.Volumes[]
    | select(.AvailabilityZone == $zone and .Tags[].Key == "ebs_backup_vol")
    | .VolumeId')

if [ -z "$ebs_vol" ]; then
  echo "Backup volume(s) not detected!"
  printf "Do you want to create a new volume? [default: n] [y/n]: "
  read -r ans
  ans=${ans:-n}
  if [ "$ans" != "y" ]; then
    error "No backup volume available."
    fail "See \`man 1 ebs-backup\`"
  fi
  

  printf "What size volume do you want (in GiB)? [default: 1] [1-16384]: "
  read -r size
  size=${size:-1}
  if ! ebs_vol=$(aws ec2 create-volume \
    --availability-zone "$zone" \
    --size "$size" \
    --volume-type gp3 \
    --tag-specifications 'ResourceType=volume,Tags=[{Key=ebs_backup_vol,Value="1"}]' \
    | jq -r '.VolumeId'); then
    fail "Volume creation failed."
  fi

  ssh_commands="sudo mkfs.btrfs /dev/xvdf; $ssh_commands"
fi

###
# Start an ephemeral ec2 instance
###

# Credit: Jan Schaumann <jschauma@netmeister.org>
# (Modified a bit from source)
# Start a fedora instance IPv4/IPv6 dual stack
# Assumes configuration as descrived in:
# https://www.netmeister.org/blog/ec2-ipv6.html
# Since the user set a default key-pair, we will
# not specify a key-pair for the run-instnaces
# command.
echo "Starting a temporary EC2 instance..."
subnet=$(aws ec2 describe-subnets \
  | jq -r '.Subnets[] | select( .Tags[]? | select(.Value == "dualstack")).SubnetId')
sg=$(aws ec2 describe-security-groups \
  | jq -r '.SecurityGroups [] | select( .GroupName == "dualstack").GroupId')
# Login with user "ubuntu" 
# Switch to an ami with a smaller ebs volume later.
if ! startup_json=$(aws ec2 run-instances --key-name "$key" \
  --placement AvailabilityZone="$zone" \
  --image-id ami-0f593aebffc0070e1 \
  --instance-type t2.micro  \
  --subnet-id "${subnet}"   \
  --security-group-ids "${sg}"); then
  fail "Failed to create instnace!"
fi

# Id of the temporary instance to perform backup to
instance=$(jq -nr --argjson data "$startup_json" '$data.Instances[].InstanceId')

# Wait for ec2 instance to come up
echo "Waiting for EC2 instance \"$instance\" to start running..."
aws ec2 wait instance-running --instance-ids "$instance"


###
# Attach volume to ec2 instance
###

if ! aws ec2 attach-volume \
  --device "/dev/xvdf" \
  --instance-id "$instance" \
  --volume-id "$ebs_vol" >/dev/null 2>&1; then
  error "Failed to attach volume."
  terminate
  exit 1
fi

# SSH may take time to setup, so wait 20 seconds.
secs=20
while [ $secs -ge 0 ]; do
  # Erase previous line and move cursor to beginning of current line
  printf "Seconds til SSH is likely active: %d\033[0K\r" "$secs"
  sleep 1
  secs=$((secs-1))
done

# Newline, since timer reset cursor position to start of line with text
echo ""
echo "Testing SSH..."

# Instance public dns name
iname=$(aws ec2 describe-instances --instance-ids "$instance" \
  | jq -r ".Reservations[].Instances[].PublicDnsName")


# Test ssh connection
if ! ssh-tmp "ubuntu@$iname" exit; then
  error "SSH connection took too long."
  terminate
  exit 1
fi
echo "Connection succeeded!"


if [ "$mode" = "b" ]; then
  ssh_commands="$ssh_commands; if [ ! -e mnt/backup.0 ]; then
  mkdir mnt/backup.0
  fi
  rm -rf mnt/backup.1
  mv mnt/backup.0 mnt/backup.1"
fi

ssh-tmp "ubuntu@$iname" "$ssh_commands"

###
# Restore if in restoration mode
###

if [ "$mode" = "r" ]; then
  restore
fi

###
# Making sure that backup can occur
###

echo "<--- Data transfer calculations --->"

# Compare filesize and file count with limits.
# Btrfs limits:
# - 2^64 files
# Note the 4096 blocksize


files=$(for file in "$@"; do
  printf "%s" "$(realpath "$file")"
  echo ""
done)


available=$(ssh-tmp "ubuntu@$iname" stat -f -c"%a" mnt)
files_used=$(ssh-tmp "ubuntu@$iname" "du -a mnt | wc -l")

du_out=$(du -caB 4096 "$files")
needed=$(printf "%s" "$du_out" | awk 'END{print $1}')

num_files=$(printf "%s" "$du_out" | head -n -1 | wc -l)
files_left=$(echo "18446744073709551616 - $num_files - $files_used" | bc)

printf "Needed blocks: %s\nAvailable blocks: %s\n" "$needed" "$available"
if [ "$(echo "$available - $needed > 0" | bc)" = "0" ]; then
  error "Not enough free blocks on backup volume!"
  terminate
  exit 1
fi

printf "Files to copy: %s\nNumber of files allowed: %s\n" "$num_files" "$files_left"
if [ "$(echo "18446744073709551616 - $num_files - $files_used" | bc)" = "0" ]; then
  error "Too many files will be backed up."
  terminate
  exit 1
fi


echo "<------>"

###
# Copy files to backup
###

# -a: Archive mode ensures symbolic links, attributes,
#     perms, etc. are preserved.
# -v: Verbose
rsync -avRP --delete \
  -e 'ssh -q -o StrictHostKeyChecking=no
          -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=10' \
  --link-dest=../backup.1 \
  "$files" \
  "ubuntu@$iname:/home/ubuntu/mnt/backup.0"

###
# Terminate instnace
###

terminate
exit 0
