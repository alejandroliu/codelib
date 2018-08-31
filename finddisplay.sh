#!/bin/sh
#
# Script for use in -display WAIT:cmd=FINDDISPLAY -unixpw mode.
# Attempts to find 1) DISPLAY and 2) XAUTH data for the user and
# returns them to caller.
#
# The idea is this script is run via su - user -c ... and returns
# display + xauth info to caller (x11vnc running as root or nobody).
# x11vnc then uses the info to open the display.
#
# If not called with -unixpw, root, etc. uses current $USER.

#FIND_DISPLAY_OUTPUT=/tmp/fdo.$USER.txt

if [ "X$FIND_DISPLAY_OUTPUT" != "X" ]; then
	if [ "X$FIND_DISPLAY_EXEC" = "X" ]; then
		FIND_DISPLAY_EXEC=1
		export FIND_DISPLAY_EXEC
		# we rerun ourselves with verbose output to a file:
		#
		if [ "X$FIND_DISPLAY_OUTPUT" != "X" ]; then
			/bin/sh $0 "$@" 2> $FIND_DISPLAY_OUTPUT
		else
			/bin/sh $0 "$@" 2> /dev/null
		fi
		exit $?
	fi
fi

if [ "X$FIND_DISPLAY_OUTPUT" != "X" ]; then
	# turn on verbose output
	set -xv
fi
if [ "X$FIND_DISPLAY_DEBUG" != "X" ]; then
	# print environment and turn on verbose output
	env
	set -xv
fi

if [ "X$X11VNC_SKIP_DISPLAY" = "Xall" ]; then
	exit 1
fi

# Set PATH to pick up utilities we use below.
PATH=$PATH:/bin:/usr/bin:/usr/X11R6/bin:/usr/bin/X11:/usr/openwin/bin:/usr/ucb
export PATH

# This is to try to trick ps(1) into writing wide lines: 
COLUMNS=256
export COLUMNS

# -n means no xauth, -f prescribes file to use.
showxauth=1
if [ "X$1" = "X-n" ]; then
	showxauth=""
	shift
fi
if [ "X$FIND_DISPLAY_NO_SHOW_XAUTH" != "X" ]; then
	showxauth=""
fi

# -f means use this xauthority file:
if [ "X$1" = "X-f" ]; then
	shift
	if [ ! -r $1 ]; then
		echo ""
		exit 1
	fi
	export XAUTHORITY="$1"
	shift
fi

# we need to set user:
#
user="$1"			# cmd line arg takes precedence
if [ "X$user" = "X" ]; then
	user=$X11VNC_USER	# then X11VNC_USER
fi
if [ "X$user" = "X" ]; then
	user=$USER		# then USER
fi
if [ "X$user" = "X" ]; then
	user=$LOGNAME		# then LOGNAME
fi
if [ "X$user" = "X" ]; then
	user=`whoami 2>/dev/null`	# desperation whoami
fi
if [ "X$user" = "X" ]; then
	echo ""		# failure
	exit 1
fi

LC_ALL=C
export LC_ALL

