#!/usr/bin/perl

# this script mounts media. It is used by udev, via a trigger script, so that
# udev does not hang or block: udev calls must finish INSTANTLY.  
# The trigger script is necessary, it is udev_mount_trigger.pl

# Q: what if the filesystem is already mounted, or the mount point is being used?
# A: 2017-03-09 any mounting over the top fails in step 0.1

use common::sense; 
use feature 'signatures';                                                       
no warnings 'experimental::signatures' ;                                        
                                       
my $thisProgName		= "udev_mount"; 
my $temp_mp2ln          = "/tmp/tmpfile_delme";  
my $logfile             = "/var/log/userspace/udev.log";
# takes one parameter, the mountpoint
my $linkMakingProgram	= "/usr/local/bin/link_mount_to_mnt_dir.pl"; 
my $mountPoint2LinkFile  = "/media/linksToMountpoints.lst";

my $MOUNT_CMD    = "/usr/bin/sudo /bin/mount " ;
my $UMOUNT_CMD   = "/usr/bin/sudo /bin/umount " ;
my $NTFSFIX_CMD  = "/usr/bin/sudo /bin/ntfsfix " ;
my $UMOUNT_PROG	 = "/usr/local/bin/udev_umount.pl"; 
my $GREP_CMD     = "/bin/grep ";
my $AWK_CMD      = "/usr/bin/awk ";
my $XMESSAGE_CMD = "DISPLAY=:0 /usr/bin/xmessage ";
my $LSOF_CMD     = "/usr/bin/lsof ";
my $KILL_CMD	 = "/usr/bin/kill "; 


# commandline: 
# {ID_FS_TYPE} {mount_options} /dev/%k {mount_dir_name}

my $device_type        = $ARGV[0];		# ntfs, .....
my $mount_options      = $ARGV[1];		# rw,utf8,uid=1000,gid=1000,umask=002 ...
my $partition_node     = $ARGV[2];		# /dev/sdX
my $mount_point        = $ARGV[3];		# /media/bbbbbbb
chomp( $device_type, $mount_options, $partition_node, $mount_point);
$mount_point           =~ s/\/$//; 		# strip trailing '/'

my $mount_type;
$mount_type="ntfs-3g" if ($device_type eq "ntfs");
$mount_type="vfat"    if ($device_type eq "vfat");



# ===== subroutines =================================================================





my $MAX_RMDIR_TRIES = 5;
my $INTER_RMMOUNTPOINT_SLEEP_SECS = 1; 
sub remove_mountpoint_dir{
	my $mp = shift; 
	`echo \"Removing the mount dir $mp\" >>g; $logfile`;
	my $rmMountDirCount = 0; 
	my $secs = 0;
	my $successfulUmount = 0; 
	my $mountpoint_existed = 0; 
	while ( -d $mp ) {
		$mountpoint_existed = 1; 
		$rmMountDirCount++; 
		my $retVal = `/bin/rmdir $mp  2>&1   > /dev/null`; 
		if ($retVal == 0){
			$successfulUmount=1; 
			last;
		}; 
		last
			if ($rmMountDirCount >= $MAX_RMDIR_TRIES); 
		sleep $INTER_RMMOUNTPOINT_SLEEP_SECS; 
		$secs += $INTER_RMMOUNTPOINT_SLEEP_SECS;
	}

	# report on what happened
	if ( 0 == $mountpoint_existed) {			# mountpoint didn't exist
		`echo "When trying to remove the mountpoint $mp, it had already been removed\n" >> $logfile`; 
	}
	elsif ($rmMountDirCount < $MAX_RMDIR_TRIES) {	# success rmdir the mountpoint 
		`echo \"Took $rmMountDirCount attempts to remove the $mp dir ($secs seconds)\n \"								>> $logfile`; 
	} else {
		`echo \"FAILED in $rmMountDirCount attempts to remove the $mp dir ($secs seconds)\n \"								>> $logfile`; 
		`$XMESSAGE_CMD "Could not remove the $mp mount point dir after $rmMountDirCount attempts.  \nPlease investigate.\n" `; 
	}
}





sub remove_mounting_programs{
	my $mp = shift; 

# ps -a | grep $mount_point | grep /dev
# 4071 ?        Ss     0:46 /sbin/mount.ntfs-3g /dev/sdi3 /media/200GB_downloadTorrent -o rw,uid=1000,gid=1000,umask=011,big_writes<Paste>

# NOTE: do NOT kill this program itself (I was killing this program!) 

	my @mountingProgramsPIDs = `/bin/ps -ax | $GREP_CMD $mount_point | $GREP_CMD "/dev/" | $GREP_CMD -v "grep" | $GREP_CMD -v $thisProgName | $AWK_CMD '{print \$1}' `; 
	chomp @mountingProgramsPIDs; 
	
	foreach my $pidToKill (@mountingProgramsPIDs) {
		`$KILL_CMD $pidToKill `; 
	}
}





