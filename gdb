#!/bin/bash -eu

. ./common.sh
common_init "$@"

pkgver=14.1
pkgver_gmp=6.3.0
pkgver_mpfr=4.2.1
fetch_web "https://ftp.gnu.org/gnu/gdb/gdb-$pkgver.tar.xz" \
	d66df51276143451fcbff464cc8723d68f1e9df45a6a2d5635a54e71643edb80
unpack_tar "gdb-$pkgver.tar.xz" --strip-components=1
# included here to make it easier for me
fetch_web "https://gmplib.org/download/gmp/gmp-$pkgver_gmp.tar.xz" \
	a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898
unpack_tar "gmp-$pkgver_gmp.tar.xz"
fetch_web "https://www.mpfr.org/mpfr-current/mpfr-$pkgver_mpfr.tar.xz" \
	277807353a6726978996945af13e52829e3abd7a9a5b7fb2793894e18f1fcbb2
unpack_tar "mpfr-$pkgver_mpfr.tar.xz"

# for the build tools to find them:
ln -snf "gmp-$pkgver_gmp" gmp
ln -snf "mpfr-$pkgver_mpfr" mpfr

>gdb/doc/gdb.texinfo # skip building documentation
CC=$MINGW_CC CXX=$MINGW_CXX ./configure --host=$MINGW_PREFIX --prefix=/ \
	--disable-nls --disable-source-highlight
make

make DESTDIR=$INSTALL_DIR install
common_tidy

package $pkgver
