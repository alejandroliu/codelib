#!/bin/sh

#CREATE_DISPLAY_OUTPUT=/tmp/cdo.txt

if echo "$USER" | egrep 'runge' > /dev/null ; then
	CREATE_DISPLAY_OUTPUT=/tmp/cdo.$USER.txt
	if [ -f $CREATE_DISPLAY_OUTPUT -a ! -w $CREATE_DISPLAY_OUTPUT ]; then
		CREATE_DISPLAY_OUTPUT=$CREATE_DISPLAY_OUTPUT.$$
	fi
fi
if [ "X$CREATE_DISPLAY_OUTPUT" != "X" ]; then
	if [ "X$CREATE_DISPLAY_EXEC" = "X" ]; then
		CREATE_DISPLAY_EXEC=1
		export CREATE_DISPLAY_EXEC
		if [ "X$CREATE_DISPLAY_OUTPUT" != "X" ]; then
			/bin/sh $0 "$@" 2> $CREATE_DISPLAY_OUTPUT
		else
			/bin/sh $0 "$@" 2> /dev/null
		fi
		exit $?
	fi
fi
if [ "X$CREATE_DISPLAY_PERL_SETPGRP" = "X" ]; then
	CREATE_DISPLAY_PERL_SETPGRP=1
	export CREATE_DISPLAY_PERL_SETPGRP
	if type perl >/dev/null 2>&1; then
		perl -e "setpgrp(0,0); exec '/bin/sh $0 $*'";
		exit $?
	fi
fi


if [ "X$CREATE_DISPLAY_OUTPUT" != "X" ]; then
	set -xv
fi

COLUMNS=256
export COLUMNS

LC_ALL_save=$LC_ALL
LC_ALL=C
export LC_ALL

findfree() {
	try=20
	dpymax=79
	if [ "X$X11VNC_CREATE_STARTING_DISPLAY_NUMBER" != "X" ]; then
		try=$X11VNC_CREATE_STARTING_DISPLAY_NUMBER
	fi
	if [ "X$X11VNC_CREATE_MAX_DISPLAYS" != "X" ]; then
		dpymax=$X11VNC_CREATE_MAX_DISPLAYS
	fi
	sry=`expr $try + $dpymax`
	n=""
	nsout=""
	if [ "X$have_netstat" != "X" ]; then
		nsout=`$have_netstat -an`
	fi
	nsout_trim=`echo "$nsout" | grep "/tmp/.X11-unix/"`
	while [ $try -lt $sry ]
	do
		tlock="/tmp/.X${try}-lock"
		if [ -r $tlock ]; then
			if echo "$nsout_trim" | grep "/tmp/.X11-unix/X${try}[ 	]*\$" > /dev/null; then
				:
			else
				pid=`head -n 1 $tlock 2>/dev/null | sed -e 's/[ 	]//g' | grep '^[0-9][0-9]*$'`
				if [ "X$pid" != "X" ]; then
					exists=0
					if [ -d /proc/$pid ]; then
						exists=1
					elif kill -0 $pid 2>/dev/null; then
						exists=1
					fi
					if [ "X$exists" = "X0" ]; then
						rm -f $tlock
					fi
				fi
			fi
		fi
		if [ ! -f $tlock ]; then
			if echo "$nsout_trim" | grep "/tmp/.X11-unix/X${try}[ 	]*\$" > /dev/null; then
				:
			else
				n=$try
				break
			fi
		fi
		try=`expr $try + 1`
	done
	echo "$n"
}

random() {
	if [ "X$RANDOM" != "X" ]; then
		echo "$RANDOM"
	else
		r1=`bash -c 'echo $RANDOM' 2>/dev/null`
		if echo "$r1" | grep '^[0-9][0-9]*$' > /dev/null; then
			echo "$r1"
		else
			r2=`sh -c 'echo $$; date; ps -elf' 2>&1 | sum -r 2>/dev/null | awk '{print $1}'`
			if echo "$r2" | grep '^[0-9][0-9]*$' > /dev/null; then
				echo "$r2"
			else
				r3=`sh -c 'echo $$'`
				echo "$r3"
			fi
		fi
	fi
}

