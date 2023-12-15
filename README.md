mingw-pkgs
-----------

A collection of scripts to cross-compile various libraries, tools, applications to Windows via [MinGW](https://www.mingw-w64.org/).

Designed to run on Linux. You will need MinGW itself, bash, wget, (un)zip, tar. Builds are transparently sandboxed if you have [`bwrap`](https://github.com/containers/bubblewrap) installed.

Supports both `i686-w64-mingw32` and `x86_64-w64-mingw32`.

**Note**: This is just a thing I maintain for my personal usage. If you need something more serious take a look at [MSYS2](https://www.msys2.org/) or openSUSE's [ported packages](https://build.opensuse.org/project/show/windows:mingw:win64).

To build any package just run the script, it will produce a `name-X.Y.Z-win??.zip` archive upon completion.
These archives contain an Unix-like `bin`, `include`, `lib` folder structure (DLLs go in `bin`).
Generally both static and dynamic libraries are built.

Common flags for all scripts:
* `--clean`: Clean before building package
* `--64`: Build for 64-bit, default is 32-bit
* `--strip`: Strip binaries/libraries before packaging

Variables/functions available in packaging scripts:
* `common_init` `...`: Call this first while forwarding arguments
* `fetch_git` `<giturl> [branch]`: Download and checkout a git repo
* `fetch_web` `<url> <sha256> [filename]`: Download a file from the web and perform hash check
* `unpack_zip` `<filename>`: Unpack zip file
* `unpack_tar` `<filename> ...`: Unpack tar file, extra arguments are forwarded to tar
* `depend_get_path` `<name>`: Return path to package root of previously built named package
* `common_tidy`: Remove commonly found clutter from the install dir
* `package` `<pkgver>`: Pack contents of install dir into ZIP archive
* `$INSTALL_DIR`: Root directory of the package
* `$MINGW_CC`: target C compiler
* `$MINGW_CXX`: target C++ compiler
* `$MINGW_PREFIX`: target triple
* `$MINGW_TYPE`: either `win32` or `win64`
* `$CMAKE_TOOLCHAIN`: path to a CMake toolchain file, should be used to set the correct settings
