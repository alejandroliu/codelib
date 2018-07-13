#!/bin/sh
#
# Create a USB from ISO
#
set -euf -o pipefail

#
# Functions
#
stderr() {
  echo "$@" 1>&2
}
die() {
  local rc="$1" ; shift
  stderr "$@"
  exit $rc
}

debug() {
  echo "$@" 1>&2
}

calc_part_size() {
  # Pick one based on the device size...
  local usbdev="$1"
  
  local dsize=$(awk '$4 == "'$(basename "$usbdev")'" { print $3/1024 }' /proc/partitions)
  if [ -n "$dsize" ] ; then
    if [ $dsize -gt $part_max ] ; then # We really don't need more than 8 GB
      echo $part_max
    else
      # Take 32 Megs off for overhead...
      echo $(expr $dsize - 32)
    fi
  fi
}

check_part_size() {
  local psize="$1" iso="$2"
  # Make sure that the size specified is OK   
  local minsz=$(expr $(expr $(stat -c '%s' "$iso") / 1024 / 1024) '*' 2)
  # Size of ISO x 2... the extra space is for ovl and updates...

  [ "$minsz" -gt "$psize" ] && die 91 "Partition size $psize is less than required $minsz"
  debug "minsz=$minsz psiz=$psize"
}

check_iso() {
  local iso="$1" version_r="$2" vtag_r="$3" label_r="$4"
  
  local tmp1=$(mktemp -d)
  trap "$root umount $tmp1 >/dev/null 2>&1; rmdir $tmp1" EXIT
  $root mount -r "$iso" "$tmp1" || exit 16
  [ ! -f "$tmp1/.alpine-release" ] && die 54 "$iso: not an Alpine ISO image"
  local id=$(cat $tmp1/.alpine-release)
  $root umount $tmp1 >/dev/null 2>&1 ; sync;sync ; rmdir $tmp1
  trap '' EXIT

  debug "$iso: $id"

  local alpine_version_str=$(echo $id | sed -e 's/^alpine-//' | sed -e 's/^[^-]*-//' | awk '{print $1}')
  local vtag_str=$(echo $alpine_version_str | cut -d. -f1-2)
  local label_str="ALPINE$alpine_version_str"
  
  eval "${version_r}=\"\$alpine_version_str\" ; ${vtag_r}=\"\$vtag_str\" ; ${label_r}=\"\$label_str\""
}



#
# parse command line arguments
#
part_size=""
part_max=8192
update=true

while [ $# -gt 0 ]
do
  case "$1" in
  --no-update)
    update=false
    ;;
  --update)
    update=true
    ;;
  --partsize=*)
    part_size=${1#--partsize=}
    ;;
  *)
    break
    ;;
  esac
  shift
done

