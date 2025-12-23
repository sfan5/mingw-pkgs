#!/bin/bash -eu

. ./common.sh
common_init "$@"

pkgver=17.1
pkgver_gmp=6.3.0
pkgver_mpfr=4.2.2
fetch_web "https://ftpmirror.gnu.org/gnu/gdb/gdb-$pkgver.tar.xz" \
	14996f5f74c9f68f5a543fdc45bca7800207f91f92aeea6c2e791822c7c6d876
unpack_tar "gdb-$pkgver.tar.xz" --strip-components=1
# included here to make it easier for me
fetch_web "https://gmplib.org/download/gmp/gmp-$pkgver_gmp.tar.xz" \
	a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898
unpack_tar "gmp-$pkgver_gmp.tar.xz"
fetch_web "https://www.mpfr.org/mpfr-current/mpfr-$pkgver_mpfr.tar.xz" \
	b67ba0383ef7e8a8563734e2e889ef5ec3c3b898a01d00fa0a6869ad81c6ce01
unpack_tar "mpfr-$pkgver_mpfr.tar.xz"

# for the build tools to find them:
ln -snf "gmp-$pkgver_gmp" gmp
ln -snf "mpfr-$pkgver_mpfr" mpfr

# don't build docs
MAKEINFO=/bin/false \
./configure --host=$MINGW_PREFIX --prefix=/ \
	--disable-nls --disable-source-highlight --enable-year2038
make

make DESTDIR=$INSTALL_DIR install
common_tidy

package $pkgver
