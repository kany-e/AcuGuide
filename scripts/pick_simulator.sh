#!/bin/sh
# Print the name of an available iPhone simulator, for `make test`'s -destination.
#
# This lives in a script rather than inline in the Makefile on purpose: the device-name pattern
# needs a literal "(" (device lines read `iPhone 16 Pro (UUID) (Shutdown)`, so the name is the part
# BEFORE the first paren), and an unbalanced "(" inside a Makefile `$(shell ...)` call makes GNU
# make stop with "unterminated call to function `shell': missing `)'". Because `?=` defers
# expansion, that error only fired when `make test` actually used $(SIM) — so `make project` and
# `make build` kept working and the breakage hid until someone ran the documented test gate.
#
# Prefers the newest iPhone by numeric model, so a machine with several runtimes picks a modern
# device instead of whatever sorts first alphabetically.
set -eu

xcrun simctl list devices available \
  | sed -n 's/^[[:space:]]*\(iPhone[^(]*\) (.*/\1/p' \
  | sed 's/[[:space:]]*$//' \
  | awk '{ n = $2 + 0; print n "\t" $0 }' \
  | sort -k1,1nr -s \
  | head -1 \
  | cut -f2-
