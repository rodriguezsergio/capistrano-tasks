require "rubygems"
require "active_support/core_ext/date/calculations"
require "aws"
require "mysql"
require "time"
require "date"

namespace :launch do

  #desc 'Login Credentials'
  task :aws_cfg, :roles => :db do
      
      config = YAML.load(File.read('aws.yml'))
      AWS.config(config)
      @ec2 = AWS::EC2.new

  end
    
    
  desc 'Backup EBS Volume'
  task :backup, :roles => :db do
    
    aws_cfg

    #Looks through all ec2 instances and selects the given instance object
    inst = @ec2.instances[inst_id]
    
    #Hash (key, value) = ("/dev/somedevice", EC2::Attachment Object)
    dev_vol = inst.block_device_mappings.fetch("#{mntpoint}").volume

    puts "#{Time.now}: Preparing to Snapshot #{dev_vol.id}"
    #Flush DB, Lock DB, XFS Freeze, and Snapshot Volume
    c = Mysql.new(inst.dns_name, db_user, db_password)
    c.query "FLUSH LOCAL TABLES"
    c.query "FLUSH TABLES WITH READ LOCK"
    c.query "SHOW MASTER STATUS"
    run "sync"
    run "sudo xfs_freeze -f #{mntdir}"
    
    time = Time.new
    
    begin
      #Class: AWS::EC2::Snapshot - #create_snapshot
      new_snapshot = dev_vol.create_snapshot("Auto Snapshot of #{lineage} from #{dev_vol.id} @ #{Time.now}")
         
      new_snapshot.tag('Name', :value => "#{lineage}")
      new_snapshot.tag('Timestamp', :value=> "#{Time.now}")
      new_snapshot.tag('Mountpoint', :value => "#{mntpoint}")
      new_snapshot.tag('AutoSnapshot', :value => "True")
      
    rescue
      puts $!, $@
    end
      
    run "sudo xfs_freeze -u #{mntdir}"
    c.query "UNLOCK TABLES"
    c.close
    puts "DONE"
      
  end   

  desc 'Purge Old Snapshots'
  task :purge, :roles => :db do
        
    aws_cfg
        
    # Filters out all ec2 snapshots not tagged with both "AutoSnapshot" AND Name: "lineage"
    snapswithtag = @ec2.snapshots.tagged(tagkey).tagged("Name").tagged_values(lineage).map.sort_by(&:start_time)
        
    #------------------------------------------------------------
        
    # Sorts snapshots
    daily = []
    weekly = []
    monthly = []
        
    # Which snapshots are being kept/deleted?
    week_keep = []    
    month_temp = []
    month_keep = []
        
    purge = []
        
    #------------------------------------------------------------
        
    today = Time.now.to_date
    one_wk_ago = today - 7 
       
    #------------------------------------------------------------
        
    # Group snapshots by age                                                 
        
    snapswithtag.each do |s|
        snaptime = s.start_time.to_date
            if snaptime > one_wk_ago
                daily.push(s)
            elsif ((snaptime <= one_wk_ago) && (snaptime >= today.weeks_ago(weeks_to_keep)))
                weekly.push(s)
            else
                monthly.push(s)
            end
    end
        
    #------------------------------------------------------------
      
    # Filter snapshots
        
    if !daily.empty?
        puts "Keeping snapshots from within the last week."
            
        daily.each do |s|
            puts "#{s.start_time}: #{s.id} from #{s.volume_id}"
        end
        puts
    end
        
        
    if !weekly.empty?
        puts "Keeping the following weekly snapshots."
            
        weekly.each do |s|
            snapday = s.start_time.wday
            if snapday == dayofwk
                week_keep.push(s)
                puts "#{s.start_time}: #{s.id} from #{s.volume_id}"
            else
                purge.push(s)
            end
        end
        
        weekly_hash = Hash[purge.group_by{|s| s.start_time.year}.map{|year, snapshots| [year, snapshots.group_by{|s| s.start_time.to_date.cweek}]}]

        # Ensure that at least 1 weekly snapshot is kept        
        weekly_hash.each_value  do |week|
                week.each_value do |snaparray|
                        if snaparray.count == 1
                                snaparray.each do |s|
                                        puts "#{s.start_time}: #{s.id} from #{s.volume_id}"
                                        week_keep.push(s)
                                        purge.delete(s)
                                end
                        end
                end
        end
        puts
    end
        
        
    if !monthly.empty?
            
        monthly.each do |s|
            if (s.start_time.to_date >= (today.months_ago(months_to_keep).beginning_of_month))
                month_temp.push(s)
            else 
                purge.push(s)
            end
        end
            
        h = Hash[month_temp.group_by{|s| s.start_time.year}.map{|year, months| [year, months.group_by{|s| s.start_time.month}]}]
            
        h.each_value do |month|
            month.each_value do |array|
                first = array.first
                    
                    array.each do |array_item|
                        if array_item == first
                            month_keep.push(array_item)
                        else
                            purge.push(array_item)
                        end
                    end
            end
        end
        puts "Keeping the following monthly snapshots."
            
        month_keep.each do |s|
            puts "#{s.start_time}: #{s.id} from #{s.volume_id}"
        end
        puts
    end
        
    puts "Keeping #{daily.count + week_keep.count + month_keep.count} snapshots.\n\n" 
        
    #------------------------------------------------------------
        
    # Delete snapshots
        
    puts "Deleting the following #{purge.count} snapshots."
    puts "----------DRY RUN----------\n" if dryrun == true
        
    purge.each do |s|
        puts "#{s.start_time}: #{s.id} from #{s.volume_id}"
        if dryrun == false
            s.delete
        end
    end
        
  end

end