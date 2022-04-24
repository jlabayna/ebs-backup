# ebs-backup

`ebs-backup(1)` is a shell script that backups up files onto an EBS volume on AWS

## TODO
- [ ] Documentation:
  - [ ] `rsync(1)` installation
  - [ ] `jq(1)` installation
- [ ] Rsync familiarity:
  - [ ] Backup files to a hard-coded directory
  - [ ] Restore files from a hard-coded directory
- [X] Configuration
  - [X] Specify region somehow
- [o] EC2:
  - [X] Start an identifiable AWS EC2 instance (for use with EBS)
  - [X] Attach EBS volume(s)
  - [ ] Mount EBS volume(s)
  - [ ] Close specific AWS EC2 instance
- [o] EBS Management:
  - [X] Create volumes if they don't exist
  - [X] Find created volumes
  - [ ] Format volume if not-yet-formatted
- [ ] Edge cases:
  - [ ] Out of inodes
  - [ ] Backup is too big
