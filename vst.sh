#!/bin/sh
#
set -euf -o pipefail

# Select from: http://standards-oui.ieee.org/oui/oui.txt
# Random OUI
oui_random="44:d2:ca"
oui_prefix="b8:78:79"
oui_changed="d8:60:b0"

random_hex() {
  echo $(od -An -N1 -t x1 /dev/urandom)
}

g_macaddr() {
  echo ${1:-$oui_random}:$(random_hex):$(random_hex):$(random_hex)
}

g_uuid() {
  if [ -f /proc/sys/kernel/random/uuid ] ; then
    cat /proc/sys/kernel/random/uuid
  else
    uuidgen
  fi
}

strip_hash_comments() {
  sed \
    -e 's/^\s*#.*$//' \
    -e 's/^\s*//' -e 's/\s*$//'
}
trim() {
  echo "$1"| sed -e 's/^\s*//' -e 's/\s*$//'
}

split_cfg_line() {
  local ln="$1"
  local i=1 j='' k=$(expr length "$ln")

  while [ $i -le $k ]
  do
    ch=$(expr substr "$ln" $i 1)
    if [ -z "$j" ] ; then
      # We are looking for the ":" separator...
      case "$ch" in
      :)
	# WE FOUND IT!
	local _left="$(expr substr "$ln" 1 $(expr $i - 1) | sed -e 's/\s*$//')"
	local _right=""
	[ $i -lt $k ] && _right="$(expr substr "$ln" $(expr $i + 1) $(expr $k - $i) | sed -e 's/^\s*//')"
	#~ echo "LEFT=<$_left>"
	#~ echo "RIGHT=<$_right>"
	[ -n "${2:-}" ] && eval ${2}=\"\$_left\"
	[ -n "${3:-}" ] && eval ${3}=\"\$_right\"
	return 0
	;;
      \\|\"|\')
	j="$ch"
	;;
      esac
    elif [ x"$(expr substr "$j" 1 1)" = x"\\" ] ; then
      # Backslash... we skip it...
      j=$(expr substr "$j" 2 1) || :
    elif [ x"$j" = x"'" -o x"$j" = x"\"" ] ; then
      if [ x"$ch" = x"$j" ] ; then
	# Close it...
	j=""
      elif [ x"$ch" = x"\\" ] ;then
	j="\\$j"
      fi
    fi
    i=$(expr $i + 1)
  done
  # Nothing found...
  return 1
}

pop_tag() {
  tag=$(set - $pops ; echo $1)
  pops=$(set - $pops ; shift ; echo $*)
  off="$(expr substr "$off" 1 $(expr $(expr length "$off") - 2))" || :
}

xmlgen() {
  local \
	off="" \
	pops="" \
	ln="" left="" right="" tag=""
  strip_hash_comments | (
    while read ln
    do
      [ -z "$ln" ] && continue
      if [ x"$ln" = x":" -o x"$ln" = x"/" ] ; then
	pop_tag
	echo "$off</$tag>"
      elif split_cfg_line "$ln" left right ; then
	# Found
	tag=$(echo "$left" | (read a b ; echo $a))
	if [ -z "$right" ] ; then
	  # Open tag...
	  echo "$off<$left>"
	  pops=$(echo $tag $pops)
	  off="  $off"
	else
	  # Single line content
	  echo "$off<$left>$right</$tag>"
	fi
      else
	# Self contained tag
	echo "$off<$ln />"
      fi
    done
    while [ -n "$pops" ]
    do
      pop_tag
      echo "$off</$tag>"
    done
  )
}


