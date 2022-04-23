# ebs-backup

`ebs-backup(1)` is a shell script that backups up files onto an EBS volume on AWS

## TODO
- [ ] Documentation:
  - [ ] `rsync(1)` installation
  - [ ] `jq(1)` installation
- [ ] Rsync familiarity:
  - [ ] Backup files to a hard-coded directory
  - [ ] Restore files from a hard-coded directory
- [ ] Configuration
- [ ] AWS (simple):
  - [X] Start an identifiable AWS EC2 instance (for use with EBS)
  - [ ] Close specific AWS EC2 instance
- [ ] EBS Management:
  - [ ] Create volumes if they don't exist
- [ ] Edge cases:
  - [ ] Out of inodes
  - [ ] Backup is too big