# util to try to match a display with a Linux VT and print
# disp,VT=... etc.  Otherwise just print out display.
#
prdpy () {
	d1=$1
	chvt0=""
	if [ "X$FIND_DISPLAY_NO_VT_FIND" != "X" ]; then
		:
	# we can only do chvt on Linux:
	elif [ "X$uname" = "XLinux" ]; then
		d2=$d1
		d3=`echo "$d2" | sed -e 's/^.*:/:/' -e 's/\..*$//'`
		d4="($d2|$d3)"

		# vt is usually in X server line:
		#
		ps_tmp=`ps wwaux | grep X`
		vt=`echo "$ps_tmp" | grep X | egrep -v 'startx|xinit' | egrep " $d4 " | egrep ' vt([789]|[1-9][0-9][0-9]*) ' | grep -v grep | head -n 1`

		if [ "X$vt" != "X" ]; then
			# strip it out and add it.
			vt=`echo "$vt" | sed -e 's/^.* vt\([0-9][0-9]*\) .*$/\1/'`
			if echo "$vt" | grep '^[0-9][0-9]*$' > /dev/null; then
				chvt0=",VT=$vt"
			fi
		else
			# otherwise look for tty:
			vt=`echo "$ps_tmp" | grep X | egrep " $d4 " | egrep ' tty([789]|[1-9][0-9][0-9]*) ' | grep -v grep | head -n 1`
			if [ "X$vt" != "X" ]; then
				vt=`echo "$vt" | sed -e 's/^.* tty\([0-9][0-9]*\) .*$/\1/'`
				if echo "$vt" | grep '^[0-9][0-9]*$' > /dev/null; then
					chvt0=",VT=$vt"
				fi
			else
				# otherwise try lsof:
				pvt=`echo "$ps_tmp" | grep X | egrep -v 'startx|xinit' | egrep " $d4 " | head -n 1 | awk '{print $2}'`
				if [ "X$FIND_DISPLAY_NO_LSOF" != "X" ]; then
					if [ "X$pvt" != "X" ]; then
						chvt0=",XPID=$pvt"
					fi
				elif [ "X$pvt" != "X" ]; then
					vt=`lsof -b -p "$pvt" 2>/dev/null | egrep '/dev/tty([789]|[1-9][0-9][0-9]*)$' | grep -v grep | head -n 1 | awk '{print $NF}' | sed -e 's,/dev/tty,,'`
					if echo "$vt" | grep '^[0-9][0-9]*$' > /dev/null; then
						chvt0=",VT=$vt"
					else
						# if this fails, at least tell them the XPID:
						chvt0=",XPID=$pvt"
					fi
				fi
			fi
		fi
	fi

	# return the string, possibly with ,VT=... appended:
	#
	echo "$d1$chvt0"
}

# save uname, netstat, and ps output:
uname=`uname`
is_bsd=""
if echo "$uname" | grep -i bsd > /dev/null; then
	is_bsd=1
fi

if [ "X$uname" = "XDarwin" ]; then
	psout=`ps aux 2>/dev/null              | grep -wv PID | grep -v grep`
elif [ "X$uname" = "XLinux" -o "X$is_bsd" = "X1" ]; then
	psout=`ps wwaux 2>/dev/null           | grep -wv PID | grep -v grep`
elif [ "X$uname" = "XSunOS" -a -x /usr/ucb/ps ]; then
	psout=`/usr/ucb/ps wwaux 2>/dev/null  | grep -wv PID | grep -v grep`
else
	psout=`ps -ef 2>/dev/null | grep -wv PID | grep -v grep`
fi
pslist=`echo "$psout" | awk '{print $2}'`

nsout=`netstat -an`

rchk() {
	rr=rr	
}

dL="-L"
if uname -sr | egrep 'SunOS 5\.[5-8]' > /dev/null; then
	dL="-h"
fi

# a portable tmp file creator
mytmp() {
	tf=$1
	if type mktemp > /dev/null 2>&1; then
		# if we have mktemp(1), use it:
		tf2="$tf.XXXXXX"
		tf2=`mktemp "$tf2"`
		if [ "X$tf2" != "X" -a -f "$tf2" ]; then
			if [ "X$DEBUG_MKTEMP" != "X" ]; then
				echo "mytmp-mktemp: $tf2" 1>&2
			fi
			echo "$tf2"
			return
		fi
	fi
	# fallback to multiple cmds:
	rm -rf "$tf" || exit 1
	if [ -d "$tf" ]; then
		echo "tmp file $tf still exists as a directory."
		exit 1
	elif [ $dL "$tf" ]; then
		echo "tmp file $tf still exists as a symlink."
		exit 1
	elif [ -f "$tf" ]; then
		echo "tmp file $tf still exists."
		exit 1
	fi
	touch "$tf" || exit 1
	chmod 600 "$tf" || exit 1
	rchk
	if [ "X$DEBUG_MKTEMP" != "X" ]; then
		echo "mytmp-touch: $tf" 1>&2
	fi
	echo "$tf"
}

