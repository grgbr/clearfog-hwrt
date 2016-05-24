#!/bin/bash -e

usage()
{
	echo "$(basename $0): UBOOT LINUX DTB"
}

uboot=$1
linux=$2
dtb=$3

if test $# != 3; then
	echo "invalid number of arguments"
	usage
	exit 1
fi
if test ! -f $uboot; then
	echo "$uboot: no such file"
	exit 1
fi
if test ! -f $linux; then
	echo "$linux: no such file"
	exit 1
fi
if test ! -f $dtb; then
	echo "$dtb: no such file"
	exit 1
fi

declare -a devs
devs=($(lsblk --raw --output NAME,MOUNTPOINT,RM | \
        grep "[^ \t]\+ [^[ \t]\+ 1$" | \
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

read -N 1 -p "select device number to flash into : " reply
echo
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
root=${devs[reply + 1]}

if test ! -b "$dev"; then
	echo "$dev: invalid block device"
	exit 1
fi
if test ! -d $root; then
	echo "$root: no such directory"
	exit 1
fi

read -N 1 -p "flash into $dev under $root ? (y,[n]): " reply
echo
if test "$reply" != "y"; then
	echo "aborted"
	exit 1
fi

echo sudo dd if=$uboot of=$dev bs=512 seek=1
echo cp $linux $root/$(basename $linux)
echo cp $dtb $root/$(basename $dtb)
