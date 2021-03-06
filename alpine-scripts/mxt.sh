#!/bin/sh
##
## This script contains some utilities to manage xen on alpine
##
src=http://ow1.localnet/v1/alpine/scripts/mxt.sh
def_bridge="4,mac=auto"
def_vg=flvg0
def_hd="hd,1,16G"

# Select from: http://standards-oui.ieee.org/oui/oui.txt
# Random OUI
oui_random="44:d2:ca"
oui_prefix="b8:78:79"
oui_changed="d8:60:b0"

######################################################################
msg() {
  echo "$@" 1>&2
}
fatal() {
  local code="$1" ; shift
  msg "$@"
  exit $code
}
fixfile() {
  if [ -n "$dryrun" ] ; then
    cat
  else
    cat >"$1"
  fi
}
random_hex() {
  echo $(od -An -N1 -t x1 /dev/urandom)
}
normalize_vmname() {
  local prefix="/etc/xen/"
  local suffix=".cfg"
  while [ $# -gt 0 ]
  do
    case "$1" in
      --prefix=*)
	prefix=${1#--prefix=}
	;;
      --suffix=*)
	suffix=${1#--suffix=}
	;;
      --name)
	prefix=''
	suffix=''
	;;
      --cfg)
	prefix='/etc/xen/'
	suffix='.cfg'
	;;
      *)
	break
    esac
    shift
  done
  [ $# -ne 1 ] && return
  [ -z "$1" ] && return
  local vmname="$(basename "$1" .cfg)"
  echo "$prefix$vmname$suffix"
}

######################################################################

##
## # Commands
##

update() {
  ## ## update
  ##
  ## Updates the utility script
  ##
  script=$(mktemp)
  trap "rm -f $script" EXIT
  wget -O$script $src || exit 1
  mv -f "$0" "$0".bak
  mv $script "$0"
  chmod +x "$0"
  lbu ci
}

######################################################################

help() {
  ## ## help
  ##
  ## Show this help message
  ##
  cat "$0" |grep -v -E '^\s*###+$' | grep -E '^\s*##' \
    | sed -e 's/^[ 	]*## *//' | more
}

######################################################################