findsession() {
	if [ "X$FD_PROG" != "X" ]; then
		echo "$FD_PROG"
		return
	fi
	if [ "X$have_gnome_session" != "X" -a "X$FD_SESS" = "Xgnome" ]; then
		if [ "X$have_dbus_launch" != "X" ]; then
			echo "$have_dbus_launch --exit-with-session $have_gnome_session"
		else
			echo "$have_gnome_session"
		fi
		return
	elif [ "X$have_startkde" != "X"    -a "X$FD_SESS" = "Xkde" ]; then
		echo "$have_startkde"
		return
	elif [ "X$have_startlxde" != "X"    -a "X$FD_SESS" = "Xlxde" ]; then
		echo "$have_startlxde"
		return
	elif [ "X$have_twm" != "X"         -a "X$FD_SESS" = "Xtwm" ]; then
		echo "$have_twm"
		return
	elif [ "X$have_fvwm2" != "X"       -a "X$FD_SESS" = "Xfvwm" ]; then
		echo "$have_fvwm2"
		return
	elif [ "X$have_mwm" != "X"         -a "X$FD_SESS" = "Xmwm" ]; then
		echo "$have_mwm"
		return
	elif [ "X$have_dtwm" != "X"        -a "X$FD_SESS" = "Xdtwm" ]; then
		echo "$have_dtwm"
		return
	elif [ "X$have_windowmaker" != "X" -a "X$FD_SESS" = "Xwmaker" ]; then
		echo "$have_windowmaker"
		return
	elif [ "X$have_wmaker" != "X"      -a "X$FD_SESS" = "Xwmaker" ]; then
		echo "$have_wmaker"
		return
	elif [ "X$have_startxfce" != "X" -a "X$FD_SESS" = "Xxfce" ]; then
		echo "$have_startxfce"
		return
	elif [ "X$have_startxfce4" != "X" -a "X$FD_SESS" = "Xxfce" ]; then
		echo "$have_startxfce4"
		return
	elif [ "X$have_enlightenment" != "X" -a "X$FD_SESS" = "Xenlightenment" ]; then
		echo "$have_enlightenment"
		return
	elif [ "X$have_Xsession" != "X"    -a "X$FD_SESS" = "XXsession" ]; then
		echo "$have_Xsession"
		return
	elif [ "X$have_Xsession" != "X"    -a "X$FD_SESS" = "Xcde" ]; then
		echo "$have_Xsession"
		return
	elif [ "X$have_xterm" != "X"       -a "X$FD_SESS" = "Xfailsafe" ]; then
		echo "$have_xterm"
		return
	elif [ "X$have_xterm" != "X"       -a "X$FD_SESS" = "Xxterm" ]; then
		echo "$have_xterm"
		return
	fi
	if type csh > /dev/null 2>&1; then
		home=`csh -f -c "echo ~$USER"`
	elif type tcsh > /dev/null 2>&1; then
		home=`tcsh -f -c "echo ~$USER"`
	elif type bash > /dev/null 2>&1; then
		home=`bash -c "echo ~$USER"`
	else
		home=""
	fi
	if [ "X$home" = "X" -o ! -d "$home" ]; then
		if [ "X$have_root" != "X" -a "X$USER" != "Xroot" ]; then
			home=`su - $USER -c 'echo $HOME'`
		fi
	fi
	if [ "X$home" = "X" -o ! -d "$home" ]; then
		if [ -d "/home/$USER" ]; then
			home="/home/$USER"
		else 
			home=__noplace__
		fi
	fi
	if [ -f "$home/.dmrc" ]; then
		if [ "X$have_startkde" != "X" ]; then
			if egrep -i 'Session=kde' "$home/.dmrc" > /dev/null; then
				echo "$have_startkde"
				return
			fi
		fi
		if [ "X$have_startlxde" != "X" ]; then
			if egrep -i 'Session=lxde' "$home/.dmrc" > /dev/null; then
				echo "$have_startlxde"
				return
			fi
		fi
		if [ "X$have_gnome_session" != "X" ]; then
			if egrep -i 'Session=gnome' "$home/.dmrc" > /dev/null; then
				echo "$have_gnome_session"
				return
			fi
		fi
		for wm in blackbox fvwm icewm wmw openbox twm mwm windowmaker enlightenment metacity startxfce4 startxfce
		do
			eval "have=\$have_$wm"
			if [ "X$have" = "X" ]; then
				continue
			fi
			if grep -i "Session=$wm" "$home/.dmrc" > /dev/null; then
				echo "$have"
				return
			fi
			
		done
		if egrep -i 'Session=default' "$home/.dmrc" > /dev/null; then
			if [ "X$have_gnome_session" != "X" ]; then
				echo "$have_gnome_session"
				return
			elif [ "X$have_startkde" != "X" ]; then
				echo "$have_startkde"
				return
			elif [ "X$have_startxfce" != "X" ]; then
				echo "$have_startxfce"
				return
			fi
		fi
	fi
	if [ -f "$home/.xsession" ]; then
		echo "$home/.xsession"
		return
	elif [ -f "$home/.xinitrc" ]; then
		echo "$home/.xinitrc"
		return
	fi
	if [ "X$have_xterm" != "X" ]; then
		echo $have_xterm
		return
	else
		echo ".xinitrc"
	fi
}

