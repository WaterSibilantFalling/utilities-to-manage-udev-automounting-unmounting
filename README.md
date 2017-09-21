
# udev device management scripts

These scripts manage the mounting and unmounting of devices in response to udev becoming aware of them as unmounted devices. 


### The scripts supporting udev

**12-sdm-mediaByLabel-autoMount-withTriggerScript.rules**

the udev rules file. 

**udev\_mount\_trigger.sh** and **udev\_umount_trigger.sh**

These one, two line trigger scripts are called directly from the udev rules file. These scripts then exit immediatly, having handed responsibility for mounting the device off to a udev_mount or udev_umount script. 

It is IMPERATIVE that anything called from a udev rules file exits IMMEDIATELY. That is why a second script is called to do the (slow) device mounting or un-mounting. 

**udev_mount.pl** and **udev_umount.pl**

These scripts actually mount and un-mount removeable media in response to udev calls. 


**linksToMountpoints.lst**

This is a list of pairs of 
	mount point or mp subdir	<tab>	link to that mountpoint or subdir
	mount point or mp subdir	<tab>	link to that mountpoint or subdir
	mount point or mp subdir	<tab>	link to that mountpoint or subdir
	mount point or mp subdir	<tab>	link to that mountpoint or subdir

The matching, appropriate links are made by the udev_mount_pl script and removed by the udev\_umount.pl script


### How these scripts work together

1.	a device is inserted (removed)
2.	udev recieves an 'insertion' (removal) signal with a great deal of infor about the device.
3.	the udev rules file is processed to see if there is a bmatch for the newly mounted device. 
4.	if there is a matching device, then the udev\_mount_trigger.pl (udev\_umount\_trigger.pl) script is called, with information about the device being pssed to the script
5.	The trigger script calls the udev\_mount.pl (udev\_umount.pl) script. 
6.	One of the things this mounting (unmounting) script does is to make each of the links, for this device, as listed in the ```linksToMountpoints.lst``` file. 






