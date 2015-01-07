#!/bin/sh
#
# NSLU2-Linux Optware extended setup script for Android
# Copyright (c) 2012 andreas@potyomkin.org
# Based on 'optware-install-via-ab.sh'
#  Copyright (c) 2012 Paul Sokolovsky <pfalcon@users.sourceforge.net>
#  http://sf.net/p/optware-android/
# License: GPLv3, http://www.gnu.org/licenses/gpl.html
#
# Optware ARM binary packages repositories (aka feeds):
# http://ipkg.nslu2-linux.org/feeds/optware/cs08q1armel/
#
# Optware source code Subversion repository:
# svn co http://svn.nslu2-linux.org/svnroot/optware/trunk/
#

#set -x

# To install optware, we need root anyway. However, the fact that we can
# obtain root access on device doesn't mean we have root access with
# "adb push", i.e. can push to any location from host. So, we need
# a location writable by adb as a temporary transfer area. That's
# ADB_WRITABLE_DIR. /data/local is usually a good choice for most devices,
# but that can be anything, for example, /sdcard (there's no requirement
# for the filesystem with that dir supported Unix permissions, this script
# will get it right).
#
# OPTWARE_DIR is where optware is installed, it should be on a partition with
# normal Unix filesystem (permissions, etc.)
OPTWARE_DIR=/data/opt
ADB_WRITABLE_DIR=/data/local

# DO NOT edit anything below this line unless you know what you are doing

tmp_dir=$ADB_WRITABLE_DIR/optware.tmp
libc_path=arm-2008q1/arm-none-linux-gnueabi/libc
libc_libs="lib/libcrypt-2.5.so libcrypt.so.1 \
      lib/libnsl-2.5.so libnsl.so.1 \
      lib/libnss_compat-2.5.so libnss_compat.so.2 \
      lib/libnss_files-2.5.so libnss_files.so.2 \
      "
etc_files="group \
      nsswitch.conf \
      passwd \
      profile \
      shells \
      "

#
# On-target (device) commands
#

t_cp () {
    # copy file on a device
    adb shell su -c "cat $1 >$2"
}

t_cd_ln () {
    local dir=$1
    shift
    adb shell su -c "cd $dir; ln $*"
}

t_chmod () {
    adb shell su -c "chmod $*"
}

t_mkdir_p () {
    # This doesn't complain if dir exists, but can't create intermediate dirs
    adb shell su -c "ls $1 >/dev/null 2>&1 || mkdir $1"
}

t_rm_f () {
    # Doesn't complain if file not there
    adb shell su -c "ls $1 >/dev/null 2>&1 && rm $1"
}

t_rm_rf () {
    # Doesn't complain if dir not there
    adb shell su -c "ls $1 >/dev/null 2>&1 && rm -r $1"
}

t_remount_rw () {
    adb shell su -c "mount -o rw,remount $1 $1"
}

t_remount_ro () {
    adb shell su -c "mount -o ro,remount $1 $1"
}

install_system_lib () {
    local f=$(basename $1)
    echo "Installing system lib: $f"
    adb push $libc_path/$1 $tmp_dir
    t_cp $tmp_dir/$f /lib/$f
    t_chmod 0755 /lib/$f
    t_cd_ln /lib/ -s $f $2
}

install_etc () {
	while [ -n "$1" ]; do
		echo "Installing /opt/etc/$1"
		adb push optware-extended/etc/$1 $tmp_dir
    	t_cp $tmp_dir/$1 /opt/etc/$1
    	t_chmod 644 /opt/etc/$1
		t_cd_ln . -s /opt/etc/$1 /etc/$1
		shift
	done
}

uninstall_etc () {
	while [ -n "$1" ]; do
		echo "Uninstalling /opt/etc/$1"
		t_rm_f /etc/$1
		t_rm_f /data/opt/etc/$1
		shift
	done
}

install_libc () {
    t_mkdir_p $OPTWARE_DIR/rootlib
    t_cd_ln . -s $OPTWARE_DIR/rootlib /lib

    while [ -n "$1" ]; do
        local lib=$1
        shift
        local symlink=$1
        shift
        install_system_lib $lib $symlink
    done
}

