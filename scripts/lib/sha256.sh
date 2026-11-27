#!/usr/bin/env bash
# sha256_of FILE: print the hex sha256 of FILE. sha256sum on Linux, shasum on macOS.
sha256_of() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
}