vmcfg() {
  ## ## vmcfg
  ##
  ## VM configurator
  ##
  ## Usage:	vmcfg {vm=name} {type=pvrun|pvinst|hvm} [...options...]
  ##		vmcfg vars
  ##
  #+vmcfg
  #
  # Default settings
  #
  mem=1024
  vcpus=1
  vm=		# Mandatory
  type=hvm	# Options: pvinst, pvrun, hvm
  dryrun=1	# Defaults to only show commands (use do to execute)
  vg=$def_vg
  rem="Configuration generated by mxt/vmcfg ($(date))"

  # Virtual devices...
  net=""
  hd=""
  serial="pty"

  # HVM specific options
  hdtype=ahci
  vnc=1
  vnclisten="0.0.0.0"
  boot=""
  viridian=""

  # PVINST specific options
  ksurl="http://ow1.localnet/cgi-bin/ksgen.cgi/host=%s/ks=kspv.cfg"
  booturl="http://ow1.localnet/v1/"
  kernel="centos-7/7-os-x86_64/images/pxeboot/vmlinuz"
  ramdisk="centos-7/7-os-x86_64/images/pxeboot/initrd.img"
  ksopts="text"
  inst=""
  localtime=0
  #-vmcfg

  if [ x"$*" = x"vars" ] ; then
    exec <$0
    local L
    while read L
    do
      [ x"$L" = x"#+vmcfg" ] && break
    done
    while read L
    do
      [ x"$L" = x"#-vmcfg" ] && break
      echo "$L"
    done
    exit
  fi

  local i
  ##
  ## Options:
  ##
  for i in "$@"
  do
    case "$i" in
      do)
	## - do : execute commands
	dryrun=
	;;
      net=*)
	## - net=<vlan-id> : add a network interface
	vmcfg_net ${i#net=}
	;;
      cdrom=*)
	## - cdrom=<lun>,<path-to-iso> : add cdrom image
	vmcfg_hd sr,${i#cdrom=}
	;;
      hd=*)
	## - hd=<lun>,<size|path-to-image> : add a ide drive
	vmcfg_hd hd,${i#hd=}
	;;
      sd=*)
	## - sd=lun,<size|path-to-image> : add a scsi drive
	vmcfg_hd sd,${i#sd=}
	;;
      xvd=*)
	## - vd=lun,<size|path-to-imate> : add a PV drive
	vmcfg_hd xvd,${i#xvd=}
	;;
      rem=*)
	## - rem="value" : comments...
	rem="${i#rem=}"
	;;
      *=*)
	## - <var>=<value> : define settings
	eval $i
	;;
      -*)
	## - -<var> : remove|reset setting
	i=${i#-}
	eval $i=\"\"
	;;
      *)
	## - <var> : set <var> to yes
	eval $i="yes"
	;;
    esac
  done

  vm=$(normalize_vmname --name "$vm")

  [ -z "$vm" ] && fatal 2 "Must specify vm=name"
  [ -z "$type" ] && fatal 3 "Must specify type pvrun, pvinst or hvm"
  [ -z "$net" ] && vmcfg_net $def_bridge
  [ -z "$hd" ] && vmcfg_hd hd,1,16G

  [ "$type" != "hvm" ] && serial= # For non HVM, disable serial emulation...

  

  #
  # Configure LVMs
  #
  disks=""
  vmcfg_lvm $hd

  #
  # Genreate xen configuration
  #
  fixfile /etc/xen/$vm.cfg <<-EOF
	#R $rem
	name = "$vm"
	memory = $mem
	vcpus = $vcpus

	$(vmgen_nets)
	$(vmgen_disks)
	$(vmgen_$type)
	$([ -n "$serial" ] && echo "serial = '$serial'")
	EOF
}
#
# VMCFG sub routines...
#
print_stanzas() {
  local lines=""
  local i
  for i in "$@"
  do
    if [ -z "$lines" ] ; then
      lines="\\t'$i'"
    else
      lines="$lines,\\n\\t'$i'"
    fi
  done
  echo -e "$lines"
}
vmcfg_net() {
  local spec="$1" q="" i

  local oIFS="$IFS"
  IFS=","
  set - $spec
  IFS="$oIFS"

  spec=""
  for i in "$@"
  do
    [ -z "$i" ] && continue
    # Single integers are handled specially
    [ x"$(echo "$i" | tr -dc 0-9)" = x"$i" ] && i="bridge=$i"

    case "$i" in
      mac=auto)
	# Handle random MAC addresses
	i=mac=$oui_random:$(random_hex):$(random_hex):$(random_hex)
	;;
      mac=??:??:??)
	# Handle un-prefixed MAC addresses
	i=mac=$oui_prefix:${i#mac=}
	;;
    esac

    spec="$spec$q$i"
    q=","
  done
  
  [ -z "$spec" ] && return
  
  if [ -z "$net" ] ; then
    net="$spec"
  else
    net="$net $spec"
  fi
}
vmcfg_hd() {
  if [ -z "$hd" ] ; then
    hd="$*"
  else
    hd="$hd $*"
  fi
}
vmcfg_lvm() {
  local i
  for i in "$@"
  do
    local vtype=$(echo $i | cut -d, -f1)
    local lun=$(echo $i | cut -d, -f2)
    local sz=$(echo $i | cut -d, -f3)

    local devtype=""
    if [ -e $sz ] ; then
      # This is an existing image file...
      local lv=$sz
      local access=r
      [ x"$vtype" = x"sr" ] && devtype=",devtype=cdrom"
    else
      check_sz $sz || fatal 5 "$i: size must be a number"
      local lv=/dev/$vg/$vm-v$lun
      local access=w
      [ x"$vtype" = x"sr" ] && fatal 2 "cdrom: must specify a iso file path"
    fi
    spec="format=raw,vdev=$(vmcfg_vdev $vtype $lun),access=$access$devtype,target=$lv"
    if [ -z "$disks" ] ; then
      disks="$spec"
    else
      disks="$disks $spec"
    fi
    [ -e $lv ] && continue
    if [ -n "$dryrun" ] ; then
      echo lvcreate -n $vm-v$lun -L $sz $vg
    else
      lvcreate -n $vm-v$lun -L $sz $vg || exit 1
    fi
  done
}
vmcfg_vdev() {
  local dtype="$1"
  local lun="$2"
  local hlun=$(printf "%x" $(expr $lun + 96))
  local letter=$(echo -e "\\x$hlun")

  case "$dtype" in
    sr)
      echo "hd$letter"
      ;;
    *)
      echo "$dtype$letter"
  esac
}

