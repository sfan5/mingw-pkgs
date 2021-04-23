mingw-pkgs
-----------

A collection of scripts to cross-compile various libraries, tools, applications to Windows via MinGW.

Supports both `i686-w64-mingw32` and `x86_64-w64-mingw32`.

Package scripts are ran indiviudually and produce a `name-X.Y.Z-win??.zip` archive upon completion.
These archives contain an unix-like `bin`, `include`, `lib` folder structure (DLLs go in `bin`).