skip_display() {
	dtry=$1
	dtry1=`echo "$dtry" | sed -e 's/^://'`
	dtry2=`echo "$dtry" | sed -e 's/\.[0-9][0-9]*$//'`

	if [ "X$X11VNC_SKIP_DISPLAY" = "X" ]; then
		# no skip list, return display:
		echo "$dtry"
	else
		# user supplied skip list:
		mat=""
		slist=""
		for skip in `echo "$X11VNC_SKIP_DISPLAY" | tr ',' '\n'`
		do
			if echo "$skip" | sed -e 's/://g' | grep '^[0-9][0-9]*-[0-9][0-9]*$' > /dev/null; then
				# a range n-m
				min=`echo "$skip" | sed -e 's/://g' | awk -F- '{print $1}'`
				max=`echo "$skip" | sed -e 's/://g' | awk -F- '{print $2}'`
				if [ "$min" -le "$max" ]; then
					while [ $min -le $max ]
					do
						if [ "X$slist" = "X" ]; then
							slist="$min"
						else
							slist="$slist $min"
						fi
						min=`expr $min + 1`
					done
					continue
				fi
			fi
			# a simple :n or n (or user supplied garbage).
			if [ "X$slist" = "X" ]; then
				slist="$skip"
			else
				slist="$slist $skip"
			fi
		done

		for skip in $slist
		do
			if echo "$skip" | grep "^:" > /dev/null; then
				:
			else
				skip=":$skip"
			fi
			skip2=`echo "$skip" | sed -e 's/\.[0-9][0-9]*$//'`

			if echo "$skip" | grep ":$dtry1\>" > /dev/null; then
				mat=1
				break
			elif echo "$skip" | grep ":$dtry2\>" > /dev/null; then
				mat=1
				break
			elif [ "X$skip2" = "X:$dtry1" ]; then
				mat=1
				break
			elif [ "X$skip2" = "X:$dtry2" ]; then
				mat=1
				break
			fi
		done
		if [ "X$X11VNC_SKIP_DISPLAY_NEGATE" = "X" ]; then
			if [ "X$mat" = "X1" ]; then
				echo ""
			else
				echo "$dtry"
			fi
		else
			if [ "X$mat" = "X1" ]; then
				echo "$dtry"
			else
				echo ""
			fi
		fi
	fi
}

am_root=""
if id | sed -e 's/ gid.*$//' | grep -w root > /dev/null; then
	am_root=1
fi
am_gdm=""
if id | sed -e 's/ gid.*$//' | grep -w gdm > /dev/null; then
	am_gdm=1
fi

# this mode is to try to grab a display manager (gdm, kdm, xdm...) display
# when we are run as root (e.g. no one is logged in yet).  We look at the
# -auth line in the X/Xorg commandline.
#
if [ "X$FD_XDM" != "X" ]; then
	list=""
	for pair in `echo "$psout" | grep '/X.* :[0-9][0-9]* .*-auth' | egrep -v 'startx|xinit' | sed -e 's,^.*/X.* \(:[0-9][0-9]*\) .* -auth \([^ ][^ ]*\).*$,\1\,\2,' | sort -u`
	do
		da=`echo "$pair" | awk -F, '{print $1}'`
		xa=`echo "$pair" | awk -F, '{print $2}'`
		da=`skip_display "$da"`
		if [ "X$da" = "X" ]; then
			continue
		fi
		if [ -f $xa -a -r $xa ]; then
			# if we have an xauth file, we proceed to test it:
			#
			env XAUTHORITY="$xa" xdpyinfo -display "$da" >/dev/null 2>&1
			if [ $? = 0 ]; then
				si_root=""
				si_gdm=""
				# recent gdm seems to use SI:localuser: for xauth.
				if env DISPLAY="$da" xhost 2>/dev/null | grep -i '^SI:localuser:root$' > /dev/null; then
					si_root=1
				fi
				if env DISPLAY="$da" xhost 2>/dev/null | grep -i '^SI:localuser:gdm$'  > /dev/null; then
					si_gdm=1
				fi
				env XAUTHORITY=/dev/null xdpyinfo -display "$da" >/dev/null 2>&1
				rc=$?
				if [ "X$rc" = "X0" ]; then
					# assume it is ok for server interpreted case.
					if [ "X$am_root" = "X1" -a "X$si_root" = "X1" ]; then
						rc=5
					elif [ "X$am_gdm" = "X1" -a "X$si_gdm" = "X1" ]; then
						rc=6
					fi
				fi
				if [ $rc != 0 ]; then
					y=`prdpy $da`
					if [ "X$FIND_DISPLAY_NO_SHOW_DISPLAY" = "X" ]; then
						echo "DISPLAY=$y"
					fi
					if [ "X$FIND_DISPLAY_XAUTHORITY_PATH" != "X" ]; then
						# caller wants XAUTHORITY printed out too.
						if [ "X$xa" != "X" -a -f "$xa" ]; then
							echo "XAUTHORITY=$xa"
						else
							echo "XAUTHORITY=$XAUTHORITY"
						fi
					fi
					if [ "X$showxauth" != "X" ]; then
						# copy the cookie:
						cook=`xauth -f "$xa" list | head -n 1 | awk '{print $NF}'`
						xtf=$HOME/.xat.$$
						xtf=`mytmp "$xtf"`
						if [ ! -f $xtf ]; then
							xtf=/tmp/.xat.$$
							xtf=`mytmp "$xtf"`
						fi
						if [ ! -f $xtf ]; then
							xtf=/tmp/.xatb.$$
							rm -f $xtf
							if [ -f $xtf ]; then
								exit 1
							fi
							touch $xtf 2>/dev/null
							chmod 600 $xtf 2>/dev/null
							if [ ! -f $xtf ]; then
								exit 1
							fi
						fi
						xauth -f $xtf add "$da" . $cook
						xauth -f $xtf extract - "$da" 2>/dev/null
						rm -f $xtf
					fi
					# DONE
					exit 0
				fi
			fi
		fi
	done
	if [ "X$FIND_DISPLAY_XAUTHORITY_PATH" = "X" ]; then
		echo ""		# failure
	fi
	if [ "X$showxauth" != "X" ]; then
		echo ""
	fi
	# DONE
	exit 1