check_redir_services() {
	redir_daemon=""
	need_env=""
	if echo "$sess" | grep '^env ' > /dev/null; then
		sess=`echo "$sess" | sed -e 's/^env //'`
		need_env=1
	fi
	if [ "X$FD_ESD" != "X" -a "X$have_esddsp" != "X" ]; then
		if echo "$FD_ESD" | grep '^DAEMON-' > /dev/null; then
			FD_ESD=`echo "$FD_ESD" | sed -e 's/DAEMON-//'`
			rport=`echo "$FD_ESD" | sed -e 's/^.*://'`
			dport=`expr $rport + 1`
			dport=`freeport $dport`
			FD_ESD=$dport
			redir_daemon="$redir_daemon,TS_ESD_REDIR:$dport:$rport"
		fi
		if echo "$FD_ESD" | grep ':' > /dev/null; then
			:
		else
			FD_ESD="localhost:$FD_ESD"
		fi
		sess="ESPEAKER=$FD_ESD $have_esddsp -s $FD_ESD $sess"
		need_env=1
	fi
	if [ "X$FD_CUPS" != "X" ]; then
		if echo "$FD_CUPS" | grep '^DAEMON-' > /dev/null; then
			FD_CUPS=`echo "$FD_CUPS" | sed -e 's/DAEMON-//'`
			rport=`echo "$FD_CUPS" | sed -e 's/^.*://'`
			dport=`expr $rport + 1`
			dport=`freeport $dport`
			FD_CUPS=$dport
			redir_daemon="$redir_daemon,TS_CUPS_REDIR:$dport:$rport"
		fi
		if echo "$FD_CUPS" | grep ':' > /dev/null; then
			:
		else
			FD_CUPS="localhost:$FD_CUPS"
		fi
		csr=`echo "$FD_CUPS" | awk -F: '{print $1}'`
		ipp=`echo "$FD_CUPS" | awk -F: '{print $2}'`
		old=`strings -a /usr/sbin/cupsd 2>/dev/null | grep 'CUPS.v1\.[01]'`
		if [ "X$old" != "X" ]; then
			FD_CUPS=`echo "$FD_CUPS" | sed -e 's/:.*$//'`
		fi
		sess="CUPS_SERVER=$FD_CUPS IPP_PORT=$ipp $sess"
		need_env=1
	fi

	if [ "X$FD_SMB" != "X" ]; then
		if echo "$FD_SMB" | grep '^DAEMON-' > /dev/null; then
			FD_SMB=`echo "$FD_SMB" | sed -e 's/DAEMON-//'`
			rport=`echo "$FD_SMB" | sed -e 's/^.*://'`
			dport=`expr $rport + 1`
			dport=`freeport $dport`
			FD_SMB=$dport
			redir_daemon="$redir_daemon,TS_SMB_REDIR:$dport:$rport"
		fi
		if echo "$FD_SMB" | grep ':' > /dev/null; then
			:
		else
			FD_SMB="localhost:$FD_SMB"
		fi
		smh=`echo "$FD_SMB" | awk -F: '{print $1}'`
		smp=`echo "$FD_SMB" | awk -F: '{print $2}'`
		if [ "X$smh" = "X" ]; then
			smh=localhost
		fi
		sess="SMB_SERVER=$FD_SMB SMB_HOST=$smh SMB_PORT=$smp $sess"
		need_env=1
	fi

	if [ "X$FD_NAS" != "X" ]; then
		if echo "$FD_NAS" | grep '^DAEMON-' > /dev/null; then
			FD_NAS=`echo "$FD_NAS" | sed -e 's/DAEMON-//'`
			rport=`echo "$FD_NAS" | sed -e 's/^.*://'`
			dport=`expr $rport + 1`
			dport=`freeport $dport`
			FD_NAS=$dport
			redir_daemon="$redir_daemon,TS_NAS_REDIR:$dport:$rport"
		fi
		if echo "$FD_NAS" | grep ':' > /dev/null; then
			:
		else
			FD_NAS="tcp/localhost:$FD_NAS"
		fi
		sess="AUDIOSERVER=$FD_NAS $sess"
		need_env=1
	fi
	if [ "X$need_env" != "X" ]; then
		sess="env $sess"
	fi
	redir_daemon=`echo "$redir_daemon" | sed -e 's/^,*//'`
	echo "redir_daemon=$redir_daemon" 1>&2
}

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

