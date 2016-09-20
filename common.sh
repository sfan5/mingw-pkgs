#!/bin/bash -eu

strip_pkg=0

common_init () {
	CURRENT_PACKAGE_NAME=$(basename "$0")
	FETCHCACHE="$PWD/dl"
	BUILDBASE="$PWD/build"
	PACKAGEDEST="$PWD"
	mkdir -p $FETCHCACHE $BUILDBASE

	local use64=0
	local clean=0
	local jobs=$(grep processor /proc/cpuinfo | wc -l)
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
			echo "This script builds the $CURRENT_PACKAGE_NAME package for Windows."
			echo "Supported flags:"
			echo "    -h/--help   Display this text"
			echo "    -j          Use specified amount of jobs (default: $jobs)"
			echo "    --clean     Clean before building package"
			echo "    --64        Build using MinGW-w64"
			echo "    --strip     Strip EXE and DLL files before packaging"
			exit 0
			;;
			*)
			echo "Unknown argument: $1" 1>&2
			exit 1
			;;
		esac
		shift
	done

	if [ $use64 -eq 1 ]; then
		MINGW_PREFIX=x86_64-mingw32
		MINGW_CC=$MINGW_PREFIX-gcc
		MINGW_CXX=$MINGW_PREFIX-g++
		MINGW_STRIP=$MINGW_PREFIX-strip
		MINGW_TYPE=win64
	else
		MINGW_PREFIX=i686-mingw32
		MINGW_CC=$MINGW_PREFIX-gcc
		MINGW_CXX=$MINGW_PREFIX-g++
		MINGW_STRIP=$MINGW_PREFIX-strip
		MINGW_TYPE=win32
	fi
	MAKE_JOBS=$jobs

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
		pwd
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
	hash=$(wget -O- $1 | tee >(sha256sum | cut -d" " -f1) >$filedest)
	if [ ! "$hash" == "$2" ]; then
		echo "Hash mismatch for $filename" 1>&2
		echo "  expected: $2" 1>&2
		echo "  actual: $hash" 1>&2
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

_strip_pkg () {
	find . -name '*.exe' -o -name '*.dll' -exec $MINGW_STRIP {} \;
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
		echo "The dependency $1 needs to be built first" 1>&2
		return 1
	else
		echo $p
	fi
}