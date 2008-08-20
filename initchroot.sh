#!/bin/sh -e
#
# Copyright © 2008  Andres Salomon <dilinger@queued.net>
#
# This file is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

DIST=lenny
DEFUSER=olpc

. functions.sh

usage()
{
	echo "" 1>&2
	echo "Usage: $0 <root directory>" 1>&2
	echo "" 1>&2
	exit 1
}

if [ "$#" != "1" ]; then
	usage
fi

ROOT_DIR=$1

if [ -d "${ROOT_DIR}" ]; then
	echo "" 1>&2
	echo "*** ${ROOT_DIR} already exists!" 1>&2
	usage
fi

check_for_cmds debootstrap || exit 1

# create chroot
debootstrap --arch i386 lenny ${ROOT_DIR} http://http.us.debian.org/debian
mount -t proc proc ${ROOT_DIR}/proc
mount -t devpts devpts ${ROOT_DIR}/dev/pts
mkdir ${ROOT_DIR}/ofw

# allow daemons to be installed without breaking
mv ${ROOT_DIR}/sbin/start-stop-daemon ${ROOT_DIR}/sbin/start-stop-daemon.REAL
cat >${ROOT_DIR}/sbin/start-stop-daemon<<EOF
#!/bin/sh
echo
echo "Warning: Fake start-stop-daemon called, doing nothing"
EOF
chmod 755 ${ROOT_DIR}/sbin/start-stop-daemon

# set up apt
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_PRIORITY=critical
cat >${ROOT_DIR}/etc/apt/apt.conf<<EOF
Acquire::Pdiffs "false";
APT::Install-Recommends "false";
EOF
cat >${ROOT_DIR}/etc/apt/sources.list<<EOF
deb http://http.us.debian.org/debian ${DIST} main contrib non-free
deb http://security.debian.org/ ${DIST}/updates main contrib non-free
EOF
(chroot ${ROOT_DIR} aptitude update)

# set up base system
echo "en_US.UTF-8 UTF-8" >${ROOT_DIR}/etc/locale.gen
(chroot ${ROOT_DIR} aptitude install -y locales)

k=$(wget -O- http://queued.mit.edu/~dilinger/builds-master/ | sed -ne 's/.*href="\(.\+\)_i386.deb".*/\1_i386.deb/p' | tail -n1)
wget -O ${ROOT_DIR}/${k} http://queued.mit.edu/~dilinger/builds-master/${k}
(chroot ${ROOT_DIR} dpkg -i /${k})
rm -f ${ROOT_DIR}/${k}

echo "debxo" > ${ROOT_DIR}/etc/hostname
cat >${ROOT_DIR}/etc/hosts<<EOF
127.0.0.1 localhost.localdomain localhost
127.0.0.1 debxo

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
EOF

# install packages
(chroot ${ROOT_DIR} aptitude install -y `cat package_list`)

# configure X
cat >${ROOT_DIR}/etc/X11/xorg.conf<<EOF
# xorg.conf (X.Org X Window System server configuration file)

Section "Monitor"
	Identifier "Configured Monitor"
	HorizSync 30-67
	VertRefresh 48-52
	DisplaySize 152 114
	Mode "1200x900"
		DotClock 57.275
		HTimings 1200 1208 1216 1240
		VTimings 900 905 908 912
		Flags "-HSync" "-VSync"
	EndMode
EndSection

Section "Screen"
	Identifier "Default Screen"
	Monitor "Configured Monitor"
EndSection
EOF

# configure gdm, gnome
sed -i 's_\[daemon\]_\[daemon\]\n\nGreeter=/usr/lib/gdm/gdmlogin\n\nAutomaticLoginEnable=true\n\nAutomaticLogin=olpc_' ${ROOT_DIR}/etc/gdm/gdm.conf
cat >${ROOT_DIR}/etc/gconf/2/local-defaults.path<<EOF
# DebXO defaults (customized for the XO-1's display
xml:readonly:/etc/gconf/debxo.xml.defaults
EOF
mkdir -p ${ROOT_DIR}/etc/gconf/debxo.xml.defaults
cp %gconf-tree.xml ${ROOT_DIR}/etc/gconf/debxo.xml.defaults/

# add default user
(chroot ${ROOT_DIR} passwd -l root)
(chroot ${ROOT_DIR} useradd -s /bin/bash --create-home ${DEFUSER})
(chroot ${ROOT_DIR} passwd -d ${DEFUSER})
(chroot ${ROOT_DIR} adduser ${DEFUSER} cdrom)
(chroot ${ROOT_DIR} adduser ${DEFUSER} audio)
(chroot ${ROOT_DIR} adduser ${DEFUSER} video)
(chroot ${ROOT_DIR} adduser ${DEFUSER} plugdev)
(chroot ${ROOT_DIR} adduser ${DEFUSER} netdev)
(chroot ${ROOT_DIR} adduser ${DEFUSER} powerdev)
echo "${DEFUSER} ALL=(ALL) ALL" >> ${ROOT_DIR}/etc/sudoers

# done, clean up
mv ${ROOT_DIR}/sbin/start-stop-daemon.REAL ${ROOT_DIR}/sbin/start-stop-daemon
(chroot ${ROOT_DIR} aptitude clean)
umount ${ROOT_DIR}/proc
umount ${ROOT_DIR}/dev/pts
rm -rf ${ROOT_DIR}/home/*; 	# i have no idea what's adding this crap...
rm -f ${ROOT_DIR}/var/cache/apt/*.bin