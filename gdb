#!/bin/bash -eu

. ./common.sh
common_init "$@"

pkgver=10.1
fetch_web "https://ftp.gnu.org/gnu/gdb/gdb-$pkgver.tar.xz" \
	f82f1eceeec14a3afa2de8d9b0d3c91d5a3820e23e0a01bbb70ef9f0276b62c0
unpack_tar "gdb-$pkgver.tar.xz" --strip-components=1

>gdb/doc/gdb.texinfo # skip building documentation
CC=$MINGW_CC CXX=$MINGW_CXX ./configure --host=$MINGW_PREFIX --prefix=/ \
	--disable-nls --disable-source-highlight
make

make DESTDIR=$INSTALL_DIR install
common_tidy

package $pkgver