vmgen_nets() {
  [ -z "$net" ] && return
  echo "vif = ["
  print_stanzas $net
  echo "]"
}
vmgen_disks() {
  [ -z "$disks" ] && return
  echo "disk = ["
  print_stanzas $disks
  echo "]"
}
vmgen_pvrun() {
  echo "bootloader = 'pygrub'"
}
vmgen_pvinst() {
  local kscfg="$(printf $ksurl $vm)"
  if [ -n "$inst" ] ; then
    case "$inst" in
      c7)
	kernel="centos-7/7-os-x86_64/images/pxeboot/vmlinuz"
	ramdisk="centos-7/7-os-x86_64/images/pxeboot/initrd.img"
	;;
    esac
  fi
  cat <<-EOF
	bootloader = "xenpvnetboot"
	bootloader_args = [
	  "--location=$booturl",
	  "--args=ks=$kscfg $ksopts"
	]
	kernel = "$kernel"
	ramdisk = "$ramdisk"
	on_poweroff = "destroy"
	on_reboot = "destroy"
	on_crash = "destroy"
	localtime = $localtime
	EOF
}
vmgen_hvm() {
  echo "builder = 'hvm'"
  echo "hdtype = '$hdtype'"
  echo "vnc = $vnc"
  echo "vnclisten = '$vnclisten'"
  echo "usb=1"
  echo "usbdevice=['tablet']"
  [ -n "$viridian" ] && echo "viridian = 1"
  [ -n "$boot" ] && echo "boot = '$boot'"
}

check_sz() {
  local sz="$1" suffix
  local num="$(echo $sz | tr -dc 0-9)"

  [ x"$sz" = x"$num" ] && return 0

  for suffix in g G m M k K t T
  do
    [ x"$sz" = x"$num$suffix" ] && return 0
  done
  return 1
}

