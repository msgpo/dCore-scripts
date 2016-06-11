#!/bin/busybox ash
# (c) Robert Shingledecker 2012
# Contributions by Jason Williams
. /etc/init.d/tc-functions

useBusybox

sudo chown root:staff /tmp
sudo chmod 1777 /tmp
TCUSER=`cat /etc/sysconfig/tcuser`
TCEDIR=`readlink /etc/sysconfig/tcedir`
DEBINXDIR=""$TCEDIR"/import/debinx"
SCEBOOTLST=""$TCEDIR"/sceboot.lst"
checknotroot
BUILD=`getBuild`
HERE=`pwd`

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
	echo "${YELLOW}sce-import - Search, convert, install DEB and pre-built packages as local SCEs,"
        echo "             use simple name (nano not nano_*_i386.deb), may use option combos,"
        echo "             also see /etc/sysconfig/sceconfig, locale.nopurge and sce.purge.${NORMAL}"
	echo "${YELLOW}"sce-import"${NORMAL}             Prompt, enter starting characters of package sought."
	echo "${YELLOW}"sce-import PKG"${NORMAL}         Search packages that start with desired package name."
	echo "${YELLOW}"sce-import -b PKG"${NORMAL}      Add resulting SCE to sceboot.lst."
	echo "${YELLOW}"sce-import -c PKG"${NORMAL}      Search packages that contain desired package name."
	echo "${YELLOW}"sce-import -d PKG"${NORMAL}      Choose existing SCE(s) to provide dependencies for"
        echo "                       new SCE, may make new SCE significantly smaller."
        echo "${YELLOW}"sce-import -k PKG"${NORMAL}      Keep /usr/share/doc and /man in SCE, see man-db."
	echo "${YELLOW}"sce-import -l LISTFILE"${NORMAL} SCE mega-extension created from text file listing one"
        echo "                       PKG per line, eg. sce-import -l /tmp/my_apps contains"
        echo "                       emelfm & nano, which can now share common dependencies."
	echo "${YELLOW}"sce-import -n PKG"${NORMAL}      Non-interactive exact name import, no combos like -nd."
	echo "${YELLOW}"sce-import -o PKG"${NORMAL}      Add imported SCE to ondemand via /tce/ondemand script."
	echo "${YELLOW}"sce-import -p PKG"${NORMAL}      Preserve old DEBINX, no new fetch, better performance."
	echo "${YELLOW}"sce-import -r PKG"${NORMAL}      Use RAM, swap partition/file to unpack source DEBs."
	echo "${YELLOW}"sce-import -s PKG"${NORMAL}      Estimate package, HD and RAM space, warn as needed."
	echo "${YELLOW}"sce-import -u PKG"${NORMAL}      (DEFAULT) update mode, sync new DEBINX files."
	echo "${YELLOW}"sce-import -v PKG"${NORMAL}      View list of packages the imported SCE contains."
	echo "${YELLOW}"sce-import -z PKG"${NORMAL}      Ignore locale.nopurge, sce.purge, sceconfig files."
	echo "${YELLOW}"sce-import -R PKG"${NORMAL}      Include recommended Debian packages, warning large SCE."
	echo "${YELLOW}"sce-import -S PKG"${NORMAL}      Include suggested Debian packages, warning large SCE."
exit 1
fi

mksce() {
	if [ "$FLAGS" ]
	then
		sudo deb2sce "$FLAGS" "$1" 
		if [ "$?" != "0" ]; then
			exit 1
		fi      
	else
		sudo deb2sce "$1"  
		if [ "$?" != "0" ]; then
			exit 1
		fi           
	fi

}

exit_tcnet() {
	echo "Issue connecting to `cat /opt/tcemirror`, exiting.."
	exit 1
}

read IMPORTMIRROR < /opt/tcemirror
PREBUILTMIRROR="${IMPORTMIRROR%/}/dCore/"$BUILD"/import"
IMPORTMIRROR="${IMPORTMIRROR%/}/dCore/import"


