#!/bin/bash -eu

strip_pkg=0

_CUSTOMOPTS_E=__this_is_empty_dont_bother__
CUSTOMOPTS=($_CUSTOMOPTS_E)

_usage () {
	echo "This script builds the $CURRENT_PACKAGE_NAME package for Windows."
	echo "Supported flags:"
	echo "    -h/--help         Display this text"
	echo "    -j <jobs>         Use specified amount of jobs (default: $jobs)"
	echo "    --clean           Clean before building package"
	echo "    --64              Build for 64-bit"
	echo "    --arm64           Build for 64-bit ARM"
	echo "    --clang           Use clang over gcc (if you have it)"
	echo "    --strip           Strip binaries/libraries before packaging"
	echo "    --sandbox <mode>  Set build sandboxing mode (auto/yes/no)"
	if [ "$CUSTOMOPTS" != "$_CUSTOMOPTS_E" ]; then
		echo "Custom options:"
		for optspec in "${CUSTOMOPTS[@]}"; do
			printf "    --%-9s %s\n" ${optspec%%|*} "${optspec##*|}"
		done
	fi
}

_print_cmake_toolchain () {
	local cpu=
	# <https://superuser.com/questions/305901/>
	case "$MINGW_PREFIX" in
		i686-*)
		cpu=X86
		;;
		x86_64-*)
		cpu=AMD64
		;;
		aarch64-*)
		cpu=ARM64
		;;
	esac
	printf 'set(CMAKE_SYSTEM_NAME Windows)\n'
	printf 'set(CMAKE_SYSTEM_PROCESSOR %s)\n' $cpu
	printf 'set(CMAKE_C_COMPILER "%s")\n' $CC
	printf 'set(CMAKE_CXX_COMPILER "%s")\n' $CXX
	printf 'set(CMAKE_RC_COMPILER "%s")\n' $MINGW_PREFIX-windres
	local rootpath=$(dirname "$(which $CC)")/../$MINGW_PREFIX
	# ^ can we just assume this is the correct one?
	printf 'set(CMAKE_FIND_ROOT_PATH "%s")\n' "$rootpath"
	printf 'set(CMAKE_FIND_ROOT_PATH_MODE_%s)\n' \
		"PROGRAM NEVER" "LIBRARY ONLY" "INCLUDE ONLY" "PACKAGE ONLY"
}