fi

# Normal case here (not xdm...).

# Try to match X DISPLAY to user:

# who(1) output column 2:
#gone=`last $user | grep 'gone.*no.logout' | awk '{print $2}' | grep '^:' | sed -e 's,/.*,,' | tr '\n' '|'`
#gone="${gone}__quite_impossible__"
#display=`who 2>/dev/null | grep "^${user}[ 	][ 	]*:[0-9]" | egrep -v " ($gone)\>" | head -n 1 \
#    | awk '{print $2}' | sed -e 's,/.*$,,'`

poss=""
list=`who 2>/dev/null | grep "^${user}[ 	][ 	]*:[0-9]" | awk '{print $2}' | sed -e 's,/.*$,,'`
list="$list "`w -h "$user" 2>/dev/null | grep "^${user}[ 	][ 	]*:[0-9]" | awk '{print $2}' | sed -e 's,/.*$,,'`
list="$list "`who 2>/dev/null | grep "^${user}[ 	]" | awk '{print $NF}' | grep '(:[0-9]' | sed -e 's/[()]//g'`
host=`hostname 2>/dev/null | sed -e 's/\..*$//'`

got_local_dm_file=""

if [ "X$X11VNC_FINDDISPLAY_SKIP_XAUTH" = "X" ]; then
	# do a normal xauth list:
	list="$list "`xauth list | awk '{print $1}' | grep /unix | grep "^${host}" | sed -e 's/^.*:/:/' | sort -n | uniq`

	# check for gdm and kdm non-NFS cookies in /tmp: (and now /var/run/gdm)
	for xa in /tmp/.gdm* /tmp/.Xauth* /var/run/gdm*/auth-for-*/database /var/run/gdm*/auth-cookie-*-for-*
	do
		# try to be somewhat careful about the real owner of the file:
		if [ "X$am_root" = "X1" ]; then
			break
		fi
		if [ -f $xa -a -r $xa ]; then
			if ls -l "$xa" | sed -e 's,/tmp.*$,,' -e 's,/var.*$,,' | grep -w "$user" > /dev/null; then
				# append these too:
				if find "$xa" -user "$user" -perm 600 > /dev/null; then
					:
				else
					continue
				fi
				# it passes the ownership tests, add it:
				# since the directory is (evidently) local, "localhost" is good too. (but beware XAUTHLOCALHOSTNAME in libxcb)
				sav0="$list "
				list="$list "`xauth -f "$xa" list | awk '{print $1}' | grep /unix | egrep -i "^${host}|^localhost" | sed -e 's/^.*:/:/' | sort -n | uniq | sed -e "s,\$,\,$xa,"`
				if [ "X$sav0" != "X$list" ]; then
					got_local_dm_file=1
				fi
			fi
		fi
	done