unset FLAGS PACKAGELIST NOPGREP
while getopts drsbolknupcvzRSN OPTION
do
	case ${OPTION} in
		c) CHECKALL=TRUE ;;
		u) UPDATEDEBINXMODE=TRUE ;;
		p) PRESERVEDEBINXMODE=TRUE ;;
		n) NONINTERACTIVE=TRUE ;;
		k) KEEPDOC=TRUE ;;
		d) DEPS=TRUE ;;
		r) RAM=TRUE ;;
		s) SIZE=TRUE ;;
		b) FLAGS="$FLAGS"b ; ONBOOT=TRUE ;;
		o) FLAGS="$FLAGS"o ; ONDEMAND=TRUE ;;
		l) PACKAGELIST=TRUE ;;
		v) VIEWPKGS=TRUE ;;
		z) NOCONFIG=TRUE ;;
		R) RECOMMENDS=TRUE ;;
		S) SUGGESTS=TRUE ;;
		N) NOLOCK=TRUE ;;
		*) echo "Run  sce-import --help  for usage information."
                   exit 1 ;;
	esac
done

if grep -i "^ONBOOT=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	ONBOOT=TRUE
	FLAGS="$FLAGS"b
fi

if grep -i "^ONDEMAND=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	ONDEMAND=TRUE
	FLAGS="$FLAGS"o
fi

shift `expr $OPTIND - 1`

if [ ! "$NOLOCK" == "TRUE" ]; then
	if [ -f /tmp/.scelock ]; then
		LOCK=`cat /tmp/.scelock`
		if /bb/ps | /bb/grep "$LOCK " | /bb/grep -v grep > /dev/null 2>&1; then
			echo "Another SCE utility is presently in use, exiting.."
			exit 1
		fi
	fi
	
	echo "$$" > /tmp/.scelock
fi

[ "$FLAGS" ] && FLAGS="-$FLAGS"
TARGET="$1"

