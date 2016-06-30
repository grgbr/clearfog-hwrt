#!/bin/bash -e

cmdargs="--subject-prefix=PATCH"

usage()
{
	echo "Usage: $(basename $0) [OPTIONS] PATCH_DIR [REVISION_RANGE]"
	echo "where PATCH_DIR      patch submission directory"
	echo "      REVISION_RANGE git revision range"
	echo "where OPTIONS"
	echo "      -u             update current version of patch"
	echo "      -n             do not generate a cover letter"
	echo "      -h             this message"
	exit $1
}

update=0
nocover=0
while getopts "unh" opt; do
	case $opt in
	u)  update=1;;
	n)  nocover=1;;
	h)  usage "0";;
	\?) usage "1";;
	esac
done
shift $((OPTIND - 1))

. $(dirname $0)/functions

if test $# -lt 1; then
	echo -e "Missing argument\n"
	usage "1"
fi

patchdir=$1
if test -d "$patchdir"; then
	vers=$(get_vers "$patchdir")
fi
if test -z "$vers"; then
	# Must start from version 1
	vers=1
elif test $update -eq 0; then
	vers=$((vers + 1))
fi
patchdir=$(realpath $patchdir)/v$vers

if test $nocover -ne 0; then
	cmdargs="$cmdargs --no-cover-letter"
else
	cmdargs="$cmdargs --cover-letter"
fi
shift 1

# create patch series
mkdir -p $patchdir
find $patchdir ! -name cover.txt ! -name mailing -type f -delete
cd $kerndir
git format-patch \
	$cmdargs \
	--output-directory=$patchdir \
	--reroll-count=$vers \
	$*

# check patches comply with kernel coding style and output a report
coverpattern='*0000-cover-letter.patch'
patches=$(find $patchdir ! -name $coverpattern -name "*.patch")
if test -z "$patches"; then
	echo "No patches generated. Aborting..."
	exit 1
fi
if ! scripts/checkpatch.pl --strict --codespell $patches; then
	echo "Patch series does not seem compliant with kernel coding style"
	read -s -N 1 -p "Do you still want to generate patches ? (y/n)" goon
	echo
	if test "$goon" != "y"; then
		exit 1
	fi
fi

# update patch series maintainers list
scripts/get_maintainer.pl $patches > $patchdir/maintainers

# If requested, generate a cover letter from optional custom one.
#
# First line of custom cover letter must correspond to the mail subject body
# followed by a blank line.
if test $nocover -eq 0; then
	coverfile=$patchdir/cover.txt

	if test ! -f $coverfile -a \
	        -f $patchdir/../v$((vers - 1))/cover.txt; then
		cp $patchdir/../v$((vers - 1))/cover.txt $coverfile
	fi

	if test -f $coverfile; then
		ed -s $(find $patchdir -name $coverpattern) <<-_EOF_
# Remove everything between subject line and cover letter epilogue start line,
# i.e. the line of the form : "<user name> (<number of patch in the series):"
/^Subject: /+1,/$(git config user.name) ([0-9]\+):/-1 d
# Now include custom cover letter
.-1 r $coverfile
# append a blank line
. a

.
# Now rework the subject line so that first line of custom cover letter is
# joined with current subject prefix
/^Subject: / s/^Subject: \[\([^]]\+\)\] .*$/Subject: [\1] /
.,+1 j
1,$ wq
_EOF_

	fi
fi

if test $update -ne 0; then
	echo -e "\nCreated new patch series version $vers\n"
else
	echo -e "\nUpdated patch series version $vers\n"
fi
if test $nocover -eq 0; then
	echo -e "You should edit cover letter body :\n    $patchdir/cover.txt"
fi
echo "A list maintainers related to this series was created in :"
echo "    $patchdir/maintainers"
echo "Before mailing the series, you should edit the recipients list here :"
echo "    $patchdir/mailing"
