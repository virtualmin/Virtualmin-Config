#!/usr/bin/env bash

packaging_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$packaging_dir/.." && pwd)"

get_version() {
  if [[ -n "${VERSION:-}" ]]; then
    printf '%s\n' "$VERSION"
    return 0
  fi

  if [[ -f "$root_dir/Makefile.PL" ]]; then
    local v
    v="$(perl -ne 'if (/\bVERSION\s*=>\s*"([^"]+)"/) {print $1; exit}' "$root_dir/Makefile.PL")"
    if [[ -n "$v" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi

  return 1
}