[ -d /tmp/work ] && sudo rm -f /tmp/work/* > /dev/null 2>&1
[ -f /tmp/.viewpkgs ] && sudo rm /tmp/.viewpkgs
[ -f /tmp/.importinteractive ] && sudo rm /tmp/.importinteractive
[ -f /tmp/.keepdoc ] && sudo rm /tmp/.keepdoc
[ -f /tmp/.importram ] && sudo rm /tmp/.importram
[ -f /tmp/.importsize ] && sudo rm /tmp/.importsize
[ -f /tmp/.pkgprebuilt ] && sudo rm /tmp/.pkgprebuilt
[ -f /tmp/.depfile ] && sudo rm /tmp/.depfile
[ -f /tmp/.pkgextrafiles ] && sudo rm /tmp/.pkgextrafiles
[ -f /tmp/select.ans ] && sudo rm /tmp/select.ans   
[ -f /tmp/.targetfile ] && sudo rm /tmp/.targetfile
[ -f /tmp/.extrarepodep ] && sudo rm /tmp/.extrarepodep
[ -f /tmp/.importdep ] && sudo rm /tmp/.importdep
[ -f /tmp/.newdep ] && sudo rm /tmp/.newdep
[ -f /tmp/.importfree ] && sudo rm /tmp/.importfree
[ -f /tmp/.scedeps ] && sudo rm /tmp/.scedeps
[ -f /tmp/.scedebs ] && sudo rm /tmp/.scedebs
[ -f /tmp/.scelist ] && sudo rm /tmp/.scelist
#[ -f /tmp/deb2sce.tar.gz ] && sudo rm /tmp/deb2sce.tar.gz
[ -f /tmp/.prebuiltmd5sumlist ] && sudo rm /tmp/.prebuiltmd5sumlist
[ -f /tmp/.pkgextrafilemd5sumlist ] && sudo rm /tmp/.pkgextrafilemd5sumlist
[ -f /tmp/.blocked ] && sudo rm /tmp/.blocked
[ -f /tmp/.pkglisterror ] && sudo rm /tmp/.pkglisterror
[ -f /tmp/.pkgdeperror ] && sudo rm /tmp/.pkgdeperror
[ -f /tmp/.nogetdeps ] && sudo rm /tmp/.nogetdeps
[ -f /tmp/sce.recommends ] && sudo rm /tmp/sce.recommends
[ -f /tmp/sce.suggests ] && sudo rm /tmp/sce.suggests
[ -f /tmp/.recommends ] && sudo rm /tmp/.recommends
[ -f /tmp/.suggests ] && sudo rm /tmp/.suggests
[ -f /tmp/.scenoconfig ] && sudo rm /tmp/.scenoconfig


# Strip .sce suffix of package and preceding directory 
# and preceding directory if specified on command line.
TARGET=`basename "$TARGET"`
TARGET=${TARGET%%.sce}

echo " "

# Determine if debinx is desired to be updated in this session.
if [ "$PRESERVEDEBINXMODE" = "TRUE" ] ; then
	echo "Using the -p option."
elif grep -i "^PRESERVEDEBINXMODE=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	PRESERVEDEBINXMODE=TRUE
	echo "Using the -p option."
else
	echo "Using the -u option."
fi

# Noconfig mode, overlooking sceconfig, sce.purge, and locale.nopurge
if [ "$NOCONFIG" == "TRUE" ]; then
	touch /tmp/.scenoconfig
	echo "Using the -z option."
fi

# Determine if non-interactive mode is being used.
if grep -i "^NONINTERACTIVE=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	touch /tmp/.importinteractive
	echo "Using the -n option."
elif [ "$NONINTERACTIVE" == "TRUE" ]; then
	touch /tmp/.importinteractive
	echo "Using the -n option."
fi

if grep -wq "^$TARGET$" "$DEBINXDIR"/PKGEXCLUDELIST > /dev/null 2>&1; then
	echo " "
	echo "$TARGET is a blocked package, exiting.."
	exit 0
fi

# Determine if the size option is being used.
if grep -i "^SIZE=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	touch /tmp/.importsize
	echo "Using the -s option."
elif [ "$SIZE" == "TRUE" ]; then
	touch /tmp/.importsize
	echo "Using the -s option."
fi

# Determine if the viewpackges option is being used.
if grep -i "^VIEWPKGS=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	touch /tmp/.viewpkgs
	echo "Using the -v option."
elif [ "$VIEWPKGS" == "TRUE" ]; then
	touch /tmp/.viewpkgs
	echo "Using the -v option."
fi

# Determine if the checkall option is being used.
if grep -i "^CHECKALL=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	export CHECKALL=TRUE
	echo "Using the -c option."
elif [ "$CHECKALL" == "TRUE" ]; then
	echo "Using the -c option."
fi

# Determine if RAM is going to be used for unpacking.
if grep -i "^RAM=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	touch /tmp/.importram
	echo "Using the -r option."
elif [ "$RAM" == "TRUE" ]; then
	touch /tmp/.importram
	echo "Using the -r option."
fi

# Determine if docs are to be kept (/usr/share/doc, /usr/share/man, etc).
if grep -i "^KEEPDOC=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	touch /tmp/.keepdoc
	echo "Using the -k option."
elif [ "$KEEPDOC" == "TRUE" ]; then
	touch /tmp/.keepdoc
	echo "Using the -k option."
fi

# Determine if including 'Recommended' packages are desired.
if grep -i "^RECOMMENDS=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	touch /tmp/.recommends
	echo "Using the -R option."
elif [ "$RECOMMENDS" == "TRUE" ]; then
	touch /tmp/.recommends
	echo "Using the -R option."
fi

# Determine if including 'Suggested' packages are desired.
if grep -i "^SUGGESTS=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	touch /tmp/.suggests
	echo "Using the -S option."
elif [ "$SUGGESTS" == "TRUE" ]; then
	touch /tmp/.suggests
	echo "Using the -S option."
fi

# Determine if the -d option or the existence of a dep file
# is present and use dep file if found.
if [ "$DEPS" == "TRUE" ]; then
	touch /tmp/.importdep
	echo "Using the -d option."
elif ls /etc/sysconfig/tcedir/sce/"$TARGET".sce.dep > /dev/null 2>&1; then
	touch /tmp/.importdep
	echo " "
	echo "Existing dependency file found."
fi


echo " "

if [ "$PRESERVEDEBINXMODE" != "TRUE" ]; then
	sudo debGetEnv "$2"
	if [ "$?" != "0" ]; then
		echo " "
		echo "Error updating DEBINX files, exiting.."
		exit 1
	fi
else
	cd "$DEBINXDIR"
	if [ ! -s /etc/sysconfig/tcedir/import/debinx/debinx ] || [ ! -f deb2sce.tar.gz ]; then
		echo "${YELLOW}Warning:${NORMAL} Please run sce-import without the -p option to update DEBINX data."
		exit 1
	
	else
		DEBINX=`cat /etc/sysconfig/tcedir/import/debinx/debinx`
		if [ ! -f "$DEBINX" ]; then
			echo "${YELLOW}Warning:${NORMAL} Please run sce-import without the -p option to update DEBINX data."
			exit 1
		fi
	fi
	if [ -s /etc/sysconfig/tcedir/import/debinx/debinx_security ]; then
		DEBINX_SECURITY=`cat /etc/sysconfig/tcedir/import/debinx/debinx_security`
		if [ ! -f "$DEBINX_SECURITY" ]; then
			echo "${YELLOW}Warning:${NORMAL} Please run sce-import without the -p option to update DEBINX data."
			exit 1
		fi
	fi
	tar xvf deb2sce.tar.gz PKGEXTRAREPODEP >/dev/null 2>&1
	[ -f PKGEXCLUDELIST ] || tar xvf deb2sce.tar.gz PKGEXCLUDELIST >/dev/null 2>&1
	tar xvf deb2sce.tar.gz PKGADDDEP >/dev/null 2>&1
	tar xvf deb2sce.tar.gz PKGEXTRAFILES >/dev/null 2>&1
	tar xvf deb2sce.tar.gz PKGPREBUILTDEP >/dev/null 2>&1
	tar xvf deb2sce.tar.gz PKGEXTRAFILEMD5SUMLIST >/dev/null 2>&1
	tar xvf deb2sce.tar.gz PKGDATAFILEMD5SUMLIST >/dev/null 2>&1
	tar xvf deb2sce.tar.gz PREBUILTMD5SUMLIST >/dev/null 2>&1
	tar xvf deb2sce.tar.gz KEEPDOC >/dev/null 2>&1
	cd "$HERE"
fi

read DEBINX < /etc/sysconfig/tcedir/import/debinx/debinx
DEBINX="/etc/sysconfig/tcedir/import/debinx/$DEBINX"

checklist() {
  if sudo grep -q "^$1:" "$DEBINXDIR"/PKGADDDEP; then
	:
  elif sudo grep "^$1:" "$DEBINXDIR"/PKGPREBUILTDEP > /dev/null 2>&1; then
	:
  elif sudo grep "^Package: $1$" "$TCEDIR"/import/debinx/debinx.* > /dev/null 2>&1; then
	:
  elif sudo grep -q "^Package: $1$" "$DEBINX" > /dev/null 2>&1; then
	:
  else
	echo "$1" >> /tmp/.pkglisterror
  fi
}



# Determine if .lst file is being used or list specified, copy to /tmp/.targetfile
if [ "$PACKAGELIST" == "TRUE" ] || [ -f "$TCEDIR"/sce/"$1".sce.lst ]; then
	if [ -f "$1" ] && [ "$PACKAGELIST" == "TRUE" ]; then
		TARGETFILE=`readlink -f "$1"`
		for I in `cat "$TARGETFILE"`; do
			checklist "$I"
		done
		if [ -s /tmp/.pkglisterror ]; then
			echo " "
			cat /tmp/.pkglisterror
			echo " "
			if [ ! -f /tmp/.importinteractive ]; then
				echo "${YELLOW}Warning:${NORMAL} The above files in "$TARGETFILE" do not exist in dCore repos."
				echo " "
				echo -n "Press Enter to proceed anyway, (q)uit to exit: "
				read ans
				if [ "$ans" == "y" ] || [ "$ans" == "Y" ] || [ "$ans" == "" ]; then
					:
				else
					exit 1
				fi
			else
				echo "The above files in "$TARGETFILE" do not exist in dCore repos."
			fi
		fi
		sudo cp $TARGETFILE /tmp/.targetfile
		TARGET=`basename $1 .sce.lst`
	elif [ -s "$TCEDIR"/sce/"$1".sce.lst ]; then
		echo " "
		echo "Existing list file found."
		TARGETFILE=""$TCEDIR"/sce/"$1".sce.lst"
		for I in `cat "$TARGETFILE"`; do
			checklist "$I"
		done
		if [ -s /tmp/.pkglisterror ]; then
			echo " "
			cat /tmp/.pkglisterror
			echo " "
			if [ ! -f /tmp/.importinteractive ]; then
				echo "${YELLOW}Warning:${NORMAL} The above files in "$TARGETFILE" do not exist in dCore repos."
				echo " "
				echo -n "Press Enter to proceed anyway, (q)uit exits: "
				read ans
				if [ "$ans" == "y" ] || [ "$ans" == "Y" ] || [ "$ans" == "" ]; then
					:
				else
					exit 1
				fi
			else
				echo "The above files in "$TARGETFILE" do not exist in dCore repos."
			fi
		fi
		sudo cp "$TCEDIR"/sce/"$1".sce.lst /tmp/.targetfile
	elif [ ! "$1" ]; then
		echo " "
		echo "Please specify a target file when using the -l option, exiting.."
		exit 0
	else
		echo " "
		echo "Neither '"$1"' or "$TCEDIR"/sce/"$1".sce.lst files exist,"
		echo "exiting.."
		exit 0
	fi
fi

# Check for MS Windows filesystem of TCEDIR, and only continue of RAM 
# is being used for unpacking.
MS_MNTS=`mount|awk '$5~/fat|vfat|msdos|ntfs/{printf "%s ",$1}'`
REALDIR=`readlink /etc/sysconfig/tcedir`
MNTDEV=`df "$REALDIR" | tail -n1 | cut -f1 -d" "`
case "$MS_MNTS" in 
			*"$MNTDEV"* )
				if [ ! -f /tmp/.importram ]; then 
					echo " "
					echo "${YELLOW}Warning:${NORMAL} "$REALDIR" resides on a Windows filesystem."
					echo "Please try again with the -r flag to unpack files in RAM, exiting.."
					exit 1
				fi	
			;;

esac

# When no package is specified on command line, ask for one.
if [ -z "$TARGET" ] && [ "$CHECKALL" == "TRUE" ]; then
	echo " "
	echo -n "Enter search characters contained in package sought: "
	read TARGET
elif [ -z "$TARGET" ]; then
	echo " "
	echo -n "Enter starting characters of package sought: "
	read TARGET
fi

if [ ! "$TARGET" ]; then
	echo "No search characters entered, exiting.."
	exit 1
fi

# Below is where the package is found either in prebuilt, main
# Packages file, or in extra repos.  And then proceeds to deb2sce.

# Below is where -l list file option is being used.
if [ "$PACKAGELIST" ] && [ ! -f "$TCEDIR"/sce/"$1".sce.lst ]; then
	if [ -f "$TARGETFILE" ]; then
  		echo " "
  		if [ -f /tmp/.importinteractive ]; then
  			echo -n "Creating "$TARGET".sce from "$TARGETFILE"."
  			mksce "$TARGET"
			exit 0
  		else
                        echo "Create "$TARGET".sce from "$TARGETFILE"?"
			echo " "
			echo "Press Enter to use this package list or enter (n)o to import a standard"
			echo "'"$TARGET"' package if it exists, Ctrl-C aborts."
                        echo " "
                        echo "${YELLOW}Warning:${NORMAL} Entering (n)o will delete "$TARGETFILE"."
                        read ans                  
	  		if [ "$ans" == "n" ] || [ "$ans" == "N" ]; then  
	  			sudo rm /tmp/.targetfile
				mksce "$TARGET" 
				sudo rm "$TARGETFILE"
				exit 0
			else
				mksce "$TARGET"
				exit 0
			fi
		fi
	else
		echo "Please specify a target file when using the -l option, exiting.."
		exit 1
	fi  
# Below is where an existing .lst file is found in sce dir.
elif [ -f "$TCEDIR"/sce/"$1".sce.lst ]; then
	echo " "
  	if [ -f /tmp/.importinteractive ]; then
  		echo -n "Creating "$TARGET".sce from "$TARGETFILE"."
  		mksce "$TARGET"
		exit 0
  	else
	  	echo "Create "$TARGET".sce from "$TARGETFILE"?"
		echo " "
		echo "Press Enter to use this package list or enter (n)o to import a standard"
		echo "'"$TARGET"' package if it exists, Ctrl-C aborts."
                echo " "
		echo "${YELLOW}Warning:${NORMAL} Entering (n)o will delete "$TARGETFILE"."
                echo -n "$ " & read ans
	  	if [ "$ans" == "n" ] || [ "$ans" == "N" ]; then  
	  		sudo rm /tmp/.targetfile
			mksce "$TARGET" 
			sudo rm "$TARGETFILE"
			exit 0
		else
			mksce "$TARGET"
			exit 0
		fi
	fi  
# Below checks for package in the extra repos first, then the 
# Debian main repos, then in the prebuilt section, in that order.
elif [ "$CHECKALL" == "TRUE" ]; then
	if sudo grep -i "^Package: .*$TARGET" "$TCEDIR"/import/debinx/debinx* > /dev/null 2>&1 ||  sudo grep -i "^Package: .*$TARGET" "$DEBINX" > /dev/null 2>&1 || sudo grep -i "$TARGET" "$DEBINXDIR"/PKGADDDEP | cut -f1 -d: | grep -i "$TARGET" > /dev/null 2>&1 || sudo grep -i "$TARGET" "$DEBINXDIR"/PKGPREBUILTDEP | cut -f1 -d: | grep -i "$TARGET" > /dev/null 2>&1; then
		if [ -f /tmp/.importinteractive ]; then
			if sudo grep -i "^Package: .*$TARGET$" "$TCEDIR"/import/debinx/debinx* > /dev/null 2>&1; then
				DEB=`sudo grep -i "^Package: $TARGET$" "$TCEDIR"/import/debinx/debinx* | head -1 | awk '{print $2}'`
			elif sudo grep -i "^Package: .*$TARGET$" "$DEBINX" > /dev/null 2>&1; then
				DEB=`sudo grep -i "^Package: $TARGET$" "$DEBINX" | awk '{print $2}'`
			elif sudo grep -i "^$TARGET:" "$DEBINXDIR"/PKGADDDEP > /dev/null 2>&1; then
				DEB=`sudo grep -i "^$TARGET:" "$DEBINXDIR"/PKGADDDEP | cut -f1 -d:`
			elif sudo grep -i "^$TARGET:" "$DEBINXDIR"/PKGPREBUILTDEP  > /dev/null 2>&1; then
				DEB=`sudo grep -i "^$TARGET:" "$DEBINXDIR"/PKGPREBUILTDEP | cut -f1 -d:`
			fi
			if [ -z "$DEB" ]; then
				echo "'"$TARGET"' is not available as a package, exiting.."
				exit 1
			fi     
		else
			{ ls "$TCEDIR"/import/debinx/debinx* > /dev/null 2>&1 && sudo grep -i "^Package: .*$TARGET" "$TCEDIR"/import/debinx/debinx* | head -1 | awk '{print $2}' ; sudo grep -i "^Package: .*$TARGET" "$DEBINX" | awk '{print $2}' ; sudo grep -i "$TARGET" "$DEBINXDIR"/PKGADDDEP | cut -f1 -d: | grep "$TARGET" ; sudo grep -i "$TARGET" "$DEBINXDIR"/PKGPREBUILTDEP | cut -f1 -d: | grep -i "$TARGET" ; } | sort | uniq  > /tmp/.sceimportselect 
			LINES=`/bb/wc -l /tmp/.sceimportselect | cut -f1 -d" "`
			if [ "$LINES" == "1" ]; then
				DEB=`cat /tmp/.sceimportselect`
				echo " "
				echo -n "Press Enter to import ${YELLOW}$DEB${NORMAL}, (q)uit to exit: "
				read ans
				if [ "$ans" == "y" ] || [ "$ans" == "Y" ] || [ "$ans" == "" ]; then
					:
				else
					exit 0
				fi
			else
				cat /tmp/.sceimportselect | select "Select package for '"$TARGET"'." "-"
				read DEB < /tmp/select.ans                                                                           
  				[ "$DEB" == "q" ] || [ "$DEB" == "" ] && exit 1  
			fi   
		fi 
		echo " "
  		echo "Importing ${YELLOW}$DEB${NORMAL}."
  		mksce "$DEB"
  		exit 0
	fi 
elif [ "$CHECKALL" != "TRUE" ]; then  
	if sudo grep -i "^Package: $TARGET" "$TCEDIR"/import/debinx/debinx* > /dev/null 2>&1 ||  sudo grep -i "^Package: $TARGET" "$DEBINX" > /dev/null 2>&1 || sudo grep -i "$TARGET" "$DEBINXDIR"/PKGADDDEP | cut -f1 -d: | grep -i "$TARGET" > /dev/null 2>&1 || sudo grep -i "$TARGET" "$DEBINXDIR"/PKGPREBUILTDEP | cut -f1 -d: | grep -i "$TARGET" > /dev/null 2>&1; then
		if [ -f /tmp/.importinteractive ]; then
			if sudo grep -i "^Package: $TARGET$" "$TCEDIR"/import/debinx/debinx* > /dev/null 2>&1; then
				DEB=`sudo grep -i "^Package: $TARGET$" "$TCEDIR"/import/debinx/debinx* | head -1 | awk '{print $2}'`
			elif sudo grep -i "^Package: $TARGET$" "$DEBINX" > /dev/null 2>&1; then
				DEB=`sudo grep -i "^Package: $TARGET$" "$DEBINX" | awk '{print $2}'`
			elif sudo grep -i "^$TARGET:" "$DEBINXDIR"/PKGADDDEP > /dev/null 2>&1; then
				DEB=`sudo grep -i "^$TARGET:" "$DEBINXDIR"/PKGADDDEP | cut -f1 -d:`
			elif sudo grep -i "^$TARGET:" "$DEBINXDIR"/PKGPREBUILTDEP  > /dev/null 2>&1; then
				DEB=`sudo grep -i "^$TARGET:" "$DEBINXDIR"/PKGPREBUILTDEP | cut -f1 -d:`
			fi
			if [ -z "$DEB" ]; then
				echo "'"$TARGET"' is not available as a package, exiting.."
				exit 1
			fi  
		 else
			{ ls "$TCEDIR"/import/debinx/debinx* > /dev/null 2>&1 && sudo grep -i "^Package: $TARGET" "$TCEDIR"/import/debinx/debinx* | head -1 | awk '{print $2}' ; sudo grep -i "^Package: $TARGET" "$DEBINX" | awk '{print $2}' ; sudo grep -i "^$TARGET" "$DEBINXDIR"/PKGADDDEP | cut -f1 -d: | grep "$TARGET" ; sudo grep -i "^$TARGET" "$DEBINXDIR"/PKGPREBUILTDEP | cut -f1 -d: | grep -i "$TARGET" ; } | sort | uniq  > /tmp/.sceimportselect 
			LINES=`/bb/wc -l /tmp/.sceimportselect | cut -f1 -d" "`
			if [ "$LINES" == "1" ]; then
				DEB=`cat /tmp/.sceimportselect`
				echo " "
				echo -n "Press Enter to import ${YELLOW}$DEB${NORMAL}, (q)uit exits: "
				read ans
				if [ "$ans" == "y" ] || [ "$ans" == "Y" ] || [ "$ans" == "" ]; then
					:
				else
					exit 0
				fi
			else
				cat /tmp/.sceimportselect | select "Select package for '"$TARGET"'." "-"
				read DEB < /tmp/select.ans                                                                           
  				[ "$DEB" == "q" ] || [ "$DEB" == "" ] && exit 1
			fi
        
		fi
		echo " "
  		echo "Importing ${YELLOW}"$DEB"${NORMAL}."
  		mksce "$DEB"
  		exit 0
	fi
  	
fi

echo " "
echo "'"$TARGET"' is not available as a package, exiting.."
exit 1
