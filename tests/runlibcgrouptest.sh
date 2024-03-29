#!/bin/bash
# usage ./runlibcgrouptest.sh
# Copyright IBM Corporation. 2008
#
# Author:	Sudhir Kumar <skumar@linux.vnet.ibm.com>
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2.1 of the GNU Lesser General Public License
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it would be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Description: This script runs the the basic tests for testing libcgroup apis.
#

# TODO path to config.h have to be set properly
OPAQUE_HIERARCHY=`grep "OPAQUE_HIERARCHY" /home/thromatka/git/20220511-libcg-rel/upcg/config.h |\
	 cut -d" " -f3 | sed  's|\"||g'`
DEBUG=false;		# for debug messages
FS_MOUNTED=0;		# 0 for not mounted, 1 for mounted, 2 for multimounted
MOUNTPOINT=/dev/cgroup_controllers;	# Just to initialize
TARGET=/dev/cgroup_controllers;
CONTROLLERS=cpu,memory;
NUM_MOUNT=1;		# Number of places to be mounted on
MULTIMOUNT=false;	# mounted at one point only
NUM_CTLRS=0;		# num of controllers supported
CTLR1="";
CTLR2="";
CPU="";
MEMORY="";
SKIP_TEST=77
RET=0

declare -a allcontrollers;
declare -a targets;

debug()
{
	# Function parameter is the string to print out
	if $DEBUG
	then
		echo SH:DBG: $1;
	fi
}

check_mount_fs ()
{
	local NUM_MOUNT=0;
	CGROUP=`cat /proc/mounts|grep -w ^cgroup|tr -s [:space:]|cut -d" " -f3`;

	# get first word in case of multiple mounts
	CGROUP=`echo $CGROUP|cut -d" " -f1`;

	debug "check_mount_fs(): CGROUP is $CGROUP";
	if [ "$CGROUP" = "cgroup" ]
	then
		NUM_MOUNT=`cat /proc/mounts|grep -w ^cgroup|wc -l`;
		debug "check_mount_fs(): fs mounted at $NUM_MOUNT places";

		if [ $NUM_MOUNT -eq 1 ]
		then
			FS_MOUNTED=1;
		else
			# Any number of mounts is multi mount
			FS_MOUNTED=2;
		fi;
		return 0;	# True
	else
		FS_MOUNTED=0;
		return 1;	# false
	fi
}