fi

if [ "X$uname" = "XDarwin" ]; then
	# macosx uses "console" string (in leopard X11 runs/launched by default)
	if who 2>/dev/null | grep -i "^${user}[ 	][ 	]*console[ 	]" > /dev/null; then
		echo "DISPLAY=console"
		if [ "X$FIND_DISPLAY_ALL" = "X" ]; then
			if [ "X$showxauth" != "X" ]; then
				echo ""
			fi
			exit 0
		fi
	fi
fi

# try the items in the list:
#
nsout_trim=`echo "$nsout" | grep "/tmp/.X11-unix/"`
#
for p in $list
do
	xa=`echo "$p" | awk -F, '{print $2}'`
	d=`echo "$p" | sed -e 's/,.*$//' -e 's/://' -e 's/\..*$//'`
	ok=""
	d=`skip_display "$d"`
	if [ "X$d" = "X" ]; then
		continue;
	fi

	# check for the local X11 files:
	xd="/tmp/.X11-unix/X$d"
	if [ -r "$xd" -o -w "$xd" -o -x "$xd" ]; then
		if echo "$nsout_trim" | grep "/tmp/.X11-unix/X$d[  ]*\$" > /dev/null; then
			ok=1
		fi
	fi
	if [ "X$ok" = "X" ]; then
		# instead check for the lock:
		if [ -f "/tmp/.X$d-lock" ]; then
			pid=`cat "/tmp/.X$d-lock" | sed -e 's/[ 	]//g'`
			if echo "$pid" | grep '^[0-9][0-9]*$' > /dev/null; then
				if [ "X$uname" = "XLinux" -o "X$uname" = "XSunOS" ]; then
					if [ -d "/proc/$pid" ]; then
						ok=1
					fi
				elif echo "$pslist" | grep -w "$pid" > /dev/null; then
					ok=1
				fi
			fi
		fi
	fi

	if [ "X$ok" = "X1" ]; then
		# ok, put it on the list
		poss="$poss $p"
	fi
done

seenvalues=""

seen() {
	# simple util to skip repeats
	v=$1
	if [ "X$seenvalues" != "X" ]; then
		for v2 in $seenvalues
		do
			if [ "X$v" = "X$v2" ]; then
				seenret=1
				return
			fi
		done
	fi
	if [ "X$seenvalues" = "X" ]; then
		seenvalues="$v"
	else
		seenvalues="$seenvalues $v"
	fi
	seenret=0
}

# now get read to try each one in $poss
#
poss=`echo "$poss" | sed -e 's/^ *//' -e 's/ *$//'`
display=""
xauth_use=""

if [ "X$X11VNC_FINDDISPLAY_SKIP_XAUTH" != "X" ]; then
	# we are not supposed to call xauth(1), simply report
	if [ "X$FIND_DISPLAY_ALL" != "X" ]; then
		for p in $poss
		do
			if [ "X$p" = "X" ]; then
				continue
			fi
			seen "$p"
			if [ "X$seenret" = "X1" ]; then
				continue
			fi
			# get rid of any ,xauth
			p=`echo "$p" | sed -e 's/,.*$//'`
			y=`prdpy $p`
			echo $y
		done
		exit 0
	fi
	display=`echo "$poss" | tr ' ' '\n' | head -n 1`