######################################################################
##
clone() {
  ## ## clone
  ##
  ## VM cloner
  ##
  ## Usage:	clone [--exec] [--thin|--full][---keep-macs] {srcvm} [dstvm} [do]
  ##
  dryrun=1
  copy=thin
  change_macs=true

  while [ $# -gt 2 ]
  do
    case "$1" in
      do|-r|--exec)
	dryrun=
	;;
      -f|--full)
	copy=full
	;;
      -t|--thin)
	copy=thin
	;;
      -m|--keep-macs)
	change_macs=false
	;;
      *)
	break;
    esac
    shift
  done

  if [ $# -eq 3 -a x"$3" = x"do" ] ; then
    dryrun=
    set - "$1" "$2"
  fi

  [ $# -ne 2 ] && fatal 10 "Usage: clone <srcvm> <dstvm>"

  srcvm="$(normalize_vmname --name "$1")"
  dstvm="$(normalize_vmname --name "$2")"

  # Check if cfg exists
  #srccfg="/etc/xen/$srcvm.cfg" 
  #dstcfg="/etc/xen/$dstvm.cfg"
  # TODO
  srccfg="$srcvm.cfg"
  dstcfg="$dstvm.cfg"

  [ -f "$srccfg" ] || fatal 7 "$srccfg: not found"
  [ -f "$dstcfg" ] && fatal 8 "$dstcfg: already exists"

  # Clone devices
  exec 4>&1
  sed -e 's/^/:/' < $srccfg | (
    exec 3>&1 1>&4
    exec 4>&-
    while read ln
    do
      if (echo "$ln" | grep -q '^:\s*name\s*=\s*') ; then
	echo ":name = '$dstvm'" 1>&3
      elif (echo "$ln" | grep -q '^:\s*vif\s*=\s*\[\s*$') ; then
	echo "$ln" 1>&3
	$change_macs || continue
	clone_vif
      elif (echo "$ln" | grep -q '^:\s*disk\s*=\s*\[\s*$') ; then
	echo "$ln" 1>&3
	clone_luns "$copy" "$dryrun"
      else
	echo "$ln" 1>&3
      fi
    done
  ) | (
    if [ -n "$dryrun" ] ; then
      file="$(cat)"
      echo "=== $dstcfg ==="
      echo "$file"
      exit
    fi
    echo "Creating $dstcfg" 1>&2
    sed -e 's/^://' > $dstcfg
  )
}

clone_luns() {
  local copy="$1" dryrun="$2"
  while read ln
  do
    if (echo "$ln" | grep -q '^:\s*\]\s*$') ; then
      echo "$ln" 1>&3
      break
    fi
    if (echo "$ln" | grep -q access=r,) ; then
      echo "$ln" 1>&3
      continue
    fi

    srcdev=$(echo "$ln" | sed -e 's/^.*,target=//' | tr -d \',)
    [ -e $srcdev ] || fatal 9 "$srcdev: not found"
    if [ ! -b $srcdev ] ; then
      # Not a block device... it is an image file...
      echo "$ln" 1>&3
      continue
    fi

    dstdev=$(echo $srcdev | sed -e "s!/$srcvm-!/$dstvm-!")
    [ -e $dstdev ] && fatal 8 "$dstdev: already exists"

    size=$(clone_lvsize "$srcdev")

    ln1=$(echo "$ln" | sed -e 's/^\(.*,target=\).*$/\1/')
    ln2=$(echo "$ln" | sed -e 's!^.*,target='$srcdev'!!')
    echo "$ln1$dstdev$ln2" 1>&3

    if [ -n "$dryrun" ] ; then
      echo "$srcdev -> $dstdev ($copy:$size:dryrun)" 1>&2
      continue
    fi

    echo "$srcdev -> $dstdev ($copy:$size:execute)" 1>&2
    case "$copy" in
      full)
	lvcreate \
	  -n $(basename $dstdev) -l $size $(dirname $dstdev) 3>&- ||exit 1
	dd if=$srcdev of=$dstdev bs=1M
	;;
      thin)
	lvcreate -n $(basename $dstdev) -l $size -s $srcdev 3>&- || exit 1
	;;
      *)
	fatal 7 "Invalid cloning mode: $copy"
	;;
    esac
  done
}

clone_lvsize() {
  lvdisplay -c "$1" 3>&- | cut -d: -f 8
}

clone_vif() {
  while read ln
  do
    if (echo "$ln" | grep -q '^:\s*\]\s*$') ; then
      echo "$ln" 1>&3
      break
    fi
    if (echo "$ln" | grep -q "[,'\"]mac=") ; then
      clone_fix_mac_addr "$ln"
      continue
    fi
    echo "$ln" 1>&3
  done
}

clone_fix_mac_addr() {
  local ln="$*"

  # Determine it it is a random or assigned MAC
  if (echo "$ln" | grep -q "[,'\"]mac=$oui_random") ; then
    local new_oui=$oui_random
  else
    local new_oui=$oui_changed
  fi
  echo "$ln" \
    | sed 's/\([,'\''"]\)mac=..:..:..:..:..:../\1mac='"$new_oui:$(random_hex):$(random_hex):$(random_hex)"'/' \
    1>&3
}

vnc() {
  ## ## vnc
  ##
  ## Show the vncdisplay number
  ##
  ## Usage:	vnc [vm]
  ##
  vncviewer=/usr/bin/vncviewer
  if [ ! -x $vncviewer ] ; then
    cat >$vncviewer <<-'EOF'
	#!/bin/sh
	echo "$@"
	EOF
    chmod 755 $vncviewer
  fi
  xl vncviewer "$@"
}


genmac() {
  ## ## genmac
  ##
  ## Generate a MAC address
  ##
  ## Usage:	genmac [xx:xx:xx]
  ##
  if [ $# -eq 0 ] ; then
    echo $oui_random:$(random_hex):$(random_hex):$(random_hex)
  else
    echo $oui_prefix:"$1"
  fi
}

######################################################################
# Dispatch commands
######################################################################
[ $# -eq 0 ] && fatal 1 "Must specify sub-command (try help)"

"$@"
exit 0