missing_mesg() {
	echo "" 1>&2
	echo "The program \"$1\" could not be found in PATH and standard locations." 1>&2
	echo "You probably need to install a package that provides the \"$1\" program." 1>&2
	echo "" 1>&2
}

put_back_LC_ALL() {
	if [ "X$X11VNC_CREATE_LC_ALL_C_OK" = "X" ]; then
		if [ "X$LC_ALL_save" = "X" ]; then
			unset LC_ALL
		else
			LC_ALL="$LC_ALL_save"
		fi
	fi
}

server() {
	authfile=`auth`
	sess=`findsession`
	DISPLAY=:$N
	export DISPLAY
	stmp=""
	noxauth=""
	if [ "X$have_root" != "X" -a "X$USER" != "Xroot" ]; then
		sess="env DISPLAY=:$N $sess"
		noxauth="1"
	fi

	redir_daemon=""
	check_redir_services

	rmf="/nosuch"
	if echo "$sess" | grep '[ 	]' > /dev/null; then
		stmp=/tmp/.cd$$`random`
		stmp=`mytmp "$stmp"`
		touch $stmp
		chmod 755 $stmp || exit 1
		echo "#!/bin/sh" > $stmp
		#echo "(id; env; env | grep XAUTHORITY | sed -e 's/XAUTHORITY=//' | xargs ls -l) > /tmp/ENV.OUT.$$" >> $stmp
		if [ "X$SAVE_PATH" != "X" ]; then
			echo "PATH=\"$SAVE_PATH\"" >> $stmp
			echo "export PATH" >> $stmp
		fi
		if [ "X$noxauth" = "X1" ]; then
			echo "unset XAUTHORITY"   >> $stmp
		fi
		echo "$sess"   >> $stmp
		echo "sleep 1"   >> $stmp
		echo "rm -f $stmp" >> $stmp
		sess=$stmp
		rmf="$stmp"
	fi

	if [ "X$have_root" != "X" -a "X$USER" != "Xroot" ]; then
		ctmp1=/tmp/.xat1_$$`random`
		ctmp1=`mytmp "$ctmp1"`
		ctmp2=/tmp/.xat2_$$`random`
		ctmp2=`mytmp "$ctmp2"`
		touch $ctmp1 $ctmp2
		$have_xauth -f $authfile nextract -           :$N > $ctmp1
		$have_xauth -f $authfile nextract - `hostname`:$N > $ctmp2
		chown $USER $ctmp1 $ctmp2
		(unset XAUTHORITY; su - $USER -c "$have_xauth nmerge - < $ctmp1" 1>&2)
		(unset XAUTHORITY; su - $USER -c "$have_xauth nmerge - < $ctmp2" 1>&2)
		rm -f $ctmp1 $ctmp2
		XAUTHORITY=$authfile
		export XAUTHORITY
		sess="/bin/su - $USER -c $sess"
	else
		$have_xauth -f $authfile nextract -           :$N | $have_xauth nmerge -
		$have_xauth -f $authfile nextract - `hostname`:$N | $have_xauth nmerge -
	fi

	result=0
	#ns=4
	ns=0
	ns2=1
	#if uname | grep SunOS > /dev/null; then
	#	ns=2
	#fi


	if [ "X$use_xdmcp_query" = "X1" ]; then
		# we cannot use -nolisten tcp
		if [ "X$FD_XDMCP_IF" != "X" ]; then
			lhost=$FD_XDMCP_IF
		elif [ "X$have_netstat" = "X" ]; then
			lhost=localhost
		elif $have_netstat -an | grep -w 177 | grep -w udp > /dev/null; then
			lhost=localhost
		elif $have_netstat -an | grep -w 177 | grep -w udp6 > /dev/null; then
			lhost=::1
		else
			lhost=localhost
		fi
		echo "$* -once -query $lhost $FD_OPTS" 1>&2
		put_back_LC_ALL
		if [ "X$have_root" != "X" ]; then
			if [ -r $authfile ]; then
				$have_nohup $* -once -query $lhost -auth $authfile $FD_OPTS 1>&2 &
			else
				# why did we have this?
				$have_nohup $* -once -query $lhost $FD_OPTS 1>&2 &
			fi
		else
			if [ "X$ns" = "X0" ]; then
				$have_nohup sh -c "$* -once -query $lhost -auth $authfile $FD_OPTS" 1>&2 &
			else
				$have_nohup sh -c "(sleep $ns; $* -once -query $lhost -auth $authfile $FD_OPTS)" 1>&2 &
				#result=1
			fi
		fi
		pid=$!
		sleep 10
	elif [ "X$have_startx" != "X" -o "X$have_xinit" != "X" ]; then
		if [ "X$have_xinit" != "X" ]; then
			sxcmd=$have_xinit
		else
			sxcmd=$have_startx
		fi
		echo "$sxcmd $sess -- $* $nolisten -auth $authfile $FD_OPTS" 1>&2
		put_back_LC_ALL
		if [ "X$have_root" != "X" ]; then
			$sxcmd $sess -- $* $nolisten -auth $authfile $FD_OPTS 1>&2 &
		else
			if [ "X$ns" = "X0" ]; then
				$have_nohup sh -c "$sxcmd $sess -- $* $nolisten -auth $authfile $FD_OPTS" 1>&2 &
			else
				# Why did we ever sleep before starting the server??
				$have_nohup sh -c "(sleep $ns; $sxcmd $sess -- $* $nolisten -auth $authfile $FD_OPTS)" 1>&2 &
				#result=1
			fi
		fi
		pid=$!
	else
		# need to emulate startx/xinit ourselves...
		echo "$* $nolisten -auth $authfile $FD_OPTS" 1>&2
		put_back_LC_ALL
		if [ "X$have_root" != "X" ]; then
			$have_nohup $* $nolisten -auth $authfile $FD_OPTS 1>&2 &
			pid=$!
			sleep 3
			$have_nohup $sess 1>&2 &
		else
			if [ "X$ns" = "X0" ]; then
				$have_nohup sh -c "$* $nolisten -auth $authfile $FD_OPTS" 1>&2 &
			else
				$have_nohup sh -c "(sleep $ns; $* $nolisten -auth $authfile $FD_OPTS)" 1>&2 &
				#result=1
			fi
			pid=$!
			sleep 3
			$have_nohup sh -c "(sleep 3; $sess)" 1>&2 &
		fi
	fi

	LC_ALL=C
	export LC_ALL

	if uname | grep SunOS > /dev/null; then
		$have_nohup sh -c "(sleep 150; rm -f $rmf)" 1>&2 &
	else
		$have_nohup sh -c "(sleep 150; rm -f $rmf $authfile)" 1>&2 &
	fi

	t=0
	tmax=5
	while [ $t -lt $tmax ]
	do
		t=`expr $t + 1`
		sleep $ns2
		pid2=`head -n 1 "/tmp/.X$N-lock" 2>/dev/null | sed -e 's/[ 	]//g' | grep '^[0-9][0-9]*$'`
		if [ "X$pid2" = "X" ]; then
			pid2=9999999
		fi
		if [ "X$result" = "X1" ]; then
			break
		elif [ -d /proc/$pid2 ]; then
			result=1
			break
		elif kill -0 $pid2 2>/dev/null; then
			result=1
			break
		elif [ -d /proc/$pid ]; then
			result=1
			break
		elif kill -0 $pid 2>/dev/null; then
			result=1
			break
		else
			result=0
		fi
		if [ "X$have_netstat" != "X" ]; then
			if $have_netstat -an | grep "/tmp/.X11-unix/X$N\$" > /dev/null; then
				result=1
			fi
		fi
	done

	if [ "X$redir_daemon" != "X" -a "X$result" = "X1" ]; then
		redir_daemon=`echo "$redir_daemon" | sed -e 's/[~!$&*()|;?<>"]//g' -e "s/'//g"`
		xprog=$X11VNC_PROG
		if [ "X$xprog" = "X" ]; then
			xprog=x11vnc
		fi
		echo "running: $xprog -sleepin 10 -auth $authfile -tsd '$redir_daemon'" 1>&2
		$have_nohup sh -c "$xprog -sleepin 10 -auth $authfile -tsd '$redir_daemon' &" 2>.tsd.log.$USER 1>&2 &
	fi
}

