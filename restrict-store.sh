#!/bin/bash
# Keep Omatracker's per-day usage history private to the owning account.
#
# prepare / tighten:
#   tracker directory 0700, history file and corrupt backups 0600.
#   Exits 0 only after those modes are in place, so the caller may then read
#   or write. Seeds a missing history file with an empty, verified 0600 inode
#   so QSaveFile preserves that mode on its first atomic replacement too.
# quarantine:
#   same restrictions, then copy the history file to a sibling
#   data.json.corrupt-<digits> backup created at 0600.
#
# Symlinks are refused. chmod and Quickshell's atomic FileView follow them,
# which would either loosen some other inode or write history outside this
# directory. Paths are arguments, never interpolated into a shell string.

set -euo pipefail
export LC_ALL=C

# Default ACLs override umask at creation. Remove named access entries, replace
# inherited defaults with owner-only defaults, and verify both the ACL and mode.
# Refuse storage when these guarantees cannot be established.
verify_dir() {
  [[ $(stat -c %a -- "$1") == 700 ]]
  [[ $(getfacl -cpE -- "$1") == $'user::rwx\ngroup::---\nother::---\ndefault:user::rwx\ndefault:group::---\ndefault:other::---' ]]
}

verify_file() {
  [[ $(stat -c %a -- "$1") == 600 ]]
  [[ $(getfacl -cpE -- "$1") == $'user::rw-\ngroup::---\nother::---' ]]
}

usage() {
  echo "usage: restrict-store.sh prepare|tighten DIR FILE" >&2
  echo "       restrict-store.sh quarantine DIR FILE DEST" >&2
  exit 2
}

secure_dir() {
  local dir=$1
  if [[ -L $dir ]]; then
    echo "omatracker: tracker path is a symlink; not touching it" >&2
    return 1
  fi
  # -m sets the creation mode exactly; umask does not widen it. Existing
  # directories are not restated by mkdir, so chmod is what migrates them.
  mkdir -p -m 0700 -- "$dir"
  if [[ -L $dir || ! -d $dir || ! -O $dir ]]; then
    echo "omatracker: tracker path is not a directory" >&2
    return 1
  fi
  chmod 0700 -- "$dir"
  setfacl -b -k -- "$dir"
  setfacl -m d:u::rwx,d:g::---,d:o::--- -- "$dir"
  verify_dir "$dir"
}

secure_file() {
  local target=$1
  if [[ ! -e $target && ! -L $target ]]; then
    return 0
  fi
  if [[ -L $target ]]; then
    echo "omatracker: refusing to follow a symlink in the tracker directory" >&2
    return 1
  fi
  if [[ ! -f $target || ! -O $target || $(stat -c %h -- "$target") != 1 ]]; then
    echo "omatracker: tracker entry is not a regular file" >&2
    return 1
  fi
  chmod 0600 -- "$target"
  setfacl -b -- "$target"
  verify_file "$target"
}

secure_tree() {
  local dir=$1 file=$2
  [[ $dir == /* && $file == /* ]] || return 1
  [[ $file == "$dir/data.json" ]] || return 1
  # Drop group/other bits before creating or restating anything else.
  umask 077
  secure_dir "$dir"
  secure_file "$file"
  local backup
  shopt -s nullglob
  for backup in "$file".*; do
    secure_file "$backup"
  done
  shopt -u nullglob
  if [[ ! -e $file ]]; then
    # Never truncate an existing file. Only empty bytes exist before checking
    # that the filesystem enforces the requested mode and ACL.
    (set -o noclobber; : > "$file")
    secure_file "$file"
  fi
}

quarantine() {
  local dir=$1 file=$2 dest=$3
  [[ $dest == /* ]] || return 1
  # Digits only, so a destination cannot escape the tracker directory.
  [[ $dest == "$file".corrupt-+([0-9]) ]] || return 1
  secure_tree "$dir" "$file"
  if [[ -L $file || ! -f $file ]]; then
    echo "omatracker: no regular history file to quarantine" >&2
    return 1
  fi
  # Create and verify an empty destination BEFORE any private bytes are copied.
  # A collision fails rather than overwriting an earlier recovery copy.
  (set -o noclobber; : > "$dest")
  secure_file "$dest"
  cat -- "$file" > "$dest"
  verify_file "$dest"
}

[[ $# -ge 1 ]] || usage
shopt -s extglob

case $1 in
  prepare | tighten)
    [[ $# -eq 3 ]] || usage
    secure_tree "$2" "$3"
    ;;
  quarantine)
    [[ $# -eq 4 ]] || usage
    quarantine "$2" "$3" "$4"
    ;;
  *)
    usage
    ;;
esac
