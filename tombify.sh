#!/bin/sh
#
set -euf -o pipefail

die() {
  local rc="$1" ; shift
  echo "$@" 1>&2
  exit $rc
}

[ $# -ne 2 ] && die 5 "Usage: $0 [input-dir] [output-dir]"

inp_dir="$1"
out_dir="$2"

[ ! -d "$inp_dir" ] && die 10 "$inp_dir: not found!"
[ ! -d "$out_dir" ] && die 10 "$out_dir: not found!"

check_tomb() {
  local file="$1" dir="$2"
  [ ! -f "$file" ] && return 0
  find "$dir" -type f | while read src
  do
    [ "$file" -nt "$src" ] && continue
    # $file is not newer than $src!
    return 0
  done
  # Nothing to be done...
  return 1
}
    
mntd=""
cleanup() {
  [ -z "$mntd" ] && return
  umount "$mntd" || :
  rmdir "$mntd"
  mntd=""
}
trap "cleanup" EXIT

find "$inp_dir" -mindepth 1 -maxdepth 1 -type d | while read dir
do
  name="$(basename "$dir" .d)"
  vfat="$out_dir/$name.vfat"
  if check_tomb "$vfat" "$dir" ; then
    rm -f "$vfat"
    truncate -s $(expr 32 \* 1024 \* 1024) "$vfat"
    echo mkdosfs -n "$name" "$vfat"
    
    mntd=$(mktemp -d)
    echo mount -o loop -t vfat "$vfat" "$mntd"
    
    ln=$(expr $(expr length "$dir") + 2)
    
    find "$dir" | while read fp
    do
      rp=$(expr substr "$fp" "$ln" $(expr length "$fp")) || :
      [ -z "$rp" ] && continue

      if [ -d "$fp" ] ; then
	echo mkdir $mntd/$rp
      else
	echo cp $fp $mntd/$rp
      fi
    done
    
    cleanup
  fi
done

