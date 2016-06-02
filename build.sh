#!/bin/bash

set -ex

BRANCH=$(git rev-parse --abbrev-ref HEAD)

function setup {
	sudo rm -rf rootfs*
	wget http://opensource.nextthing.co/chippian/rootfs/rootfs.tar.gz
	sudo tar -xf rootfs.tar.gz
}

function build_debian_chroot {
  export LANG=C

        sudo cp /usr/bin/qemu-arm-static rootfs/usr/bin/
        sudo cp /etc/resolv.conf rootfs/etc/

        sudo touch rootfs/usr/sbin/policy-rc.d
        sudo chmod a+w rootfs/usr/sbin/policy-rc.d
       echo >rootfs/usr/sbin/policy-rc.d <<EOF
echo "************************************" >&2
echo "All rc.d operations denied by policy" >&2
echo "************************************" >&2
exit 101
EOF
  sudo chmod 0755 rootfs/usr/sbin/policy-rc.d

  # mount proc, sys and dev
  sudo mount -t proc     chproc  rootfs/proc
  sudo mount -t sysfs    chsys   rootfs/sys
#  sudo mount -t devtmpfs chdev   rootfs/dev || mount --bind /dev rootfs/dev
#  sudo mount -t devpts   chpts   rootfs/dev/pts

        sudo chroot rootfs /bin/bash <<EOF
set -x

echo -e "chip\nchip\n" | passwd
echo "chip" >/etc/hostname
echo -e "127.0.0.1\tchip" >/tmp/hosts.tmp
cp /etc/hosts /tmp/hosts.bak
cat /tmp/hosts.tmp /tmp/hosts.bak >/etc/hosts

echo -e "\
deb http://ftp.us.debian.org/debian/ jessie main contrib non-free\n\
deb-src http://ftp.us.debian.org/debian/ jessie main contrib non-free\n\
\n\
deb http://security.debian.org/ jessie/updates main contrib non-free\n\
deb-src http://security.debian.org/ jessie/updates main contrib non-free\n\
\n\
deb http://http.debian.net/debian jessie-backports main contrib non-free\n\
deb-src http://http.debian.net/debian jessie-backports main contrib non-free\n\
\n\
deb http://opensource.nextthing.co/chip/debian/repo jessie main\n\
" >/etc/apt/sources.list

if [[ "$BRANCH" == "chip/next" ]]; then
	echo -e "\n\
deb http://opensource.nextthing.co/chip/debian/testing-repo testing main\n\
" >> /etc/apt/sources.list
fi

wget -qO - http://opensource.nextthing.co/chip/debian/repo/archive.key | apt-key add -

export DEBIAN_FRONTEND=noninteractive

apt-get update

#if [[ "$BRANCH" == "chip/next" ]]; then
#export FORCE=$(echo "--force-yes")
#fi

#echo "$FORCE"

apt-get -y --allow-unauthenticated install network-manager fake-hwclock ntpdate openssh-server sudo hostapd bluez \
                   lshw stress i2c-tools \
                   avahi-daemon cu\
                   flash-kernel \
                   alsa-utils htop \
                   binutils bzip2 ntp mlocate \
                   bc gawk mtd-utils openssl ca-certificates \
                   chip-power chip-hwtest curl chip-dt-overlays\
|| exit 1

chmod u+s `which ping`

#this is needs to be done after flash-kernel and before a kernel.deb is installed
echo "NextThing C.H.I.P." > /etc/flash-kernel/machine


if [[ "$BRANCH" == "chip/next" ]]; then
apt-get -y --allow-unauthenticated install linux-image-4.4.11 rtl8723bs-bt linux-firmware-image-4.4.11\
 rtl8723bs-mp-driver-common rtl8723bs-mp-driver-modules-4.4.11\
 chip-mali-modules
else
apt-get -y install linux-image-4.4.11 rtl8723bs-bt\
  rtl8723bs-mp-driver-common\
  rtl8723bs-mp-driver-modules-4.4.11
fi


#THIS NEEDS TO BE DONE BEFORE THE PULSE PACKAGE IS INSTALLED
echo -e "\
state.sun4icodec {
        control.1 {
                iface MIXER
                name 'Power Amplifier Volume'
                value 56
                comment {
                        access 'read write'
                        type INTEGER
                        count 1
                        range '0 - 63'
                        dbmin -9999999
                        dbmax 0
                        dbvalue.0 -700
                }
        }
        control.2 {
                iface MIXER
                name 'Left Mixer Left DAC Playback Switch'
                value false
                comment {
                        access 'read write'
                        type BOOLEAN
                        count 1
                }
        }
        control.3 {
                iface MIXER
                name 'Right Mixer Right DAC Playback Switch'
                value false
                comment {
                        access 'read write'
                        type BOOLEAN
                        count 1
                }
        }
        control.4 {
                iface MIXER
                name 'Right Mixer Left DAC Playback Switch'
                value false
                comment {
                        access 'read write'
                        type BOOLEAN
                        count 1
                }
        }
        control.5 {
                iface MIXER
                name 'Power Amplifier DAC Playback Switch'
                value true
                comment {
                        access 'read write'
                        type BOOLEAN
                        count 1
                }
        }
        control.6 {
                iface MIXER
                name 'Power Amplifier Mixer Playback Switch'
                value false
                comment {
                        access 'read write'
                        type BOOLEAN
                        count 1
                }
        }
        control.7 {
                iface MIXER
                name 'Power Amplifier Mute Switch'
                value true
                comment {
                        access 'read write'
                        type BOOLEAN
                        count 1
                }
        }
}
" >/var/lib/alsa/asound.state

alsactl restore

sed -s -i 's/#EXTRA_GROUPS="/EXTRA_GROUPS="netdev dip adm lp /' /etc/adduser.conf
sed -s -i 's/#ADD_EXTRA_GROUPS=/ADD_EXTRA_GROUPS=/' /etc/adduser.conf

# Load g_serial driver and enable getty on it
echo -e "\n# Virtual USB serial gadget\nttyGS0\n\n" >>/etc/securetty
ln -s /lib/systemd/system/serial-getty@.service /etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service

# quick and dirty solution since hwtest doesn't like dash:
rm /bin/sh
ln -s /bin/bash /bin/sh

if [[ "$BRANCH" == "chip/next" ]]; then
  echo "SERVER-NEXT" > /etc/os-variant
else
  echo "SERVER" > /etc/os-variant
fi


EOF

#sudo chown -R $USER:$USER *

for a in $(mount |grep $PWD|awk '{print $3}'); do sudo umount -l $a; done
#sudo rm -rf rootfs/proc/*
#sudo rm -rf rootfs/dev/*
#sudo rm -rf rootfs/run/*
#sudo rm -rf rootfs/sys/*

sudo tar -zvcf server-rootfs.tar.gz rootfs

}


setup
build_debian_chroot || exit $?

