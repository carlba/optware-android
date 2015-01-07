#!/system/bin/sh
ls /opt >/dev/null 2>&1 && exit
export PATH="/system/xbin:/opt/sbin:/opt/bin:/opt/local/bin:/sbin:/system/sbin:/system/bin"
export LD_LIBRARY_PATH="/opt/lib:/system/lib"

echo Reinitializing optware rootfs links
mount -o rw,remount rootfs /
ln -s /data/opt /opt
ln -s /data/opt/rootlib /lib
ln -s /data/opt/rootbin /bin
ln -s /data/opt/tmp /tmp
mount -o ro,remount rootfs /
hash -r

# Call regular sysv init style startup scripts
. /opt/etc/rc.optware
