#! /bin/sh

# default config

DO_INSTALL=1
USE_EXTERNAL_SCRIPT=0
FORMAT=1
PARTITION=1
SETDATETIME=1
USELVM=1

ROOT_SIZE=10GiB
SWAP_SIZE=1024MiB

#########################DO NOT EDIT BELOW!############################

_mdadm=/usr/sbin/mdadm
_parted=/usr/sbin/parted
_device=/dev/sda
_root=/dev/sda1
_home=/dev/sda2
_swap=/dev/sda3
_vg_name=bubba
_lv_name=storage
_lvm=/dev/mapper/$_vg_name-$_lv_name
_ledfreq=/sys/devices/platform/bubbatwo/ledfreq
_ledmode=/sys/devices/platform/bubbatwo/ledmode

# Indicate mount-phase
echo 4096 > $_ledfreq
echo blink > $_ledmode

getusb () {
	for arg in /sys/block/sd?
	do 
		_disk=`readlink -f $arg|grep usb | xargs -r basename`
		if [ -b /dev/${_disk}1 ]
		then
			_partition="/dev/${_disk}1"
		fi	
	done
}

waitforusb () {
	i=1
	while [ $i -eq 1 ]
	do
		sleep 1
		echo "Waiting for usb device to show up"
		getusb
		if [ -n "$_partition" ]
		then
			i=0
		fi
	done
}

waitforusb


# Mount usb-stick
echo "Mount usb"
while ! mount -t vfat $_partition /mnt/usb
do
	sleep 1
done

# Logging to file
_logfile=install-`date +%F_%H%M%S`.txt
exec 2>>/mnt/usb/install/$_logfile
exec 1>>/mnt/usb/install/$_logfile

echo "Check if we have an old lvm disk"
/sbin/lvdisplay bubba                          
_lvm_mode=$?          

echo "Check if we an old raid disk"
$_mdadm --examine /dev/sda2 1> /dev/null 2> /dev/null 
_raid_mode=$?

# Indicate install-phase
echo 8192 > $_ledfreq
echo blink > $_ledmode

if [ -e /mnt/usb/install/bubba.cfg ]; then
	echo "Reading external config"
	. /mnt/usb/install/bubba.cfg
else
	echo "No external config available"
fi

# Look if we should install at all.
if [ $DO_INSTALL -eq 0 ]; then
	echo "Not doing install by your command"
	# Blink slowly to indicate that we wont install.
	echo 32768 > $_ledfreq
	echo blink > $_ledmode
	exit 0
fi

if [ $USE_EXTERNAL_SCRIPT -eq 1 ]; then
	echo "Looking for external install script"
	if [ -e /mnt/usb/install/einstall.sh ]; then
		echo "Transfering control to external installer"
		/mnt/usb/install/einstall.sh
	else
		echo "No external script found"
	fi
	# blink real slow to tell were done executing external script 
	echo 49152 > $_ledfreq
	echo blink > $_ledmode
	exit 0
fi

_ifiles=`ls -1 /mnt/usb/install/payload/*.tar.gz | wc  -l`
if [ $_ifiles -le 0 ]; then
	echo "No payload to install, bailing out"
	echo 2048 > $_ledfreq
	echo blink > $_ledmode
	exit 1
fi

echo "Fixing umask"
umask 0

echo "Check for preinst script"
if [ -e /mnt/usb/install/preinst.sh ]; then
	echo "Executing preinst"
	/mnt/usb/install/preinst.sh
else
	echo "No preinst script available"
fi


if [ $SETDATETIME -eq 1 ]; then
	echo "Setting date/time"
	/usr/bin/wget -O - http://www.excito.com/install/date.php | /usr/bin/xargs /bin/date
	/sbin/hwclock -f /dev/rtc0 --systohc
else
	echo "Not setting date/time"
fi

if [ $FORMAT -eq 1 ]; then
	if [ $_lvm_mode == 0 ]; then
		# only remove if we also format the disk.
		echo "Possibly reduce lvm if degraded"
		vgreduce --force --removemissing bubba
		echo "Removing existing lvm"
		lvremove --force /dev/bubba/storage
		vgremove --force bubba
		pvremove --force /dev/sda2
		echo "LVM removed"
	else
		echo "No LVM attached"                                    
	fi

	if [ $_raid_mode == 0 ]; then
		echo "Stopping raid devices"
		for x in /dev/md?*
		do
			$_mdadm --stop $x
		done
		echo "Zero possible raid superblock on data partition"
		$_mdadm --zero-superblock /dev/sda2
	else
		echo "No raid devices detected"
	fi
fi

if [ $PARTITION -eq 1 ]; then
	echo "Partition disk"
	$_parted --script $_device --align optimal -- mklabel gpt
	$_parted --script $_device --align optimal -- mkpart root ext3 0 $ROOT_SIZE
	$_parted --script $_device --align optimal -- mkpart home ext3 $ROOT_SIZE -$SWAP_SIZE
	$_parted --script $_device --align optimal -- mkpart swap linux-swap -$SWAP_SIZE -1



else
	echo "Not partitioning disk"
fi

if [ $USELVM -eq 1 ]; then
	echo "Create volume"
	$_parted --script $_device --align optimal -- toggle 2 lvm
	export LVM_SYSTEM_DIR=/tmp/lvm
	pvcreate --force --force --yes $_home
	vgcreate --force --yes $_vg_name $_home
	lvcreate -l 100%FREE --name $_lv_name $_vg_name
else
	echo "Not creating volume"
fi


echo "Format system disk"
mkfs.ext3 -q -L "Bubba root" $_root
tune2fs -c0 -i0 $_root

if [ $FORMAT -eq 1 ]; then
	if [ $USELVM -eq 1 ]; then
		echo "Formatting lvm data partition"
		mkfs.ext3 -q -L "Bubba home" $_lvm
		tune2fs -c0 -i0 $_lvm
	else
		echo "Formatting native data partition"
		mkfs.ext3 -q -L "Bubba home" $_home
		tune2fs -c0 -i0 $_home
	fi
else
	echo "Not formatting data partition"
fi

echo "Create swapspace"
mkswap $_swap
 
echo "Install root filesystem"
mount -text3 $_root /mnt/disk
mkdir /mnt/disk/home
if [ $USELVM -eq 1 ]; then
	mount -text3 $_lvm /mnt/disk/home
else
	mount -text3 $_home /mnt/disk/home
fi

cd /mnt/disk
tar zxf /mnt/usb/install/payload/*.tar.gz
echo "Creating missing devicenodes"
# TODO XXX still needed?
mknod dev/sda b 8 0
mknod dev/sda1 b 8 1
mknod dev/sda2 b 8 2
mknod dev/sda3 b 8 3
mknod dev/sda4 b 8 4
mknod dev/sdb b 8 16
mknod dev/sdb1 b 8 17
mknod dev/sdb2 b 8 18
mknod dev/sdb3 b 8 19
mknod dev/sdb4 b 8 20
mknod dev/ttyS0 c 4 64
mknod dev/rtc c 254 0

# Indicate install done.
echo 16384 > $_ledfreq
echo blink > $_ledmode

echo "Check for postinst script"
if [ -e /mnt/usb/install/postinst.sh ]; then
	echo "Executing postinst"
	/mnt/usb/install/postinst.sh
else
	echo "No postinst script available"
fi

sync

echo "Umount home install partition"
umount /mnt/disk/home
echo "Umount system install partition"
umount /mnt/disk
echo "Umount usb storage"
umount /mnt/usb

sync
echo "Install done"
echo "Reboot into new system"
reboot
