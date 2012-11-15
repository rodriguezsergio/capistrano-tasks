capistrano-tasks
================
Included in this repo are:
  - A MySQL backup task to be run on AWS EC2 Instances
  - A pruning task that will keep:
    + snapshots from the last 7 days
    + weekly snapshots based on a user-specified weekday
    + and one monthly snapshot. The script is written to grab the oldest snapshot in the month. Presumably, this will end up keeping the snapshot from the first of the month if you're running this daily under crontab.