#!/bin/bash

# this script is a trigger script to run the actual mount command in the background
# and then INSTANTLY retuns. Do NOT add ANY time consuming tasks to this script
#
# it is used so that udev commands, "RUN+=" strings, don't take any observable time 
# themselves. 


# $*	:	all command line arguements as one long space ($IFS) separated string
/usr/local/bin/udev_umount.pl $*  & exit



