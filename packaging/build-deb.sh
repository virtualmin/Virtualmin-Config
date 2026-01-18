#!/usr/bin/env bash
set -euo pipefail

packaging_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packaging/lib.sh
source "$packaging_dir/lib.sh"

usage() {
  cat <<'USAGE'
Usage: build-deb.sh [--output-dir DIR]

Options:
  --output-dir DIR  Copy resulting artifacts to DIR
USAGE
}

out_dir="${OUT_DIR:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      out_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

version="$(get_version 2>/dev/null || true)"
changelog_version=""

if command -v dpkg-parsechangelog >/dev/null 2>&1; then
  changelog_version="$(dpkg-parsechangelog -S Version 2>/dev/null || true)"
else
  changelog_version="$(perl -ne 'if (/^\S+ \(([^)]+)\)/) {print $1; exit}' "$root_dir/debian/changelog")"
fi

if [[ -n "$version" && -n "$changelog_version" && "$version" != "$changelog_version" ]]; then
  echo "Warning: dist.ini/Makefile.PL version ($version) differs from debian/changelog ($changelog_version)." >&2
fi

cd "$root_dir"
dpkg-buildpackage -us -uc -b

if [[ -n "$out_dir" ]]; then
  mkdir -p "$out_dir"
  pkg_name="virtualmin-config"
  find "$root_dir/.." -maxdepth 1 -type f \( \
    -name "${pkg_name}_*.deb" -o \
    -name "${pkg_name}_*.buildinfo" -o \
    -name "${pkg_name}_*.changes" \
  \) -exec cp -a {} "$out_dir/" \;
  printf '%s\n' "$out_dir"
fi