try_X() {
	if [ "X$use_xdmcp_query" = "X1" ]; then
		if [ "X$have_X" != "X" ]; then
			server $have_X :$N
		elif [ "X$have_Xorg" != "X" ]; then
			server $have_Xorg :$N
		elif [ "X$have_XFree86" != "X" ]; then
			server $have_XFree86 :$N
		elif [ "X$have_Xsun" != "X" ]; then
			server $have_Xsun :$N
		fi
	elif [ "X$have_xinit" != "X" ]; then
		save_have_startx=$have_startx
		have_startx=""
		server :$N
		have_startx=$save_have_startx
	else
		server :$N
	fi
}

try_Xvnc() {
	if [ "X$have_Xvnc" = "X" ]; then
		missing_mesg Xvnc
		return
	fi

	server $have_Xvnc :$N -geometry $geom -depth $depth
}

try_Xsrv() {
	if [ "X$FD_XSRV" = "X" ]; then
		return
	fi

	server $FD_XSRV :$N -geometry $geom -depth $depth
}

add_modmap() {
	if [ "X$have_root" = "X" ]; then
	    $have_nohup sh -c "(
		sleep 10;
		$have_xmodmap -display :$N -e 'keycode any = Shift_R' \
			-e 'add Shift = Shift_L Shift_R' \
			-e 'keycode any = Control_R' \
			-e 'add Control = Control_L Control_R' \
			-e 'keycode any = Alt_L' \
			-e 'keycode any = Alt_R' \
			-e 'keycode any = Meta_L' \
			-e 'clear Mod1' \
			-e 'add Mod1 = Alt_L Alt_R Meta_L';
		if uname | grep SunOS > /dev/null; then
			for sym in SunAudioMute SunAudioLowerVolume SunAudioRaiseVolume
			do
				if $have_xmodmap -pk | grep -w \$sym > /dev/null; then
					:
				else
					$have_xmodmap -e \"keycode any = \$sym\"
				fi
			done
		fi

	    )" 1>&2 &
	else
	    (
		sleep 6;
		$have_xmodmap -display :$N -e 'keycode any = Shift_R' \
			-e 'add Shift = Shift_L Shift_R' \
			-e 'keycode any = Control_R' \
			-e 'add Control = Control_L Control_R' \
			-e 'keycode any = Alt_L' \
			-e 'keycode any = Alt_R' \
			-e 'keycode any = Meta_L' \
			-e 'clear Mod1' \
			-e 'add Mod1 = Alt_L Alt_R Meta_L';
		# this is to workaround a bug with JDS Solaris 10 gnome-session-daemon.
		if uname | grep SunOS > /dev/null; then
			for sym in SunAudioMute SunAudioLowerVolume SunAudioRaiseVolume
			do
				if $have_xmodmap -pk | grep -w $sym > /dev/null; then
					:
				else
					$have_xmodmap -e "keycode any = $sym"
				fi
			done
		fi
	    ) 1>&2 &
	fi
}

