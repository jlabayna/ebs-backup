#!/bin/sh

# Rationale for functions in here rather than a
# separate file:
# - User can just put this script anywhere
# - Minimize chance of breakage (no other files
#   that need to be anywhere specific)



###
# Error Handling
###

alias error='echo 1>&2'

fail() {
  error "$1"
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

if [ $# -ne 1 ]; then
  fail "Bad number of parameters"
fi

key="$1"

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
subnet=$(aws ec2 describe-subnets | jq -r '.Subnets[] | select( .Tags[]? | select(.Value == "dualstack")).SubnetId')
sg=$(aws ec2 describe-security-groups | jq -r '.SecurityGroups [] | select( .GroupName == "dualstack").GroupId')
if ! startup_json=$(aws ec2 run-instances --key-name "$key" --image-id ami-08b4ee602f76bff79 \
  --instance-type t2.micro  \
  --subnet-id "${subnet}"   \
  --security-group-ids "${sg}")
then
  fail "Failed to create instnace!"
fi

# Id of the temporary instance to perform backup to
instance=$(jq -nr --argjson data "$startup_json" '$data.Instances[].InstanceId')

# Wait for ec2 instance to come up
echo "Waiting for EC2 instance \"$instance\" to start running"
aws ec2 wait instance-running --instance-ids "$instance"

# SSH may take time to setup, so wait 60 seconds.
secs=60
while [ $secs -gt 0 ]; do
  # Erase previous line and move cursor to beginning of current line
  printf "Seconds til SSH is probably active: %d\033[0K\r" "$secs"
  sleep 1
  secs=$((secs-1))
done

echo "SSH should be active. Continuing script..."

# Instance public dns name
iname=$(aws ec2 describe-instances --instance-ids "$instance" | \
  jq -r ".Reservations[].Instances[].PublicDnsName")

echo "$iname"
