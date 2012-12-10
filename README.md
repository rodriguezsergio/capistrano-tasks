capistrano-tasks
================
Included in this repo are:
  - A MySQL backup task to be run on AWS EC2 Instances
  - A pruning task that will keep:
    + snapshots from the last 7 days
    + one weekly snapshot
    + and one monthly snapshot.

This script will keep the oldest snapshot within each week/month. If run daily under crontab, you will have weekly Monday snapshots in addition to a snapshot from the first of the month.

You can set up your configuration within aws.yml and config/ec2config.rb.