try_Xvfb() {
	if [ "X$have_Xvfb" = "X" ]; then
		missing_mesg Xvfb
		return
	fi

	sarg="-screen"
	if uname | grep SunOS > /dev/null; then
		if grep /usr/openwin/bin/Xsun $have_Xvfb > /dev/null; then
			sarg="screen"
		fi
	fi
	margs=""
	if $have_Xvfb -help 2>&1 | grep '^\+kb[ 	].*Keyboard Extension' >/dev/null; then
		margs="+kb"
	fi

	# currently not enabled in Xvfb's we see.
#	if $have_Xvfb -extension MOOMOO 2>&1 | grep -w RANDR >/dev/null; then
#		margs="$margs +extension RANDR"
#	fi

	if [ $depth -ge 16 ]; then
		# avoid DirectColor for default visual:
		margs="$margs -cc 4"
	fi
	server $have_Xvfb :$N $sarg 0 ${geom}x${depth} $margs

	if [ "X$result" = "X1" -a "X$have_xmodmap" != "X" ]; then
		add_modmap
	fi
}

try_Xdummy() {
	if [ "X$have_Xdummy" = "X" ]; then
		missing_mesg Xdummy
		return
	fi
	if [ "X$FD_XDUMMY_RUN_AS_ROOT" != "X" -a "X$have_root" = "X" ]; then
		return
	fi

	server $have_Xdummy :$N -geometry $geom -depth $depth
	
	if [ "X$result" = "X1" -a "X$have_xprop" != "X" ]; then
		(sleep 1; $have_xprop -display :$N -root -f X11VNC_TRAP_XRANDR 8s -set X11VNC_TRAP_XRANDR 1 >/dev/null 2>&1) &
		sleep 1
	fi
}


