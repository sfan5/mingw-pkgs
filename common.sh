#!/bin/bash -eu

strip_pkg=0

_CUSTOMOPTS_E=__this_is_empty_dont_bother__
CUSTOMOPTS=($_CUSTOMOPTS_E)

_usage () {
	echo "This script builds the $CURRENT_PACKAGE_NAME package for Windows."
	echo "Supported flags:"
	echo "    -h/--help   Display this text"
	echo "    -j          Use specified amount of jobs (default: $jobs)"
	echo "    --clean     Clean before building package"
	echo "    --64        Build using 64-bit MinGW"
	echo "    --strip     Strip binaries/libraries before packaging"
	if [ "$CUSTOMOPTS" != "$_CUSTOMOPTS_E" ]; then
		echo "Custom options:"
		for optspec in "${CUSTOMOPTS[@]}"; do
			printf "    --%-9s %s\n" ${optspec%%|*} "${optspec##*|}"
		done
	fi
}

common_init () {
	CURRENT_PACKAGE_NAME=$(basename "$0")
	FETCHCACHE="$PWD/dl"
	BUILDBASE="$PWD/build"
	PACKAGEDEST="$PWD"
	mkdir -p $FETCHCACHE $BUILDBASE

	# parse command line
	local use64=0
	local clean=0
	local jobs=$(grep -c '^processor' /proc/cpuinfo)
	[ "$CUSTOMOPTS" != "$_CUSTOMOPTS_E" ] && \
	for optspec in "${CUSTOMOPTS[@]}"; do
		local tmp=${optspec%|*}
		declare -g ${tmp#*|}=0
	done
	while [ $# -gt 0 ]; do
		case "$1" in
			-j)
			shift
			jobs=$1
			;;
			--clean)
			clean=1
			;;
			--64)
			use64=1
			;;
			--strip)
			strip_pkg=1
			;;
			-h|--help)
			_usage
			exit 0
			;;
			*)
			custom=
			[ "$CUSTOMOPTS" != "$_CUSTOMOPTS_E" ] && \
			for optspec in "${CUSTOMOPTS[@]}"; do
				[ ! "--${optspec%%|*}" == "$1" ] && continue
				local tmp=${optspec%|*}
				custom=${tmp#*|}
			done
			if [ -z "$custom" ]; then
				echo "Unknown argument: $1" >&2
				exit 1
			else
				declare -g $custom=1
			fi
			;;
		esac
		shift
	done

	# env vars
	if [ $use64 -eq 1 ]; then
		MINGW_PREFIX=x86_64-w64-mingw32
		MINGW_TYPE=win64
	else
		MINGW_PREFIX=i686-w64-mingw32
		MINGW_TYPE=win32
	fi
	MINGW_CC=$MINGW_PREFIX-gcc
	MINGW_CXX=$MINGW_PREFIX-g++
	MINGW_STRIP=$MINGW_PREFIX-strip
	export MAKEFLAGS="-j$jobs"
	which wine &>/dev/null && unset DISPLAY

	which $MINGW_CC >/dev/null

	# set up directories
	local builddir="$BUILDBASE/$CURRENT_PACKAGE_NAME-$MINGW_TYPE"
	SRCDIR="$builddir/src"
	INSTALL_DIR="$builddir/pkg"
	[ $clean -eq 1 ] && rm -rf $SRCDIR
	[ -d $INSTALL_DIR ] && rm -rf $INSTALL_DIR
	mkdir -p $SRCDIR $INSTALL_DIR
	cd $SRCDIR
}

fetch_git () {
	local gitdir=$FETCHCACHE/$CURRENT_PACKAGE_NAME.git
	if [ -d $gitdir ]; then
		[ -f $SRCDIR/.git ] || git init --separate-git-dir=$gitdir $SRCDIR
		GIT_DIR=$gitdir git fetch
		GIT_DIR=$gitdir GIT_WORK_TREE=$SRCDIR git reset HEAD --hard
	else
		local branch=master
		[ $# -ge 2 ] && branch=$2
		git clone -b $branch --separate-git-dir=$gitdir "$1" $SRCDIR
	fi
}

fetch_web () {
	local filename=${1##*/}
	[ $# -ge 3 ] && filename=$3
	[ -f $FETCHCACHE/$filename ] && return 0
	local filedest=$(mktemp -p $FETCHCACHE -u)
	hash=$(wget -O- "$1" | tee >(sha256sum | cut -d " " -f 1) >$filedest)
	if [ "$hash" != "$2" ]; then
		echo "Hash mismatch for $filename" >&2
		echo "  expected: $2" >&2
		echo "  actual: $hash" >&2
		rm $filedest
		return 1
	else
		mv $filedest $FETCHCACHE/$filename
	fi
}

unpack_zip () {
	unzip -nd $SRCDIR $FETCHCACHE/$1
}

unpack_tar () {
	local tarfile=$FETCHCACHE/$1
	shift
	tar -xva -f $tarfile -C $SRCDIR "$@"
}

common_tidy () {
	pushd $INSTALL_DIR >/dev/null
	find . -name '*.la' -delete
	# although pkgconfig can work on windows/mingw we don't use it
	[ -d lib/pkgconfig ] && rm -r lib/pkgconfig
	[ -d share ] && rm -rf share/{info,man,doc,aclocal}
	find . -depth -type d -exec rmdir {} \; 2>/dev/null # empty directories
	popd >/dev/null
}

_strip_pkg () {
	find . -name '*.exe' -exec $MINGW_STRIP {} \;
	find . -name '*.dll' -exec $MINGW_STRIP --strip-unneeded {} \;
	find . -name '*.a' -exec $MINGW_STRIP -g {} \;
}

package () {
	local zipfile=$PACKAGEDEST/$CURRENT_PACKAGE_NAME-$1-$MINGW_TYPE.zip
	pushd $INSTALL_DIR
	[ $strip_pkg -eq 1 ] && _strip_pkg
	rm -f $zipfile
	zip -9ry $zipfile -- *
	popd
}

depend_get_path () {
	local p="$BUILDBASE/$1-$MINGW_TYPE/pkg"
	if [ ! -d $p ]; then
		echo "The dependency $1 needs to be built first" >&2
		kill $$ # there doesn't seem to be a good way to exit from here
	else
		echo $p
	fi
}
