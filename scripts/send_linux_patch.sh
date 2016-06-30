#!/bin/sh -e

usage()
{
	echo "Usage: $(basename $0) [OPTIONS] PATCHSET"
	echo "where PATCHSET path to patch set to submit"
	echo "where OPTIONS"
	echo "      -p       really post to official maintainers and lists"
	echo "      -h       this message"
	exit $1
}

post=0
while getopts "ph" opt; do
	case $opt in
	p)  post=1;;
	h)  usage "0";;
	\?) usage "1";;
	esac
done
shift $((OPTIND - 1))

. $(dirname $0)/functions

if test $# -ne 1; then
	echo "Missing argument\n"
	usage "1"
fi

patchdir=$1
if test ! -d "$patchdir"; then
	echo "Invalid patch directory"
	exit 1
fi

patchdir=$(realpath $patchdir/v$(get_vers "$patchdir"))
if test ! -d "$patchdir"; then
	echo "Invalid version directory"
	exit 1
fi

cd $kerndir
if test $post -eq 0; then
	exec git send-email --to="$(git config user.email)" $patchdir/*.patch
fi

if test ! -f "$patchdir/mailing"; then
	echo "Missing mailing file"
	exit 1
fi

cat $patchdir/mailing | xargs git send-email $patchdir/*.patch