cookie() {
	cookie=""
	if [ "X$have_mcookie" != "X" ]; then
		cookie=`mcookie`
	elif [ "X$have_md5sum" != "X" ]; then
		if [ -c /dev/urandom ]; then
			cookie=`dd if=/dev/urandom count=32 2>/dev/null | md5sum | awk '{print $1}'`
		elif [ -c /dev/random ]; then
			cookie=`dd if=/dev/random count=32 2>/dev/null | md5sum | awk '{print $1}'`
		fi
		if [ "X$cookie" = "X" ]; then
			r=`random`
			cookie=`(echo $r; date; uptime; ps -ealf 2>&1) | md5sum | awk '{print $1}'`
		fi
	elif [ "X$have_xauth" != "X" ]; then
		if uname | grep SunOS > /dev/null; then
			cookie=`$have_xauth list | awk '{print $NF}' | tail -1`
		else
			cookie=`$have_xauth list | awk '{print $NF}' | tail -n 1`
		fi
	fi
	if [ "X$cookie" = "X" ]; then
		# oh well..
		for k in 1 2 3 4
		do
			r=`random`
			cookie=$cookie`printf "%08x" "${r}$$"`
		done
	fi
	echo "$cookie"
}

auth() {
	if [ "X$have_xauth" = "X" ]; then
		exit 1
	fi
	tmp=/tmp/.xas$$`random`
	tmp=`mytmp "$tmp"`
	touch $tmp
	chmod 600 $tmp || exit 1
	if [ ! -f $tmp ]; then
		exit 1
	fi
	cook=`cookie`
	$have_xauth -f $tmp add :$N . $cook  1>&2
	$have_xauth -f $tmp add `hostname`:$N . $cook  1>&2
	if [ "X$CREATE_DISPLAY_EXEC" != "X" ]; then
		ls -l $tmp 1>&2
		$have_xauth -f $tmp list 1>&2
	fi
	echo "$tmp"
}

freeport() {
	base=$1
	if [ "X$have_uname" != "X" -a "X$have_netstat" != "X" ]; then
		inuse=""
		if $have_uname | grep Linux > /dev/null; then
			inuse=`$have_netstat -ant | egrep 'LISTEN|WAIT|ESTABLISH|CLOSE' | awk '{print $4}' | sed 's/^.*://'`
		elif $have_uname | grep SunOS > /dev/null; then
			inuse=`$have_netstat -an -f inet -P tcp | grep LISTEN | awk '{print $1}' | sed 's/^.*\.//'`
		elif $have_uname | grep -i bsd > /dev/null; then
			inuse=`$have_netstat -ant -f inet | grep LISTEN | awk '{print $4}' | sed 's/^.*\.//'`
		# add others...
		fi
	fi
	i=0
	ok=""
	while [ $i -lt 500 ]
	do
		tryp=`expr $base + $i`
		if echo "$inuse" | grep -w "$tryp" > /dev/null; then
			:
		elif echo "$palloc" | tr ' ' '\n' | grep -w "$tryp" > /dev/null; then
			:
		else
			ok=$tryp
			break
		fi
		i=`expr $i + 1`
	done
	if [ "X$ok" != "X" ]; then
		base=$ok
	fi
	if [ "X$palloc" = "X" ]; then
		palloc="$base"
	else
		palloc="$palloc $base"
	fi
	echo "$base"
}


depth0=24
geom0=1280x1024
depth=${depth:-24}
geom=${geom:-1280x1024}

nolisten=${FD_NOLISTEN:-"-nolisten tcp"}

if [ "X$X11VNC_CREATE_GEOM" != "X" -a "X$FD_GEOM" = "X" ]; then
	FD_GEOM=$X11VNC_CREATE_GEOM
fi

if [ "X$FD_GEOM" != "X" -a "X$FD_GEOM" != "XNONE" ]; then
	x1=`echo "$FD_GEOM" | awk -Fx '{print $1}'`
	y1=`echo "$FD_GEOM" | awk -Fx '{print $2}'`
	d1=`echo "$FD_GEOM" | awk -Fx '{print $3}'`
	if [ "X$x1" != "X" -a "X$y1" != "X" ]; then
		geom="${x1}x${y1}"
	fi
	if [ "X$d1" != "X" ]; then
		depth="${d1}"
	fi
fi

depth=`echo "$depth" | head -n 1`
geom=`echo "$geom" | head -n 1`

if echo "$depth" | grep '^[0-9][0-9]*$' > /dev/null; then
	:
else
	depth=$depth0
fi
if echo "$geom" | grep '^[0-9][0-9]*x[0-9][0-9]*$' > /dev/null; then
	:
else
	geom=$geom0
fi

if [ "X$USER" = "X" ]; then
	USER=$LOGNAME
fi
if [ "X$USER" = "X" ]; then
	USER=`whoami`
fi

# Set PATH to have a better chance of finding things:
SAVE_PATH=$PATH
PATH=$PATH:/usr/X11R6/bin:/usr/bin/X11:/usr/openwin/bin:/usr/dt/bin:/opt/kde4/bin:/opt/kde3/bin:/opt/gnome/bin:/usr/bin:/bin:/usr/sfw/bin:/usr/local/bin

