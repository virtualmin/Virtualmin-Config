#!/usr/bin/env bash
set -euo pipefail

packaging_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packaging/lib.sh
source "$packaging_dir/lib.sh"

usage() {
  cat <<'USAGE'
Usage: build-rpm.sh [--version VERSION] [--rpmbuild-root DIR] [--output-dir DIR]

Options:
  --version VERSION      Override detected version
  --rpmbuild-root DIR    rpmbuild root (default: ./build/rpmbuild)
  --output-dir DIR       Copy resulting RPMs to DIR
USAGE
}

out_dir="${OUT_DIR:-}"
rpmbuild_root="${RPMBUILD_ROOT:-$root_dir/build/rpmbuild}"
version="${VERSION:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      out_dir="$2"
      shift 2
      ;;
    --rpmbuild-root)
      rpmbuild_root="$2"
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

mkdir -p "$rpmbuild_root"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

"$packaging_dir/build-tarball.sh" --output-dir "$rpmbuild_root/SOURCES" --version "$version" >/dev/null

spec_in="$root_dir/virtualmin-config.spec"
spec_out="$rpmbuild_root/SPECS/virtualmin-config.spec"

sed -E "s/^Version:[[:space:]]+.*/Version:        $version/" "$spec_in" > "$spec_out"

rpmbuild -ba --define "_topdir $rpmbuild_root" "$spec_out"

if [[ -n "$out_dir" ]]; then
  mkdir -p "$out_dir"
  find "$rpmbuild_root/RPMS" "$rpmbuild_root/SRPMS" -type f -name '*.rpm' -exec cp -a {} "$out_dir/" \;
  printf '%s\n' "$out_dir"
else
  printf '%s\n' "$rpmbuild_root"
fi
