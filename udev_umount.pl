#!/usr/bin/perl

# this script UNmounts media. 
#
# It is used by udev, via a trigger script, so that
# udev does not hang or block: udev calls must finish INSTANTLY.  
# The trigger script is necessary, it is udev_umount_trigger.sh
#
#	called as:
#		udev_umount.pl		<mount_point>
#		udev_umount.pl		/media/someDir
#


use common::sense; 
use feature 'signatures';                                                       
no warnings 'experimental::signatures' ;                                        

my $thisProgName 		 = "udev_umount"; 
my $mountPoint2LinkFile  = "/media/linksToMountpoints.lst";
my $logfile              = "/var/log/userspace/udev.log";
my $mount_point          = $ARGV[0];		# /media/sldkfjla
$mount_point             =~ s/\/$//; 				# strip trailing '/'
chomp($mount_point); 
# if a '1' is passed, then only warn about prograams using the mountpoint, else kill. 
my $kill_warn			 = ($ARGV[1] && ($ARGV[1] == 1)) ? "warn" : "kill"; 

my $MOUNT_CMD    = "/usr/bin/sudo /bin/mount " ;
my $UMOUNT_CMD   = "/usr/bin/sudo /bin/umount --all-targets --lazy " ;
my $GREP_CMD     = "/bin/grep ";
my $AWK_CMD      = "/usr/bin/awk ";
my $XMESSAGE_CMD = "DISPLAY=:0 /usr/bin/xmessage ";
my $LSOF_CMD     = "/usr/bin/lsof ";
my $KILL_CMD	 = "/usr/bin/sudo /bin/kill "; 

my $INTER_RMMOUNTPOINT_SLEEP_SECS = 1;
my $MAX_RMDIR_TRIES               = 3;

my $mount_point_is_active         = 0; 
# 0. 	sync
# this is actually wrong. the device has already been removed
# so it is too late to call sync
`sync`;  


sub check_program_parameters ($mp) {
	my $badParams = 0; 
	my $bad_argv2 = 0; 
	my @validMountPoints;
	my $timestamp = `/usr/local/bin/datetime`; chop $timestamp;
	my $error = (); 

	# impossible number of parameters
	if ((@ARGV < 1) or (@ARGV > 2)) {
		my $logMsg = "\n$timestamp\n"  
		.	"either 1 or 2 parameters needed\n"; 
		`echo \"$logMsg\" >> $logfile `;
		$error = "Bad Parameters: need 1 or 2 parameters"; 
	}
	return $error if ($error); 

	# invalid mountpoint (param 1) 
   	# NOTE: This only checks if there is a link to be made to the mount point.
	#		as of 2017-04-07 I have made it that ONLY those with links in the 
	#		link_from_to file can be mounted
	if ($mp) {				
        @validMountPoints = 
			`$GREP_CMD -v "^#" $mountPoint2LinkFile | $GREP_CMD $mp |  $AWK_CMD \'{print \$2}\'`;
        chomp @validMountPoints;
		if (! @validMountPoints) {			
			my $logMsg = "\n$timestamp\n" 
			.	"Bad parameter passed to /usr/local/bin/udev_umount.pl" 
			.	"Parameters:\nmount_point: $mp  \n" ;
			`echo \"$logMsg\"		>> $logfile `;
		$error = "Invalid mountpoint: $mp"; 
		}
	}
	return $error if ($error); 

	# second parameter is not '1' if it exists
	if ($ARGV[1] && ($ARGV[1] != 1)){
		$error = "second parameter must be \"1\" if it exists"; 
		my $logMsg = "\n$timestamp\n"  
		.	"Bad parameter passed to /usr/local/bin/udev_umount.pl\n" 
		.	"Parameter 2 should be 1 or absent (Parameter 2 is $ARGV[1]) \n"; 
		`echo \"$logMsg\"		>> $logfile `; 
		$badParams = 1; 
	}
	return $error if ($error); 

	return; 
}


