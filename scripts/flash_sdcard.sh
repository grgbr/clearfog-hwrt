#!/bin/bash -e

################################################################################
# Make bootable SD
# Should be formatted as something like:
#  Device    Boot Start End    Sectors Size Id Type
#  /dev/sdh1      2048  249855 247808  121M  e W95 FAT16 (LBA)
################################################################################

usage()
{
	echo "$(basename $0): UBOOT_SPL UBOOT_ENV"
}

if test $# != 2; then
	echo "invalid number of arguments"
	usage
	exit 1
fi

declare -a devs
devs=($(lsblk --raw --output NAME,MODEL,RM,TYPE | \
	grep -E '^[^ ]+ [^ ]+ 1 disk$' | \
        cut -f 1,2 -d ' '))

echo "Available removable block device for flashing :"
d=0
while test $d -lt ${#devs[@]}; do
	echo -e "\t$((d / 2 + 1)) - ${devs[d]} ${devs[d + 1]}"
	d=$((d + 2))
done
if test ${#devs[@]} -lt 2; then
	echo -e "\tnone"
	exit 1
fi
echo

read -p "select device number to flash into : " reply
if ! echo $reply | grep -q '[0-9]\+'; then
	echo "invalid device number selected"
	exit 1
fi
reply=$(((reply - 1) * 2))
if test $reply -ge ${#devs[@]}; then
	echo "invalid device number selected"
	exit 1
fi

dev=/dev/${devs[reply]}

if test ! -b "$dev"; then
	echo "$dev: invalid block device"
	exit 1
fi

read -p "format and flash U-Boot into $dev ? (y,[n]): " reply
if test "$reply" != "y"; then
	echo "aborted"
	exit 1
fi

if mount | cut -f1 -d' ' | grep -qE "$dev[0-9]+"; then
	eject $dev >/dev/null 2>&1 || :
fi

# Partition SD card
sudo parted --script $dev mklabel msdos
sudo parted --script $dev mkpart primary ext4 1m 100%

# Format
pagesz=$((4*1024))
planesz=$((16*1024))
erasesz=$((32*1024))
sudo mkfs.ext4 \
	-F \
	-O ^has_journal,^huge_file,^dir_nlink \
	-E stride=$((planesz / pagesz)),stripe_width=$((erasesz / pagesz)),discard \
	-b $pagesz \
	-L CLEARFOG \
	${dev}1

# Install U-Boot SPL binary right after MBR, i.e. starting at 2nd sector ;
# then install U-Boot environment at 1 mBytes - 64kBytes offset as required by
# clearfog U-Boot implementation.
sectorsz=512
envoff=0xf0000
sudo dd if=$1 of=$dev bs=$sectorsz seek=1
sudo dd if=$2 of=$dev bs=512 seek=$((envoff / sectorsz))