openssh_uninstall () {
    t_remount_rw /
    t_remount_rw /system
    uninstall_etc $etc_files
	t_rm_f /etc/init.d/20optware
    t_remount_ro /system
	t_rm_f /data/opt/optware-init.sh
	t_rm_f /data/opt/rc.optware
	t_remount_ro /
	adb shell PATH=/opt/bin:/bin /opt/bin/ipkg remove openssh
	adb shell PATH=/opt/bin:/bin /opt/bin/ipkg remove openssh-sftp-server
    echo "OpenSSH sucessfully uninstalled"
}

#
# Main code
#

if [ "$1" == "" ]; then
    echo "This script extends your Optware installation with all files necessary to run"
    echo "the OpenSSH server on your connected Android device."
    echo "It is assumed that you have successfully installed Optware using"
    echo "'optware-install-via-adb.sh'. Since this installation requires some of the"
    echo "previously downloaded libraries you have to to run it from the same directory as"
    echo "'optware-install-via-adb.sh'."
    echo "The following files will be pushed to your device, any existing files will be" 
    echo "overwritten:"
    echo "    optware-extended/etc/group"
    echo "    optware-extended/etc/nsswitch.conf"
    echo "    optware-extended/etc/optware-init.sh"
    echo "    optware-extended/etc/passwd"
    echo "    optware-extended/etc/profile"
    echo "    optware-extended/etc/rc.optware"
    echo "    optware-extended/etc/shells"
    echo ""
    echo "Copy your public key to 'optware-extended/authorized_keys'"
    echo ""
    echo "The automatic initialization of Optware and it's init-script assumes that your"
    echo "device has a working sysinit."
    echo ""
    echo "Usage: $0 install|uninstall"
    exit 1
fi

if [ "$1" == "uninstall" ]; then
    openssh_uninstall
    exit
fi

t_remount_rw /

# Start from scratch, links may already exist
echo "== Initializing optware environment =="
t_rm_rf $tmp_dir
t_mkdir_p $tmp_dir

t_cd_ln . -s $OPTWARE_DIR /opt
t_cd_ln . -s $OPTWARE_DIR/rootbin /bin
t_cd_ln . -s $OPTWARE_DIR/tmp /tmp

echo "== Installing necessary libraries =="
install_libc $libc_libs

echo "== Installing necessary files  =="

# On a normal Android system, /etc is symlink to /system/etc, but just in case...
t_mkdir_p /etc
# but for normal system, we need to remount /system
t_remount_rw /system

# install files into /opt/etc and symlink to /etc
install_etc $etc_files

# initialize optware on startup
adb push optware-extended/etc/optware-init.sh $tmp_dir
adb push optware-extended/etc/rc.optware $tmp_dir
t_cp $tmp_dir/optware-init.sh /opt/etc/optware-init.sh
t_cp $tmp_dir/rc.optware /opt/etc/rc.optware
t_chmod 0700 /opt/etc/optware-init.sh
t_chmod 0700 /opt/etc/rc.optware
if [ -d /etc/init.d ]; then
    t_cd_ln . -s /data/opt/etc/optware-init.sh /etc/init.d/20optware
fi

t_remount_ro /system

adb shell rm -r $tmp_dir

# copy key file
if [ -e optware-extended/authorized_keys ]; then
    echo "== Installing key file  =="
    adb shell su -c "mkdir /opt/home/root/.ssh"
    t_chmod 0700 /opt/home/root/.ssh
    adb push authorized_keys /opt/home/root/.ssh/
    t_chmod 0600 /opt/home/root/.ssh/authorized_keys
fi

# fix permissions on root's home
t_chmod 0755 /opt/home/root/

t_remount_ro /

echo "== Installing OpenSSH  =="
echo "Make sure that your device is woken up and connected to the Internet"
echo "Press Enter to continue"
read
adb shell PATH=/opt/bin:/bin /opt/bin/ipkg install openssh
adb shell PATH=/opt/bin:/bin /opt/bin/ipkg install openssh-sftp-server
echo "Extended Optware installation complete."
