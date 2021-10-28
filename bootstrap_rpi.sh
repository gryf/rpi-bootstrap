#!/usr/bin/env bash

# Write raspbian image provided via commandline to the passed device, and do
# the basic boostrap - configure network, add ssh key and so on.

set -ex

show_help() {
    echo "Usage:"
    echo "$0" device-to-write os-image-filename
}

write_to_device() {
    local device="${1}"
    local image="${2}"
    dd if="${image}" of="${device}" bs=10240
}

mount_partition() {
    local device="$1"
    local mntpoint="$2"
    mount "$device" "$mntpoint"
}

umount_partition() {
    local device="$1"
    umount "$device"
}

enable_ssh_on_boot() {
    local mntpoint="$1"
    touch "${mntpoint}/ssh"
}

set_hostname() {
    local mntpoint="$1"
    echo "${HOSTN}" > "${mntpoint}/etc/hostname"
    # default hostname for raspbian is raspberrypi
    sed -ie "s/raspberrypi/${HOSTN}/" "${mntpoint}/etc/hosts"
}

setup_net() {
    local mntpoint="$1"
    {
        echo
        echo "interface eth0"
        echo "static ip_address=$IP/$NETMASK"
        echo "static routers=${GATEWAY}"
        echo "static domain_name_servers=$NAMESERVERS"
        echo "metric 200"
        echo
        echo "interface wlan0"
        echo "static ip_address=$IP/$NETMASK"
        echo "static routers=${GATEWAY}"
        echo "static domain_name_servers=$NAMESERVERS"
        echo "metric 300"
    } >> "${mntpoint}/etc/dhcpcd.conf"

    {
        echo "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev"
        echo "update_config=1"
        echo "country=${COUNTRY}"
        echo
        echo "network={"
        echo "    ssid=\"${SSID}\""
        echo "    psk=\"${WIFIPSK}\""
        echo "}"
    } > "${mntpoint}/etc/wpa_supplicant/wpa_supplicant.conf"
}

copy_authorized_key() {
    local mntpoint="$1"
    if [ ! -d "${mntpoint}/home/pi/.ssh" ]; then
        mkdir "${mntpoint}/home/pi/.ssh"
        chmod 700 "${mntpoint}/home/pi/.ssh"
        chown 1000:1000 "${mntpoint}/home/pi/.ssh"
    fi

    if [ ! -f "${mntpoint}/home/pi/.ssh/authorized_keys" ]; then
        touch "${mntpoint}/home/pi/.ssh/authorized_keys"
        chmod 600 "${mntpoint}/home/pi/.ssh/authorized_keys"
        chown 1000:1000 "${mntpoint}/home/pi/.ssh/authorized_keys"
    fi
    echo "${SSHKEY}" >> "${mntpoint}/home/pi/.ssh/authorized_keys"
}

copy_sshd_keys() {
    local mntpoint="$1"
    if [ ! -d "ssh_keys" ]; then
        echo "No sshd keys found, skipping"
        return
    fi
    for fname in ssh_keys/*; do
        cp "${fname}" "$mntpoint/etc/ssh"
    done
    chmod 600 $mntpoint/etc/ssh/*key
    chmod 644 $mntpoint/etc/ssh/*pub

    # don't (re)generate keys, which are already there.
    rm "${mntpoint}/etc/systemd/system/multi-user.target.wants/"`
        `"regenerate_ssh_host_keys.service"
}

set_locale() {
    local mntpoint="$1"
    # If there is a need, specific locales can be generated (locale-gen will
    # be invoked on system update)
    # {
    #     echo "pl_PL.UTF-8 UTF-8"
    #     echo "en_US.UTF-8 UTF-8"
    # } > "${mntpoint}/etc/locale.gen"

    # UK kbd layout can be problematic
    sed -ie "s/gb/${KBDLAYOUT}/" "$mntpoint/etc/default/keyboard"
    # most of the cases C.UTF-8 will be enough
    sed -ie "s/en_GB.UTF-8/${DEFAULTLOCALE}/" "$mntpoint/etc/default/locale"
}

clear_soft_rfkill() {
    local mntpoint="$1"
    for fname in $mntpoint/var/lib/systemd/rfkill/platform*; do
        echo 0 > $fname
    done
}

remove_pi_pass() {
    local mntpoint="$1"

    # default hash for pi password on official raspbian image
    local pattern='$6$KUf.pHy0JZ2A8C.G$1ybG8vZLdxRFmSh0NqZ9v3zTEX3LQ'
    pattern+='lCuSDZLYrseM1lys364EB59Pq89g92bRSxpur3ca.gmOyKHXQndxLKwP0'

    sed -ie 's/$6$KUf.pHy0JZ2A8C.G$1ybG8vZLdxRFmSh0NqZ9v3zTEX3LQ//' \
        "$mntpoint/etc/shadow"
}


copy_pi_files() {
    local dst="${1}"
    local src="pi"

    if ! shopt dotglob; then
        reset=1
    fi

    shopt -s dotglob
    cp -a ${src}/* "${dst}/"

    if [ "$reset" -eq 1 ]; then
        shopt -u dotglob
    fi
}

if [ $# -ne 2 ]; then
    show_help
    exit 1
fi

DEVICE=$1
IMAGE=$2

if [ ! -f params ]; then
    echo "File 'params' doesn't exists. Expecting to have this file "
    echo "filled with right information."
    exit 2
fi

source ./params

write_to_device "${DEVICE}" "${IMAGE}"

boot_mnt=$(mktemp -d pixie.XXX)
fs_mnt=$(mktemp -d pixie.XXX)

mount_partition "${DEVICE}1" "${boot_mnt}"
mount_partition "${DEVICE}2" "${fs_mnt}"

enable_ssh_on_boot "${boot_mnt}"
set_hostname "${fs_mnt}"
setup_net "${fs_mnt}"
set_locale "${fs_mnt}"
copy_sshd_keys "${fs_mnt}"
copy_authorized_key "${fs_mnt}"
clear_soft_rfkill "${fs_mnt}"
remove_pi_pass "${fs_mnt}"
copy_pi_files "${fs_mnt}/home/pi"

umount_partition "${boot_mnt}"
umount_partition "${fs_mnt}"

rm -fr "${boot_mnt}"
rm -fr "${fs_mnt}"
