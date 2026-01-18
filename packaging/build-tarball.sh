#!/usr/bin/env bash
set -euo pipefail

packaging_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packaging/lib.sh
source "$packaging_dir/lib.sh"

usage() {
  cat <<'USAGE'
Usage: build-tarball.sh [--version VERSION] [--output-dir DIR]

Options:
  --version VERSION   Override detected version
  --output-dir DIR    Output directory (default: ./dist)
USAGE
}

out_dir="${OUT_DIR:-}"
version="${VERSION:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      out_dir="$2"
      shift 2
      ;;
    --version)
      version="$2"
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

if [[ -z "$version" ]]; then
  version="$(get_version)" || {
    echo "Unable to determine version; set VERSION or --version." >&2
    exit 1
  }
fi

out_dir="${out_dir:-$root_dir/dist}"
mkdir -p "$out_dir"

pkg_name="Virtualmin-Config"
prefix="${pkg_name}-${version}"
out_file="$out_dir/${prefix}.tar.gz"

if git -C "$root_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$root_dir" archive --format=tar --prefix "${prefix}/" HEAD | gzip -n > "$out_file"
else
  tar -C "$root_dir" -czf "$out_file" \
    --transform "s,^,${prefix}/," \
    --exclude="./dist" \
    --exclude="./build" \
    --exclude="./.git" \
    .
fi

printf '%s\n' "$out_file"
