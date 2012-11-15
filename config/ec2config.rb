# SSH Setup
#-------------------------------------------------------------
set :user, 'user'  
set :use_sudo, false
ssh_options[:keys] = ['/path/to/.ssh/pem.file']

# AWS Setup
#-------------------------------------------------------------
set :inst_id, 'i-123456789'
set :mntpoint, '/dev/sdh'
set :mntdir, '/dir'

# MySQL Login Config
#-------------------------------------------------------------
set :db_user, 'user'
set :db_password, 'pass'

# MySQL Servers
#-------------------------------------------------------------
role :db, 'ec2.AWS.address', :primary => true
set :lineage, 'MySQL-Slave1'

# Purge Script Variables
#-------------------------------------------------------------
set :dryrun, true

set :tagkey, 'AutoSnapshot' 
set :tagvalue, 'VALUE' # Not used by default, but can be used in place of :tagkey

set :dayofwk, 1
# For Weekly Snapshots. Choose which day of the week you would like to keep. 0 == Sunday

set :months_to_keep, 6
# For Monthly Snapshots, only the oldest snapshot from that month is kept.