umount_fs ()
{
	PROC_ENTRY_NUMBER=`cat /proc/mounts|grep ^cgroup | wc -l`;
	NUMBER=1;
	#go and remove all ot opaque mount points
	while [ $PROC_ENTRY_NUMBER -ge $NUMBER ]
	do
		# Get $NUMBER-th mountpoint in case of multiple mount
		PROC_ENTRY=`cat /proc/mounts|grep ^cgroup|\
				tr -s [:space:]|cut -d" " -f2 |\
				head -n$NUMBER | tail -n1`;
		# if the hierarchy is opaque skip to next item
		if [ -n "$OPAQUE_HIERARCHY" ]
		then
			# find whether is the NUMBER-th item opaque
			PROC_ENTRY_OPT=`cat /proc/mounts|grep ^cgroup|\
				tr -s [:space:]|cut -d" " -f4 |\
				head -n$NUMBER | tail -n1`;
			echo $PROC_ENTRY_OPT | grep $OPAQUE_HIERARCHY
			# if yes skip it to the next item
			if [ $? -eq 0 ]
			then
				let NUMBER=$NUMBER+1
				continue
			fi;
		fi;
		# remove the item
		if [ ! -z "$PROC_ENTRY" ]
		then
			TARGET=$PROC_ENTRY;
			# Need to take care of running tasks in any group ??
			rmdir $TARGET/* 2> /dev/null ;
			umount $TARGET;
			rmdir  $TARGET;
			debug "umounted $TARGET";
		fi;
		# go to the next item
		let NUMBER=$NUMBER+1
	done;
	FS_MOUNTED=0;
	TARGET=/dev/cgroup_controllers;	#??
	echo "Cleanup done";
}

# Put all the supported controllers in an array
# We have the priority for cpu and memory controller. So prefer to mount
# them if they exist
get_all_controllers()
{
	while [ 1 ]; do
		read line || break;
		if ! echo $line | grep -q ^#
		then
			allcontrollers[$NUM_CTLRS]=`echo $line | cut -d" " -f1`;
			if [ ${allcontrollers[$NUM_CTLRS]} == "cpu" ]; then
				CPU="cpu";
			elif [ ${allcontrollers[$NUM_CTLRS]} == "memory" ]; then
				MEMORY="memory";
			fi;
			debug "controller: ${allcontrollers[$NUM_CTLRS]}";
			NUM_CTLRS=`expr $NUM_CTLRS + 1`;
		fi
	done < /proc/cgroups;
	debug "Total controllers $NUM_CTLRS";
}

# Get a second controller other than cpu or memory
get_second_controller()
{
	local i=0;
	while [ $i -lt $NUM_CTLRS ]
	do
		if [ "${allcontrollers[$i]}" != "cpu" ] &&
				 [ "${allcontrollers[$i]}" != "memory" ]
		then
			CTLR2=${allcontrollers[$i]};
			return 0;
		fi;
	i=`expr $i + 1`;
	done;
}

# Check if kernel is not having any of the controllers enabled
no_controllers()
{
	# prefer if cpu and memory controller are enabled
	if [ ! -z $CPU ] && [ ! -z $MEMORY ]
	then
		CONTROLLERS=$CPU,$MEMORY ;
		CTLR1=$CPU;
		CTLR2=$MEMORY;
		debug "first controller is $CTLR1";
		debug "second controller is $CTLR2";
		return 1;	# false
	elif [ ! -z $CPU ]
	then
		CONTROLLERS=$CPU ;
		CTLR1=$CPU;
		get_second_controller;
		debug "first controller is $CTLR1";
		debug "second controller is $CTLR2";
		return 1;	# false
	elif [ ! -z $MEMORY ]
	then
		CONTROLLERS=$MEMORY ;
		CTLR1=$MEMORY;
		get_second_controller;
		debug "first controller is $CTLR1";
		debug "second controller is $CTLR2";
		return 1;	# false
	fi;
	# Kernel has neither cpu nor memory controller enabled. So there is
	# no point in running the testcases. At least one of them should be
	# supported.(or should I run testcases with controllers such as
	#  ns, devices etc? Thoughts???)
	if [ $NUM_CTLRS -lt 2 ]
	then
		echo "Kernel needs to have 2 controllers enabled";
		echo "Recompile your kernel with at least 2 controllers"
		echo "Exiting the tests.....";
		exit $SKIP_TEST;
	fi;

	return 0;	# true
}


mount_fs ()
{
	local NUM_MOUNT=0;	# On how many places to mount on
	local CUR_MOUNT=1;
	FS_MOUNTED=0;

	# Check if kernel has controllers enabled
	if no_controllers
	then
		echo "Kernel has none of cpu/memory controllers enabled";
		echo "Recompile your kernel with at least one of these enabled"
		echo "Exiting the tests.....";
		exit $SKIP_TEST;
	fi;

	# At least one Controller is enabled. So proceed further.
	if [ -z $1 ]
	then
		echo "WARN: No parameter passed to function mount_fs";
		echo "taking default as 0....So not mounting cgroup fs";
	else
		NUM_MOUNT=$1;
		debug "mount_fs fs will be mounted on $NUM_MOUNT places";
	fi;

	# create so many directories i.e. mountpoints
	while [ $NUM_MOUNT -ge $CUR_MOUNT ]
	do
		NEWTARGET="$TARGET-$CUR_MOUNT";
		if [ -e $NEWTARGET ]
		then
			echo "WARN: $NEWTARGET already exist..overwriting";
			check_mount_fs;	# Possibly fs might be mounted on it
			if [ $FS_MOUNTED -gt 0 ]
			then
				umount_fs;
			else
				rmdir $NEWTARGET ;
			fi;
		fi;
		mkdir $NEWTARGET;

		# In case of multimount, mount controllers at diff points
		if $MULTIMOUNT ; then
			if [ $CTLR1 ] && [ $CTLR2 ] ; then
				if [ $CUR_MOUNT -eq 1 ] ; then
					CONTROLLERS=$CTLR1;
				else
					CONTROLLERS=$CTLR2;
				fi;
			else
				echo "Only 1 controler enabled in kernel";
				echo "So not running multiple mount testcases";
				exit $SKIP_TEST;
			fi;
		fi;

		mount -t cgroup -o $CONTROLLERS cgroup $NEWTARGET;
		if [ $? -ne 0 ]
		then
			echo "ERROR: in mounting cgroup fs on $NEWTARGET."
			echo "Exiting test";
			umount_fs;
			exit -1;
		fi;
		target[$CUR_MOUNT]=$NEWTARGET;
		CUR_MOUNT=`expr $CUR_MOUNT + 1`;
		FS_MOUNTED=`expr $FS_MOUNTED + 1`;

		# Group created earlier may again be visible if not cleaned.
		# So clean them all
		if [ -e $NEWTARGET/group1 ] # first group that is created
		then
			# Need to handle if tasks are running in them
			rmdir $NEWTARGET/group*
			echo "WARN: Earlier groups found and removed...";
		fi;

		debug "$CONTROLLERS controllers mounted on $NEWTARGET  directory"
	done;

	if [ $FS_MOUNTED -gt 2 ]
	then
		FS_MOUNTED=2;
	fi;

}

get_ctl_num()
{
	ctl1=$1;
	ctl2=$2;
	if [ -z $ctl1 ] || [ -z $ctl2 ]; then
		echo "Null controller passed to function get_ctl_num"
		echo "Exiting the testcases....."
	fi

	# Add any new controller developed here
	declare -a ctl_list;
	# Following list has to be in sync with enums in header
	ctl_list[0]="cpu";
	ctl_list[1]="memory";
	ctl_list[2]="cpuset";

	local i=0;
	while [ ! -z ${ctl_list[$i]} ]; do
		if [ "${ctl_list[$i]}" == "$ctl1" ]; then
			ctl1=$i;
		fi;

		if [ "${ctl_list[$i]}" == "$ctl2" ]; then
			ctl2=$i;
		fi;
	i=`expr $i + 1`;
	done;
}

runtest()
{
	MOUNT_INFO=$1;
	TEST_EXEC=$2;
	if [ -f $TEST_EXEC ]
	then
		./$TEST_EXEC $MOUNT_INFO $ctl1 $ctl2 ${target[1]} ${target[2]};
		if [ $? -ne 0 ]
		then
			echo Error in running ./$TEST_EXEC
			echo Exiting tests.
		else
			PID=$!;
		fi;
	else
		echo Sources not compiled. please run make;
	fi
}

###############################
# Main starts here
	# Check if kernel has controllers support
	if [ -e /proc/cgroups ]
	then
		get_all_controllers;
	else
		echo "Your Kernel seems to be too old. Plz recompile your"
		echo "Kernel with cgroups and appropriate controllers enabled"
		echo " Exiting the testcases...."
		exit $SKIP_TEST;
	fi;

	MY_ID=`id -u`
	if [ $MY_ID -ne 0 ]; then
		echo "Only root can start this script."
		echo " Exiting the testcase..."
		exit $SKIP_TEST
	fi

# TestSet01: Run tests without mounting cgroup filesystem
	echo;
	echo Running first set of testcases;
	echo ==============================
	FS_MOUNTED=0;
	FILE=libcgrouptest01;
	check_mount_fs;
	# unmount fs if already mounted
	if [ $FS_MOUNTED -ne 0 ]
	then
		umount_fs;
	fi;
	debug "FS_MOUNTED = $FS_MOUNTED"
	runtest $FS_MOUNTED $FILE

	wait $PID;
	RC=$?;
	if [ $RC -ne 0 ]
	then
		echo Test binary $FILE exited abnormaly with return value $RC;
		# Do not exit here. Failure in this case does not imply
		# failure in other cases also
		RET=$RC
	fi;

# TestSet02: Run tests with mounting cgroup filesystem
	echo;
	echo Running second set of testcases;
	echo ==============================
	FILE=libcgrouptest01;
	check_mount_fs;
	# mount fs at one point if not already mounted or multimounted
	NUM_MOUNT=1;
	if [ $FS_MOUNTED -eq 0 ]
	then
		mount_fs $NUM_MOUNT;
	elif [ $FS_MOUNTED -gt 1 ]
	then
		umount_fs;
		mount_fs $NUM_MOUNT;
	fi;
	debug "FS_MOUNTED = $FS_MOUNTED"
	get_ctl_num $CTLR1 $CTLR2;
	runtest $FS_MOUNTED $FILE

	wait $PID;
	RC=$?;
	if [ $RC -ne 0 ]
	then
		echo Test binary $FILE exited abnormaly with return value $RC;
		RET=$RC
	fi;
	umount_fs;


# TestSet03: Run tests with mounting cgroup filesystem at multiple points
	echo;
	echo Running third set of testcases;
	echo ==============================
	FILE=libcgrouptest01;
	check_mount_fs;
	# mount fs at multiple points
	MULTIMOUNT=true;
	NUM_MOUNT=2;
	if [ $FS_MOUNTED -eq 0 ]
	then
		mount_fs $NUM_MOUNT;
	elif [ $FS_MOUNTED -eq 1 ]
	then
		umount_fs;
		mount_fs $NUM_MOUNT;
	fi;
	debug "FS_MOUNTED = $FS_MOUNTED"
	get_ctl_num $CTLR1 $CTLR2;
	runtest $FS_MOUNTED $FILE

	wait $PID;
	RC=$?;
	if [ $RC -ne 0 ]
	then
		echo Test binary $FILE exited abnormaly with return value $RC;
		RET=$RC
	fi;
	umount_fs;

	exit $RET;