sub list_apps_active_on_mountpoint {
	# pass in a mount point
	# returns an array of "pid filepath" string that are of each app with an open file 
	# underneath that mountpoint
 	my $mp	=	shift; 
	
	my $adjMountPoint = ($mp  =~ s,/,\/,gr); 
	my @pidAndFile = `$LSOF_CMD 2>/dev/null | $GREP_CMD '$adjMountPoint' | $AWK_CMD '\{out=\$2; for(i=9;i<=NF; i++) \{out=out" "\$i\}; print out\}' | /usr/bin/sort -u` ;
	chomp @pidAndFile; 
	# lsof $2 : application
	# lsof $2 : pid
	# lsof $9 : file path
	# NOTE: no, the grep should NOT become part of the awk because it can't handle '/'
	# and if i/you/one tries, it gets REALLY ugly REALLY quickly

	return \@pidAndFile; 
}



sub warn_on_pid_file_list {
	# the passed in array must be
	# ["pid filepath", "pid filepath" ... ]
	my @pidAndFile	= shift ; 

	foreach (@pidAndFile) {
		(my ($pid, $file)) = split / /, $_; 
		my $appnName = `ps -q $pid -o comm=`; # returns the application's name
		chomp $appnName; 
		my $xmMsg = "Application: $appnName \nFile: $file \n\tis keeping the mount point $mount_point active. Please fix \nUnmounting regardless." ;
		`$XMESSAGE_CMD \"$xmMsg\" `; 
		$mount_point_is_active = 1; 
	}
}



sub ensure_to_umount_mountpoint{ 
	my $mp = shift ; 
	# 1.	unmount
	# this handles multiply-mounted devices (i.e /mount/dir/a_dev mounted three times)
	while (`$MOUNT_CMD | $GREP_CMD -o $mp`) {
		my $timestamp           = `/usr/local/bin/datetime`;
		chomp $timestamp;
		`echo \"\n\n$timestamp\"                      >> $logfile`;
		`echo \"unmounting $mp\"             >> $logfile`;
		`$UMOUNT_CMD $mp 2>&1 >> $logfile`;
		# -l	:	lazy umount: umount, but complete when the file are not
		# 			being used
	}
	# NOTE: it looks like ntfs-3g, which is a fuse system, does NOT use the fusemount -u
	# to umount: just normal umount. So all just use umount
}