have_root=""
id0=`id`
if id | sed -e 's/ gid.*$//' | grep -w root > /dev/null; then
	have_root="1"
fi

p_ok=0
if [ "`type -p /bin/sh`" = "/bin/sh" ]; then
	p_ok=1
fi

for prog in startx xinit xdm gdm kdm xterm Xdummy Xvfb Xvnc xauth xdpyinfo mcookie md5sum xmodmap startkde startlxde dbus-launch gnome-session blackbox fvwm2 mwm openbox twm windowmaker wmaker enlightenment metacity X Xorg XFree86 Xsun Xsession dtwm netstat nohup esddsp konsole gnome-terminal x-terminal-emulator perl startxfce4 startxfce xprop
do
	p2=`echo "$prog" | sed -e 's/-/_/g'`
	eval "have_$p2=''"
	if type $prog > /dev/null 2>&1; then
		bpath=`which $prog | awk '{print $NF}'`
		if [ ! -x "$bpath" -o -d "$bpath" ]; then
			if [ "X$p_ok" = "X1" ]; then
				bpath=`type -p $prog | awk '{print $NF}'`
			fi
			if [ ! -x "$bpath" -o -d "$bpath" ]; then
				bpath=`type $prog | awk '{print $NF}'`
			fi
		fi
		eval "have_$p2=$bpath"
	fi
done
if [ "X$have_xterm" = "X" ]; then
	if [ "X$have_gnome_terminal" != "X" ]; then
		have_xterm=$have_gnome_terminal
	elif [ "X$have_konsole" != "X" ]; then
		have_xterm=$have_konsole
	elif [ "X$have_x_terminal_emulator" != "X" ]; then
		have_xterm=$have_x_terminal_emulator
	fi
fi

if [ "X$have_nohup" = "X" ]; then
	have_nohup="nohup"
fi

N=`findfree`

if [ "X$N" = "X" ]; then
	exit 1
fi
echo "trying N=$N ..." 1>&2

if [ "X$CREATE_DISPLAY_OUTPUT" != "X" ]; then
	set | grep "^have_" 1>&2
fi

TRY="$1"
if [ "X$TRY" = "X" ]; then
	TRY=Xvfb,Xdummy
fi

for curr_try in `echo "$TRY" | tr ',' ' '`
do
	result=0
	use_xdmcp_query=0
	if echo "$curr_try" | egrep '[+.-]xdmcp' > /dev/null; then
		use_xdmcp_query=1
	fi

	if [ "X$X11VNC_XDM_ONLY" = "X1" -a "X$use_xdmcp_query" = "X0" ]; then
		echo "SKIPPING NON-XDMCP item '$curr_try' in X11VNC_XDM_ONLY=1 mode." 1>&2
		continue
	fi
	
	curr_try=`echo "$curr_try" | sed -e  's/[+.-]xdmcp//'`
	curr_try=`echo "$curr_try" | sed -e  's/[+.-]redirect//'`

	if echo "$curr_try"   | grep -i '^Xdummy\>' > /dev/null; then
		try_Xdummy
	elif echo "$curr_try" | grep -i '^Xdummy$'  > /dev/null; then
		try_Xdummy
	elif echo "$curr_try" | grep -i '^Xvfb\>'   > /dev/null; then
		try_Xvfb
	elif echo "$curr_try" | grep -i '^Xvfb$'    > /dev/null; then
		try_Xvfb
	elif echo "$curr_try" | grep -i '^Xvnc\>'   > /dev/null; then
		try_Xvnc
	elif echo "$curr_try" | grep -i '^Xvnc$'    > /dev/null; then
		try_Xvnc
	elif echo "$curr_try" | grep -i '^Xsrv\>'   > /dev/null; then
		try_Xsrv
	elif echo "$curr_try" | grep -i '^Xsrv$'    > /dev/null; then
		try_Xsrv
	elif echo "$curr_try" | grep -i '^X\>'      > /dev/null; then
		try_X
	elif echo "$curr_try" | grep -i '^X$'       > /dev/null; then
		try_X
	fi
	if [ "X$result" = "X1" ]; then
		echo "DISPLAY=:$N"
		$have_xauth -f $authfile extract - :$N
		if [ "X$FD_EXTRA" != "X" ]; then
			$have_nohup env DISPLAY=:$N sh -c "(sleep 2; $FD_EXTRA) &" 1>&2 &
		fi
		exit 0
	fi
done

exit 1