sub unlink_links_to_the_mountpoint( $mp ){
	my @ln_from = `$GREP_CMD -v "^#" $mountPoint2LinkFile | $GREP_CMD $mp |  $AWK_CMD \'{print \$1}\'`;
	chomp (@ln_from);
	foreach my $this_lnFrom (@ln_from) {
		# this is safe as the links can only come from the file
		next unless -e $this_lnFrom; 
		my $unlinkFail = `unlink $this_lnFrom 2> /dev/null `;
		my $logMsg = `/usr/local/bin/datetime`; chomp $logMsg; 
		$logMsg .= "\n"; 
		$logMsg = "unlinked $this_lnFrom \n " 
			if (! $unlinkFail ) ;
		# also remove any dirs where links TO the mountpoint should be (eg /mnt/someLink as a dir)
		my $rmdirFailed = `rmdir $this_lnFrom 2> /dev/null `; 
		$logMsg .= "removed a DIR at $this_lnFrom (should have been a link)\n"  
			if (! $rmdirFailed); 
		`echo $logMsg >> $logfile `; 
	}
}





sub check_parameters($device_type, $mount_options, $partition_node, $mount_point)
{
    # are the parameters OK?
    my $goodParams =
         ( ( $device_type =~ /ntfs/ ) || ( $device_type =~ /vfat/ ) )
      && ( $mount_options =~ /gid/ )
      && ( $partition_node =~ /\/dev\// )
      && ($mount_point);
	
	  # problems w/ params --> fail, exit
    if ( !$goodParams ) {    
        my $timestamp = `/usr/local/bin/datetime`;
        chomp $timestamp;
        my $logMsg =
            "\n\n$timestamp \n "
          . "Bad parameters passed to $0\n "
          . "Parameters:\ndevice_type: \"$device_type\" mount_options: \"$mount_options\" partition_node: \"$partition_node\" mount_point: \"$mount_point\" \n"
          . "Exiting from $0, not mounting $mount_point\n";
        `echo $logMsg >> $logfile `;
		my $xmMsg = "Bad parameters passed to /usr/local/bin/udev_mount.pl\n" 
		.	"Parameters:\n  "
		.	"device_type: $device_type mount_options: $mount_options "
		.	"partition_node: $partition_node mount_point: $mount_point \n "
		.	"NOT MOUNTING\n ";
		`$XMESSAGE_CMD $xmMsg `; 
        die 1;
    }

	# params all OK
    else {                   
        my $timestamp = `/usr/local/bin/datetime`;
        chomp $timestamp;
        my $logMsg = "\n\n$timestamp  \n "
          . "Running /usr/local/bin/udev_mount.pl device_type:\"$device_type\" mount_options:\"$mount_options\" partition_node:\"$partition_node\" mount_point:\"$mount_point\" \n ";
        `echo $logMsg >> $logfile `;
        `$XMESSAGE_CMD "Mounting $mount_point" `;
    }
}





sub check_for_real_dir_at_mount_point( $mount_point ) {

    # 0.1 is there a REAL directory at the mount point?
    my $mount_error    = 0;
    my $tempDirListing = `ls -1b $mount_point 2>/dev/null `;
    chomp $tempDirListing;
    my $mount_error += scalar( $tempDirListing =~ /\w{3,}/ );
    if ($mount_error) {

        # Problem: this message does NOT appear when running from udev.
        # 			it only appears when this script is run directly.

		my $xmMsg = "Can not mount $partition_node at $mount_point because $mount_point already exists\n" 
		.	"Remove the device, FIX THIS, and reinstall." ;
		`$XMESSAGE_CMD $xmMsg`; 
		my $timestamp = `/usr/local/bin/datetime`; chomp $timestamp;
        my $logMsg =
		"\n$timestamp\n$mount_point already occupied by a real filesystem."
		.	"Must be fixed rather than mounted over\n";
        `echo $logMsg >> $logfile`;
        die 0;
    }
}




# ====== main program ==================================================================

require IPC::System::Simple;

# 0.  unlink any thing mounted at the mountpoint
check_for_real_dir_at_mount_point( $mount_point ); 
# the umount prog warns rather than deletes, so to 
# force removals, delete progs and links first
eval { require "$UMOUNT_PROG $mount_point  1 "} ;  # a safe way to run a perl program

# try to limit ntfs problems: no proper fsck type solution available 
my $retVal = system("$NTFSFIX_CMD "." $partition_node ")  
	if ($device_type eq "ntfs");

# 1. make the mountpoint dir
`/bin/mkdir -p $mount_point `;
`/bin/chown me.me $mount_point`; 
`/bin/chmod g+rwx $mount_point`; 

# 2. call the mount command using the parameters passed into this script
my $runCmd = "/usr/bin/sudo /bin/mount -t $mount_type    -o $mount_options   $partition_node   $mount_point"; 
`$runCmd`;
my $timestamp = `/usr/local/bin/datetime`; chomp $timestamp;
my $logMsg = "\n$timestamp \n$runCmd\n" ; 
`echo \"$logMsg\" >> $logfile`;

# 3. make links to the mountpoint
`$linkMakingProgram $mount_point`;