_run_bwrap () {
	local args=(--proc /proc --dev /dev)
	for p in /bin /etc /lib{,32,64} /sbin /usr; do
		if [ -L $p ]; then
			args+=(--symlink "$(readlink $p)" $p)
		elif [ -d $p ]; then
			args+=(--ro-bind $p $p)
		fi
	done
	for p in /run /tmp /var /var/{empty,run,tmp}; do
		args+=(--dir $p)
	done
	# if mingw is located somewhere else make sure to bind that too
	local mingw=$(realpath $(dirname "$(which $CC)")/..)
	if [[ "$mingw" != /usr && "$mingw" != /usr/* ]]; then
		args+=(--ro-bind "$mingw" "$mingw")
	fi

	exec bwrap "${args[@]}" --bind "$PWD" "$PWD" \
		--unshare-all --share-net --die-with-parent \
		-- "$@"
}

common_init () {
	CURRENT_PACKAGE_NAME=$(basename "$0")
	FETCHCACHE="$PWD/dl"
	BUILDBASE="$PWD/build"
	PACKAGEDEST="$PWD"
	mkdir -p "$FETCHCACHE" "$BUILDBASE"
	local args_backup=("$@")

	# parse command line
	local use64=0
	local usea64=0
	local useclang=0
	local clean=0
	local sandbox=auto
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
			--arm64)
			usea64=1
			;;
			--clang)
			useclang=1
			;;
			--strip)
			strip_pkg=1
			;;
			--sandbox)
			shift
			sandbox=$1
			;;
			-h|--help)
			_usage
			exit 0
			;;
			*)
			custom=
			[ "$CUSTOMOPTS" != "$_CUSTOMOPTS_E" ] && \
			for optspec in "${CUSTOMOPTS[@]}"; do
				[[ "--${optspec%%|*}" != "$1" ]] && continue
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

	# environment
	if [ $usea64 -eq 1 ]; then
		MINGW_PREFIX=aarch64-w64-mingw32
		MINGW_TYPE=win64-aarch64 # Mozilla uses this naming
	elif [ $use64 -eq 1 ]; then
		MINGW_PREFIX=x86_64-w64-mingw32
		MINGW_TYPE=win64
	else
		MINGW_PREFIX=i686-w64-mingw32
		MINGW_TYPE=win32
	fi
	if [ $useclang -eq 1 ]; then
		CC=$MINGW_PREFIX-clang
		CXX=$CC++
	else
		CC=$MINGW_PREFIX-gcc
		CXX=$MINGW_PREFIX-g++
	fi
	# not sure if it was an gnu autotools bug or my setup but it's safer to
	# specify the linker lest autoconf gets confused
	LD=$MINGW_PREFIX-ld
	STRIP=$MINGW_PREFIX-strip
	export CC CXX LD STRIP

	# test that these exist
	if ! command -v $CC >/dev/null; then
		echo "$CC not found" >&2
		exit 1
	fi
	if ! command -v $LD >/dev/null; then
		echo "$LD not found" >&2
		exit 1
	fi

	# sandboxing
	if [[ "$(readlink /proc/1/exe)" == *"/bwrap" ]]; then
		: # we're inside the sandbox
	else
		if [ "$sandbox" = auto ]; then
			which bwrap &>/dev/null && sandbox=yes
		elif [ "$sandbox" = yes ]; then
			which bwrap >/dev/null
		fi
		[ "$sandbox" = yes ] && _run_bwrap "$0" "${args_backup[@]}"
	fi

	# environment (part 2)
	export MAKEFLAGS="-j$jobs"

	unset DISPLAY XAUTHORITY

	# neutralize pkg-config, it's not used
	export PKG_CONFIG_SYSROOT_DIR=/var/empty
	export PKG_CONFIG_LIBDIR=/var/empty
	unset PKG_CONFIG_PATH

	local builddir="$BUILDBASE/$CURRENT_PACKAGE_NAME-$MINGW_TYPE"
	mkdir -p "$builddir"
	CMAKE_TOOLCHAIN="$builddir/toolchain.cmake"
	_print_cmake_toolchain >"$CMAKE_TOOLCHAIN"

	# set up directories
	SRCDIR="$builddir/src"
	INSTALL_DIR="$builddir/pkg"
	[ $clean -eq 1 ] && rm -rf "$SRCDIR"
	rm -rf "$INSTALL_DIR"
	mkdir -p "$SRCDIR" "$INSTALL_DIR"
	cd "$SRCDIR"
}

fetch_git () {
	local gitdir=$FETCHCACHE/$CURRENT_PACKAGE_NAME.git
	if [ -d $gitdir ]; then
		[ -f "$SRCDIR/.git" ] || git init --separate-git-dir=$gitdir "$SRCDIR"
		GIT_DIR=$gitdir git fetch
		GIT_DIR=$gitdir GIT_WORK_TREE=$SRCDIR git reset HEAD --hard
	else
		local branch=master
		[ $# -ge 2 ] && branch=$2
		git clone -b $branch --separate-git-dir=$gitdir "$1" "$SRCDIR"
	fi
}

fetch_web () {
	local filename=${1##*/}
	[ $# -ge 3 ] && filename=$3
	[ -f $FETCHCACHE/"$filename" ] && return 0
	local filedest=$(mktemp -p $FETCHCACHE -u)
	hash=$(wget -O- "$1" | tee >(sha256sum | cut -d " " -f 1) >$filedest)
	if [ "$hash" != "$2" ]; then
		echo "Hash mismatch for $filename" >&2
		echo "  expected: $2" >&2
		echo "  actual: $hash" >&2
		rm $filedest
		return 1
	else
		mv $filedest "$FETCHCACHE/$filename"
	fi
}

unpack_zip () {
	echo "Extracting: $1" >&2
	unzip -qnd "$SRCDIR" "$FETCHCACHE/$1"
}

unpack_tar () {
	local tarfile=$FETCHCACHE/$1
	shift
	echo "Extracting: $(basename "$tarfile")" >&2
	tar -xa -f "$tarfile" -C "$SRCDIR" "$@"
}

common_flat_tree () {
	ln -snf . "$INSTALL_DIR/usr"
	ln -snf . "$INSTALL_DIR/local"
}

common_tidy () {
	pushd $INSTALL_DIR >/dev/null
	find . -name '*.la' -delete
	# delete symlinks possibly created by common_flat_tree
	[ -L usr ] && rm -f usr local
	# although pkgconfig can work on windows/mingw we don't use it
	[ -d lib/pkgconfig ] && rm -r lib/pkgconfig
	[ -d share ] && rm -rf share/{info,man,doc,aclocal}
	find . -depth -type d -exec rmdir {} \; 2>/dev/null # empty directories
	popd >/dev/null
}

_strip_pkg () {
	find . -name '*.exe' -exec $STRIP {} \;
	find . -name '*.dll'  -exec $STRIP --strip-unneeded {} \;
	find . -name '*.a' -a -not -name '*.dll.a' -exec $STRIP -g {} \;
}

package () {
	[[ -z "$1" || "$1" == *" "* ]] && { echo "Version invalid, cannot proceed." >&2; return 1; }
	local zipfile=$PACKAGEDEST/$CURRENT_PACKAGE_NAME-$1-$MINGW_TYPE.zip
	rm -f "$zipfile"

	[ -z "$(ls "$INSTALL_DIR")" ] && { echo "Package empty, cannot proceed." >&2; return 1; }
	pushd $INSTALL_DIR
	[ $strip_pkg -eq 1 ] && _strip_pkg
	zip -9ry "$zipfile" -- *
	popd
}

depend_get_path () {
	local p="$BUILDBASE/$1-$MINGW_TYPE/pkg"
	if [ ! -d $p ]; then
		local p2=$(echo "$PACKAGEDEST/$1-"[!-]*"-$MINGW_TYPE.zip")
		if [ ! -f "$p2" ]; then
			echo "The dependency $1 needs to be built first!" >&2
			kill $$ # there doesn't seem to be a good way to exit from here
		else
			echo "Note: The dependency $1 was requested and exists as a ZIP archive, unpacking it." >&2
			mkdir -p "$p"
			unzip -q "$p2" -d "$p" || kill $$
		fi
	fi
	printf '%s' "$p"
}
