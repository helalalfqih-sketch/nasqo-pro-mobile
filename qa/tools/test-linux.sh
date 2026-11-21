#!/usr/bin/env bash
# Some Linux runtime images only ship the versioned SQLite library. Make
# the loader name required by Dart FFI available to this process tree only.
set -eu
libdir=$(mktemp -d)
trap 'rmdir "$libdir" 2>/dev/null || { unlink "$libdir/libsqlite3.so"; rmdir "$libdir"; }' EXIT
if ! python3 -c "import ctypes;ctypes.CDLL('libsqlite3.so')" 2>/dev/null; then
  lib=$(/sbin/ldconfig -p | awk '$1=="libsqlite3.so.0" {print $NF; exit}')
  test -f "$lib" || { echo 'Install the SQLite runtime in the test environment' >&2; exit 1; }
  ln -s "$lib" "$libdir/libsqlite3.so"
  export LD_LIBRARY_PATH="$libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
flutter test --no-pub -j 1 --reporter expanded "$@"
