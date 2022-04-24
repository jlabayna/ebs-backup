#!/bin/sh

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

###
# AWS Instance Handling
###

# Aws key-pair name for ssh.
# Set to "" by deafult in case aws commands that
# need an ssh-key-pair somehow run without a
# specified key. Safe, since aws keys cannot be
# blank.
key=""


# SSH without host key checking or saving the new host
alias ssh-tmp='ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=10'


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

#TODO: Assume default region is in config if not specified

if [ $# -ne 2 ]; then
  fail "Bad number of parameters"
fi

key="$1"
zone="$2"

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
  fail "Failed to attach volume."
fi

# SSH may take time to setup, so wait 60 seconds.
# TODO: Set back to 60 seconds before release
secs=5
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
# TODO: Handle connection failure
if ! ssh-tmp "ubuntu@$iname" exit; then
# TODO: Kill instnaces when ssh fails, or retry before finally killing
  fail "SSH connection took too long."
fi
echo "Connection succeeded!"



###
# Terminate instnace
###

echo "Terminating instance..."
aws ec2 terminate-instances --instance-ids "$instance"