ymlgen() {
  local off=""
  local ln left right
  sed -e 's/^\s*//' -e 's/\s*$//' | (
    while read ln
    do
      [ -z "$ln" ] && continue
      if ((echo $ln | grep -q '^<') && (echo $ln | grep -q '>$')) ; then
	ln=$(echo $ln | sed -e 's/^<\s*//' -e 's/\s*>$//')
	if (echo $ln | grep -q '>.*<') ; then
	  left=$(echo "$ln" | cut -d'>' -f1)
	  right=$(echo "$ln" | cut -d'>' -f2- | sed -e 's/<\s*\/[^>]*$//')
	  echo "$off$left: $right"
	elif (echo $ln | grep -q '/$') ; then
	  echo "$off$(echo "$ln" | sed -e 's!\s*/$!!')"
	elif (echo $ln | grep -q '^/') ; then
	  off="$(expr substr "$off" 1 $(expr $(expr length "$off") - 2))"
	  echo "$off:"
	else
	  echo "$off$ln:"
	  off="$off  "
	fi
      else
	echo "Parser can not handle such complex XML!" 1>&2
	return 2
      fi
    done
  )
}
xmlparse() {
  local off="" prefix="${1:-CF}"
  local ln left right
  sed -e 's/^\s*//' -e 's/\s*$//' | (
    while read ln
    do
      ln=$(echo "$ln" | sed -e 's/^\s*//' -e 's/\s*$//')
      [ -z "$ln" ] && continue
      if ((echo $ln | grep -q '^<') && (echo $ln | grep -q '>$')) ; then
	ln=$(echo $ln | sed -e 's/^<\s*//' -e 's/\s*>$//')
	if (echo $ln | grep -q '>.*<') ; then
	  left=$(echo "$ln" | cut -d'>' -f1)
	  right=$(echo "$ln" | cut -d'>' -f2- | sed -e 's/<\s*\/[^>]*$//')
	  right=$(declare -p right | sed -e 's/^[^=]*//')
	  #right="='$right'"
	  for ln in $left
	  do
	    echo "${prefix}_${off}_$ln$right"
	    right=""
	  done
	elif (echo $ln | grep -q '/$') ; then
	  right="=1"
	  for left in $(echo $ln | sed 's/\/$//')
	  do
	    echo "${prefix}_${off}_$left$right"
	    right=""
	  done
	elif (echo $ln | grep -q '^/') ; then
	  off=$(
	    set - $(echo $off | tr '_' ' ')
	    o=""
	    while [ $# -gt 1 ]
	    do
	      if [ -z $o ] ; then
		o="$1"
	      else
		o="${o}_$1"
	      fi
	      shift
	    done
	    echo "$o"
	  )
	else
	  left="$(set - $ln ; echo "$1")"
	  echo "# $left ($off)"
	  if [ -z "$off" ] ; then
	    off="$left"
	  else
	    off="${off}_${left}"
	  fi
	  for right in $(set - $ln ; shift ; echo $*)
	  do
	    echo "${prefix}_${off}_${right}"
	  done
	fi
      else
	echo "Parser can not handle such complex XML!" 1>&2
	return 2
      fi
    done
  )
}

pp() {
  local eof="$$"
  eof="EOF_${eof}_EOF_${eof}_EOF_${eof}_EOF_${eof}_EOF"
  local txt="$(echo "cat <<$eof" ; cat ; echo '' ;echo "$eof")"
  eval "$txt"
}

"$@"

: xmlparse <<EOF
<domain type="kvm">
    <name>demo2</name>
    <uuid>4dea24b3-1d52-d8f3-2516-782e98a23fa0</uuid>
    <memory>131072</memory>
    <vcpu>1</vcpu>
    <os>
        <type arch="i686">hvm</type>
    </os>
    <clock sync="localtime"/>
    <devices>
        <emulator>/usr/bin/qemu-kvm</emulator>
        <disk type="file" device="disk">
            <source file="/var/lib/libvirt/images/demo2.img"/>
            <target dev="hda"/>
        </disk>
        <interface type="network">
            <source network="default"/>
            <mac address="24:42:53:21:52:45"/>
        </interface>
        <graphics type="vnc" port="-1"/>
    </devices>
</domain>
EOF



: <<EOF
# Comments
domain type="kvm":
  name: ts1
  uuid: $(g_uuid)
  memory unit="MiB": 1024
  vcpu: 1
  os:
    type arch="x86_64": hvm
    boot dev="network"
    boot dev="hd"
  :
  features:
    acpi
  :
  clock sync="utc"
  devices:
    #~ emulator: /usr/bin/qemu-kvm
    watchdog model="i6300esb"
    console type="pty":
      target type="serial"
    :
    graphics type="vnc" port="-1":
      listen type="address" address="0.0.0.0"
    :
    # Storage configuration
    disk type="block" device="disk":
      source dev="/dev/hdvg0/ts1-v1"
      target dev="vda"
    :
    # Network configuration
    #~ interface type="bridge":
      #~ source bridge="br0"
      #~ mac address="$(g_macaddr)"
      #~ model type="virtio"
    #~ :
    #~ interface type="bridge":
      #~ source bridge="br1"
      #~ mac address="$(g_macaddr)"
      #~ model type="virtio"
    #~ :
    #~ interface type="bridge":
      #~ source bridge="br2"
      #~ mac address="$(g_macaddr)"
      #~ model type="virtio"
    #~ :
    #~ interface type="bridge":
      #~ source bridge="br3"
      #~ mac address="$(g_macaddr)"
      #~ model type="virtio"
    #~ :
    interface type="bridge":
      source bridge="br4"
      mac address="$(g_macaddr)"
      model type="virtio"
    :
    #~ interface type="bridge":
      #~ source bridge="br5"
      #~ mac address="$(g_macaddr)"
      #~ model type="virtio"
    #~ :
EOF

: <<EOF
# Comments
domain type="kvm":
  name: rs1
  uuid: $(g_uuid)
  memory: 131072
  vcpu: 1
  os:
    type arch="x86_64": hvm
    boot dev="cdrom"
    boot dev="hd"
  :
  features:
    acpi
  :
  clock sync="utc"
  devices:
    #~ emulator: /usr/bin/qemu-kvm
    watchdog model="i6300esb"
    console type="pty":
      target type="serial"
    :
    graphics type="vnc" port="-1":
      listen type="address" address="0.0.0.0"
    :
    # Storage configuration
    disk type="block" device="disk":
      source dev="/dev/hdvg0/rs1-v1"
      target dev="vda"
    :
    #~ disk type="file" device="cdrom":
      #~ source file="/media/isolib/boot-cd/alpine-virt-3.7.0-x86_64.iso"
      #~ target dev="vdb"
    #~ :
    disk type="network" device="cdrom":
      source protocol="http" name="/alex/alpine-virt-3.7.0-x86_64.iso":
	host name="cvm1.localnet" port="80"
      :
      target dev="vdb"
    :
    disk type="file" device="disk":
      source file="/media/isolib/boot-parms/rs1.vfat"
      target dev="vdc"
    :

    # Network configuration
    #~ interface type="bridge":
      #~ source bridge="br0"
      #~ mac address="$(g_macaddr)"
      #~ model type="virtio"
    #~ :
    interface type="bridge":
      source bridge="br1"
      mac address="$(g_macaddr)"
      model type="virtio"
    :
    #~ interface type="bridge":
      #~ source bridge="br2"
      #~ mac address="$(g_macaddr)"
      #~ model type="virtio"
    #~ :
    #~ interface type="bridge":
      #~ source bridge="br3"
      #~ mac address="$(g_macaddr)"
      #~ model type="virtio"
    #~ :
    #~ interface type="bridge":
      #~ source bridge="br4"
      #~ mac address="$(g_macaddr)"
      #~ model type="virtio"
    #~ :
    #~ interface type="bridge":
      #~ source bridge="br5"
      #~ mac address="$(g_macaddr)"
      #~ model type="virtio"
    #~ :
EOF


: <<EOF
# Comments
domain type="kvm":
  name: ts1
  uuid: $(g_uuid)
  memory unit="MiB": 1024
  vcpu: 1
  os:
    type arch="x86_64": hvm
    boot dev="cdrom"
    boot dev="hd"
  :
  features:
    acpi
  :
  clock sync="utc"
  devices:
    #~ emulator: /usr/bin/qemu-kvm
    watchdog model="i6300esb"
    console type="pty":
      target type="serial"
    :
    graphics type="vnc" port="-1":
      listen type="address" address="0.0.0.0"
    :
    # Storage configuration
    disk type="block" device="disk":
      source dev="/dev/hdvg0/ts1-v1"
      target dev="vda"
    :
    disk type="network" device="cdrom":
      source protocol="http" name="/Files/Temp/isolib-installers/os/elementary/elementaryos-0.3.2-stable-amd64.20151209.iso":
	host name="alvm1.localnet" port="80"
      :
      target dev="vdb"
    :
    # Network configuration
    interface type="bridge":
      source bridge="br4"
      mac address="$(g_macaddr)"
      model type="virtio"
    :
EOF

m_error() {
  echo "# $*"
  echo "ERROR: $*" 1>&2
  return 0
}

m_parse() {
  local name="$1" ; shift
  local switch='case "$1" in'
  local i check=""
  for i in $opts
  do
    if (echo $i | grep -q '?$') ; then
      i=$(echo $i | sed -e 's/?$//')
    else
      if [ -z "$check" ] ; then
	check="$i"
      else
	check="$check $i"
      fi
    fi
    switch="$switch
	${i}=*) ${i}=\${1#$i=} ;; "
  done
  switch="$switch
	*) m_error \"$name: Invalid specification \\\"\$1\\\"\" ; return 1 ;;"
  switch="$switch
	esac"

  #echo "$switch"
  while [ $# -gt 0 ]
  do
    eval "$switch"
    shift
  done

  # Check if parameter is there...
  rc=0
  for i in $check
  do
    eval "local j=\${$i:-}"
    [ -n "$j" ] && continue
    rc=1
    m_error "$name: $i not specified"
  done

  return $rc
}

m_disc_block() {
  local vdev="" path=""
  local opts="vdev path"
  m_parse m_disc_block "$@" || return 1
  cat <<-_EOF_
    # Storage configuration
    disk type="block" device="disk":
      source dev="$path"
      target dev="$vdev"
    :
	_EOF_
}
m_disc_file() {
  local vdev="" file=""
  local opts="vdev file"
  m_parse m_disc_file "$@" || return 1
  cat <<-_EOF_
    disk type="file" device="disk":
      source file="$file"
      target dev="$vdev"
    :
	_EOF_
}

m_cdrom_local() {
  local vdev="" iso=""
  local opts="vdev iso"
  m_parse m_cdrom_local "$@" || return 1
  cat <<-_EOF_
    disk type="file" device="cdrom":
      source file="$iso"
      target dev="$vdev"
    :
	_EOF_
}
m_cdrom_http() {
  local vdev="" url=""
  local opts="vdev url"
  m_parse m_cdrom_http "$@" || return 1

  local proto=$(echo "$url" | cut -d: -f1)
  local path=$(echo "$url" | cut -d: -f2- | sed -e 's!^//!!')
  local host=$(echo "$path" | cut -d/ -f1) port=80
  path=/$(echo "$path" | cut -d/ -f2-)
  if (echo $host | grep -q :) ; then
    port=$(echo $host | cut -d: -f2-)
    host=$(echo $host | cut -d: -f1)
  fi
  cat <<-_EOF_
    disk type="network" device="cdrom":
      source protocol="$proto" name="$path":
	host name="$host" port="$port"
      :
      target dev="$vdev"
    :
	_EOF_
}

m_net_brnic() {
  local br=br0 mac="" type="virtio"
  local opts="br mac? type"
  m_parse m_net_brnic "$@" || return 1
  [ -z "$mac" ] && mac=$(g_macaddr)
  [ $(expr length "$mac") -eq 8 ] && mac="$oui_prefix:$mac"

  cat <<-_EOF_
    interface type="bridge":
      source bridge="$br"
      mac address="$mac"
      model type="$type"
    :
	_EOF_
}
(pp | xmlgen) <<EOF
# Comments
domain type="kvm":
  name: ts1
  uuid: $(g_uuid)
  memory unit="MiB": 1024
  vcpu: 1
  os:
    type arch="x86_64": hvm
    boot dev="cdrom"
    boot dev="hd"
  :
  features:
    acpi
  :
  clock sync="utc"
  devices:
    #~ emulator: /usr/bin/qemu-kvm
    watchdog model="i6300esb"
    console type="pty":
      target type="serial"
    :
    graphics type="vnc" port="-1":
      listen type="address" address="0.0.0.0"
    :
    # Storage configuration
    $(m_disc_block vdev=vda path=/dev/hdvg0/ts1-v1)
    $(m_disc_file vdev=vdc file=/medias/isolib/boot-params/rs1.vfat)
    $(m_cdrom_local vdev="vdb" iso="/media/isolib/boot-cd/alpine-virt-3.7.0-x86_64.iso")
    $(m_cdrom_http vdev="vdb" url="http://alvm1.localnet/Files/Temp/isolib-installers/os/elementary/elementaryos-0.3.2-stable-amd64.20151209.iso")
    # Network configuration
    $(m_net_brnic br=br4)
EOF