if [ $# -lt 2 ] ; then
  cat 2>&1 <<-EOF
	Usage:
	    $0 [--part_size=MEGS --[no-]update] isofile /dev/usbhdd [path-to-ovl]
	Options:
	  --partsize=value: Partition size in Megs
	    If not specified it defaults to entire drive up to 8GB.
	  --[no-]update
	    Include files to update Alpine
	  isofile : ISO file to use as the base alpine install
	  usbhdd : /dev/path to the thumb drive (full disc) that will be installed.
	  path-to-ovl: Path to the backup OVL file used to initialize
	  system.

	The script will invoke "sudo" automatically if needed.
	EOF
  exit 1
fi

iso="$1"
usbdev="$2"
[ $# -gt 2 ] && ovl="$3" || ovl=""

[ ! -f "$iso" ] && die 56 "$iso: not found"
[ ! -e "$usbdev" ] && die 57 "$usbdev: not found"
[ ! -b "$usbdev" ] && die 58 "$usbdev: not a block device"
if [ -n "$ovl" ] ; then
  [ ! -f "$ovl" ] && die 59 "$ovl: not found"
fi

if [ $(id -u) -eq 0 ] ; then
  root=""
else
  root="sudo"
fi

if [ -z "$part_size" ] ; then
  part_size=$(calc_part_size $usbdev)
fi
check_part_size "$part_size" "$iso"


if [ -d /usr/lib/syslinux/bios ] ; then
  syslinux_dir=/usr/lib/syslinux/bios
elif [ -d /usr/share/syslinux ] ; then
  syslinux_dir=/usr/share/syslinux
else
  die 6 "Unknown syslinux"
fi

check_iso "$iso" alpine_version vtag label
[ -z "$vtag" ] && update=false

#
# Prepare USB key
#
# Erase drive
$root dd if=/dev/zero of="$usbdev" bs=512 count=200
$root sgdisk --zap-all "$usbdev" || :
# Create bootloader
$root dd bs=440 conv=notrunc count=1 if="$syslinux_dir/gptmbr.bin" of="$usbdev" || exit 1
# GPT partitioning...
$root sgdisk -n 1:0:+${part_size}M "$usbdev"	# Create partition
$root sgdisk -t 1:ef00 "$usbdev"		# Mark partition as ESP
$root sgdisk --attributes=1:set:2 "$usbdev"	# Mark partition as Legacy BOOT
	
[ ! -b "${usbdev}1" ] && die 50 "Failed to create partition"
# Format partition
$root mkfs.vfat -F 32 -n "$label" -v "${usbdev}1"

# Install syslinux
$root syslinux --install "${usbdev}1"


# Populate filestyems...
tmpdst=$(mktemp -d)
$root mount "${usbdev}1" "$tmpdst"
tmpsrc=$(mktemp -d)
trap "$root umount $tmpdst || : ; $root umount $tmpsrc || :; rmdir $tmpdst $tmpsrc || $root rm -rf $tmpsrc" EXIT

$root mount -r "$iso" "$tmpsrc"
# Copy files
stderr "Copy files from ISO"
$root cp -r $(find "$tmpsrc" -maxdepth 1 -mindepth 1) "$tmpdst"
$root umount "$tmpsrc"
trap "$root umount $tmpdst || : ; rmdir $tmpdst  ; $root rm -rf $tmpsrc" EXIT

# Make sure there is a cache directory...
$root mkdir -p "$tmpdst/cache"

# Fix c32 files
target="$tmpdst/boot/syslinux"
stderr -n Fixing binaries:
if [ -d "$target" ] ; then
  find "$target" -maxdepth 1 -mindepth 1 -type f | while read c32
  do
    [ ! -f $c32 ] && continue
    current="$(basename "$c32")"
    if [ -f "$syslinux_dir/$current" ] ; then
      stderr -n '' "$current"
      $root cp -r "$syslinux_dir/$current" "$c32"
    fi
  done
  echo ''
fi


if [ -n "$ovl" ] ; then
  stderr "Injecting $ovl"

  if $update ; then
    $root tar -zxf "$ovl" -C "$tmpsrc"
    $root sed -i \
      -e 's!/v[0-9]\.[0-9]/!/v'"$vtag"'/!' "$tmpsrc/etc/apk/repositories"
    disable_local=""
    if [ ! -L "$tmpsrc/etc/runlevels/default/local" ] ; then
      disable_local="rm -f /etc/runlevels/default/local # disable local"
      $root ln -s /etc/init.d/local "$tmpsrc/etc/runlevels/default/local"
    fi
    $root mkdir -p "$tmpsrc/etc/local.d"
    s=1 ; tmpl="etc/local.d/z%04d.start"
    while [ -f "$tmpsrc/$(printf $tmpl $s)" ]
    do
      s=$(expr $s + 1)
    done
    script=$(printf $tmpl $s)

    $root dd of="$tmpsrc/$script" <<-EOF
	#!/bin/sh
	echo "PERFORMING POST-UPGRADE TASKS" >/dev/tty1
	exec >/dev/tty1 2>/dev/tty1
	$disable_local
	rm -f /$script
	apk update
	apk upgrade --available
	apk cache clean
	lbu ci
	echo reboot
	EOF
    $root chmod 755 "$tmpsrc/$script"

    # Fix fstab for referenced to changing label...
    $root sed -i -e 's/LABEL=ALPINE[.0-9]*/LABEL='"$label"'/' "$tmpsrc/etc/fstab"

    $root tar -zcf "$tmpdst/$(basename "$ovl")" -C "$tmpsrc" .
  else
    $root cp "$ovl" "$tmpdst"
  fi
fi