else
	freebie=""
	xauth_freebie=""
	for p in $poss
	do
		if [ "X$p" = "X" ]; then
			continue
		fi
		seen "$p"
		if [ "X$seenret" = "X1" ]; then
			continue
		fi

		# extract ,xauth if any.
		xa=""
		xa=`echo "$p" | awk -F, '{print $2}'`
		p=`echo "$p" | sed -e 's/,.*$//'`

		# check xauth for it:
		if [ "X$xa" != "X" ]; then
			myenv="XAUTHORITY=$xa"
		else
			myenv="FOO_BAR_=baz"
		fi
		p=`skip_display "$p"`
		if [ "X$p" = "X" ]; then
			continue
		fi

		env "$myenv" xdpyinfo -display "$p" >/dev/null 2>&1
		rc=$?

		if [ $rc != 0 ]; then
			# guard against libxcb/desktop silliness: 
			xalhn_save=$XAUTHLOCALHOSTNAME

			if [ "X$xalhn_save" != "X" ]; then
				# try it again unset
				unset XAUTHLOCALHOSTNAME
				env "$myenv" xdpyinfo -display "$p" >/dev/null 2>&1
				rc=$?
				if [ $rc != 0 ]; then
					# did not work; put it back
					XAUTHLOCALHOSTNAME=$xalhn_save
					export XAUTHLOCALHOSTNAME
				fi
			fi
			if [ $rc != 0 -a "X$xalhn_save" != "Xlocalhost" ]; then
				# try it again with localhost
				env "$myenv" XAUTHLOCALHOSTNAME=localhost xdpyinfo -display "$p" >/dev/null 2>&1
				rc=$?
				if [ $rc = 0 ]; then
					# better export it for cmds below...
					XAUTHLOCALHOSTNAME=localhost
					export XAUTHLOCALHOSTNAME
				fi
			fi
		fi

		if [ $rc = 0 ]; then
			if [ "X$FD_TAG" != "X" ]; then
				# look for x11vnc special FD_TAG property:
				if [ "X$xa" = "X" ]; then
					if xprop -display "$p" -root -len 128 FD_TAG | grep -iv no.such.atom \
					    | grep "=[ 	][ 	]*\"$FD_TAG\"" > /dev/null; then
						:
					else
						continue
					fi
				else
					if env XAUTHORITY="$xa" xprop -display "$p" -root -len 128 FD_TAG | grep -iv no.such.atom \
					    | grep "=[ 	][ 	]*\"$FD_TAG\"" > /dev/null; then
						:
					else
						continue
					fi
				fi
			fi

			# Now try again with no authority:
			env XAUTHORITY=/dev/null xdpyinfo -display "$p" >/dev/null 2>&1

			# 0 means got in for free... skip it unless we don't find anything else.
			if [ $? != 0 ]; then
				# keep it
				display="$p"
				xauth_use="$xa"
				if [ "X$FIND_DISPLAY_ALL" != "X" ]; then
					y=`prdpy $p`
					echo "DISPLAY=$y"
					continue
				fi
				break
			else
				# store in freebie as fallback
				if [ "X$FIND_DISPLAY_ALL" != "X" ]; then
					y=`prdpy $p`
					echo "$y,NOXAUTH"
					continue
				fi
				if [ "X$freebie" = "X" ]; then
					freebie="$p"
					xauth_freebie="$xa"
				fi
			fi
		fi
	done
	if [ "X$display" = "X" -a "X$freebie" != "X" ]; then
		# fallback to the freebie (if any)
		display="$freebie"
		xauth_use="$xauth_freebie"
	fi
fi

if [ "X$FIND_DISPLAY_ALL" != "X" ]; then
	# we have listed everything, get out.
	exit
fi
if [ "X$display" = "X" ]; then
	if [ "X$FINDDISPLAY_run" = "X" ]; then
		echo ""		# failure
		if [ "X$showxauth" != "X" ]; then
			echo ""
		fi
	fi
	exit 1
fi

# append ,VT=n if applicable:
dpy2=`prdpy "$display"`

if [ "X$FIND_DISPLAY_NO_SHOW_DISPLAY" = "X" ]; then
	echo "DISPLAY=$dpy2"
fi
if [ "X$FIND_DISPLAY_XAUTHORITY_PATH" != "X" ]; then
	# caller wants XAUTHORITY printed out too.
	if [ "X$xauth_use" != "X" -a -f "$xauth_use" ]; then
		echo "XAUTHORITY=$xauth_use"
	else
		echo "XAUTHORITY=$XAUTHORITY"
	fi
fi
if [ "X$showxauth" != "X" ]; then
	# show the (binary) xauth data:
	if [ "X$xauth_use" != "X" -a -f "$xauth_use" ]; then
		xauth -f "$xauth_use" extract - "$display" 2>/dev/null
	else
		xauth extract - "$display" 2>/dev/null
	fi
fi

exit 0
