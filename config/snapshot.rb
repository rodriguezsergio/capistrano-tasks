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
        
    # Filters out all AWS resources not tagged with 'tagkey' (OR 'tagvalue')
    snapswithtag = @ec2.tags.filter('key', tagkey).map(&:resource).sort_by(&:start_time)
        
    #------------------------------------------------------------
        
    # Sorts snapshots
    daily = []
    weekly = []
    monthly = []
        
    # Which snapshots are being kept/deleted?        
    day_keep = []
    week_keep = []    
    month_temp = []
    month_keep = []
        
    purge = []
        
    #------------------------------------------------------------
        
    today = Time.now.to_date
    one_wk_ago = today - 7    
    this_month = today.month
    # Used for finding the oldest month to keep
    n_month_backups = months_to_keep - 1
       
    #------------------------------------------------------------
        
    # Group snapshots by age                                                 
        
    snapswithtag.each do |s|
        snaptime = s.start_time.to_date
            if snaptime > one_wk_ago
                daily.push(s)
            elsif ((snaptime <= one_wk_ago) && (snaptime.month == this_month))
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
            day_keep.push(s)
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
        puts
    end
        
        
    if !monthly.empty?
            
        monthly.each do |s|
            if (((today.months_ago(n_month_backups))..(today)) === s.start_time.to_date)
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
        
    puts "Keeping #{day_keep.count + week_keep.count + month_keep.count} snapshots.\n\n" 
        
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