sub remove_mountpoint_dir{
	my $mp = shift; 
	`echo \"Removing the mount dir $mp\" >> $logfile`;
	my $rmMountDirCount = 0; 
	my $secs = 0;
	my $successfulrmdir = 0; 
	my $mountpoint_existed = 0; 
	while ( -d $mp ) {
		$mountpoint_existed = 1; 
		$rmMountDirCount++; 
		my $retVal = `/bin/rmdir $mp  2>&1   > /dev/null`; 
		if ($retVal == 0){
			$successfulrmdir =1; 
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
		`echo \"Took $rmMountDirCount attempts to remove the $mp dir ($secs seconds)\n\n \"								>> $logfile`; 
	} else {
		`echo \"FAILED in $rmMountDirCount attempts to remove the $mp dir ($secs seconds)\n\n \"								>> $logfile`; 
		`$XMESSAGE_CMD "Could not remove the $mp mount point dir after $rmMountDirCount attempts.  \nPlease investigate.\n" `; 
	}
}




use List::MoreUtils 'uniq' ; 

sub remove_mounting_programs ($mp) {
	# Removes all programs that MOUNT something on the mountpoint
	
	#25983 pts/5    Sl+    0:00 nvim rssxml_list.txt
	my @mountingProgramsPIDs = `/bin/ps -ax | $GREP_CMD $mp | $GREP_CMD "/dev/" | $GREP_CMD -v "grep" | $GREP_CMD -v $thisProgName | $AWK_CMD '{print \$1}' `; 
	chomp @mountingProgramsPIDs; 
	
	foreach my $pidToKill ((@mountingProgramsPIDs)) {
		`$KILL_CMD $pidToKill 2>/dev/null `; 
	}
}




sub remove_accessing_programs ($mp) {
	# the programs that access the mount point
	# NOT any programs involed in actually MOUNTING a dir at the mount point
	# NOT this current program

	#bash      16996               me  cwd       DIR       8,17     4096      38258 /media/usbhd/music/podcasts
	my @accessingProgramsPIDs = `$LSOF_CMD | $GREP_CMD $mp | $GREP_CMD -v "grep" | $GREP_CMD -v "/sbin/mount" | $GREP_CMD -v $thisProgName | $AWK_CMD '{print \$2}' `; 
	chomp @accessingProgramsPIDs; 
	
	foreach my $pidToKill (( @accessingProgramsPIDs)) {
		`$KILL_CMD $pidToKill 2>/dev/null `; 
	}
}






sub unlink_links_to_the_mountpoint{
	my @ln_from = `$GREP_CMD -v "^#" $mountPoint2LinkFile | $GREP_CMD $mount_point |  $AWK_CMD \'{print \$1}\'`;
	chomp (@ln_from);
	foreach my $this_lnFrom (@ln_from) {
		# this is safe as the links can only come from the file
		next unless -e $this_lnFrom; 
		my $logMsg = `/usr/local/bin/datetime`; chomp $logMsg; 
		$logMsg .= "\n"; 
		my $unlinkFail = `unlink $this_lnFrom 2> /dev/null `;
		$logMsg = "unlinked $this_lnFrom \n " 
			if (! $unlinkFail ) ;
		# also remove any dirs where links TO the mountpoint should be (eg /mnt/someLink as a dir)
		my $rmdirFailed = `rmdir $this_lnFrom 2> /dev/null `; 
		$logMsg .= "removed a DIR at $this_lnFrom (should have been a link)\n"  
			if ( ! $rmdirFailed); 		# 1-->error; 0-->OK-->there was a dir-->print message 
		`echo \"$logMsg\" >> $logfile `; 
		
	}
}





sub exit_if_mountpoint_not_mounted( $mp  ){

	my $adjMountPoint = ($mp  =~ s,/,\/,gr); 
	my @mountedOn_mountpoints = `$MOUNT_CMD | $GREP_CMD \"$adjMountPoint\" `;
	chomp @mountedOn_mountpoints; 
	if (1 > @mountedOn_mountpoints) {
		my $timestamp           = `/usr/local/bin/datetime`;
		chomp $timestamp;
		my $logMsg = "$timestamp\n$mp was not mounted, so didn\'t need to be un-mounted\n";
		`echo \"$logMsg\" >> $logfile `; 
		die 0; 
	}
}





# ====== main program ================================================

# 1. MUST be unmounted BEFORE removing the mount_point directory
# 2. all of
# 		all progs (lsof & ps) killed			<-- what if only the mouting programs killed? 
# 		unmounted
#		remove links to the mountpoint
# 		mountpoint directory removed 
# 3: Do all of 2, even if not mounted


# 0 : check parameters
if ( check_program_parameters( $mount_point ) ) {
	print "\nbye\n"; 
	exit( 1 ) 
}

# 1 : remove (or warn) still running programs
if ("warn" eq $kill_warn){
	my @pidAndFile	=	@{ list_apps_active_on_mountpoint( $mount_point ) }; 
	warn_on_pid_file_list( @pidAndFile )
		 if  ( @pidAndFile > 0 );
}
if ( "kill" eq $kill_warn ) {
    remove_mounting_programs($mount_point);
	# remove_accessing_programs($mount_point);	# <-- poss leave the progs running, if lazy umount
}

# 2 : unmount the mount point
ensure_to_umount_mountpoint( $mount_point ); 

# 3 : unlink links to the mouuntpoint dir
unlink_links_to_the_mountpoint( ) ; 

# 4 : remove the mountpoint dir
remove_mountpoint_dir($mount_point) ;

# 5 : 
# exit_if_mountpoint_not_mounted( $mount_point ); 
















# ======= notes ===================================================
#
#
#
#
# - other, unusuals
#
# this will also go into check_every_minute.pl
# 
# if not in proc partitons : get rid of it (kill the mount program supporting it)
# 	mountpoint --> /dev/sda3, /dev/sdf2 ... kill those not in proc partions REGARDLESS
#
# if (one 'instantiation') of a mount point is not the mounted version, then kill it
# 	mountpoint --> /dev/sda3, /dev/sdf2 ... kill those not in mount IFF no lsof 

# 
