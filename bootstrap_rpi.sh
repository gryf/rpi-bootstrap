#!/usr/bin/env bash

# Write raspios image based on Bookworm (Debian 12) provided via commandline
# to the passed device, and do the basic boostrap - configure network, add
# ssh key and so on.

set -e  # x

show_help() {
    echo "Usage:"
    echo "$0" device-to-write os-image-filename
}

write_to_device() {
    dd if="${IMAGE}" of="${DEVICE}" bs=10240
}

enable_ssh_on_boot() {
    local mntpoint="$1"
    touch "${mntpoint}/ssh"
}

set_hostname() {
    local mntpoint="$1"
    if [ -z "${PIHOSTNAME}" ]; then
        echo "No hostname for RPi defined. Leaving default."
        return
    fi
    echo "${PIHOSTNAME}" > "${mntpoint}/etc/hostname"
    # default hostname for raspbian is raspberrypi
    sed -ie "s/raspberrypi/${PIHOSTNAME}/" "${mntpoint}/etc/hosts"
    echo "Hostname for RPi chaned to '${PIHOSTNAME}'."
}

setup_net() {
    local mntpoint="$1"
    if [ -z "${IP}" ] || [ -z "${GATEWAY}" ] || [ -z "${NETMASK}" ] || \
        [ -z "${NAMESERVERS}" ]; then
        echo -n "One (or more) variable is missing for configuring static "
        echo "network. Check variables:"
        echo IP
        echo NETMASK
        echo GATEWAY
        echo NAMESERVERS
        echo "in params file. Skipping."
    else
        # adopt nameservers string to nm
        local nameservers="$(echo $NAMESERVERS|sed -e 's/ /;/g');"
        {
            echo "[connection]"
            echo "id=Wired connection 1"
            echo "uuid=b9851567-b78b-3cc2-befb-b0c0a14ecfbc"
            echo "type=ethernet"
            echo "autoconnect-priority=-999"
            echo "interface-name=eth0"
            echo "timestamp=1704617134"
            echo ""
            echo "[ethernet]"
            echo ""
            echo "[ipv4]"
            echo "address1=${IP}/${NETMASK}/${GATEWAY}"
            echo "dns=$nameservers"
            echo "method=manual"
            echo ""
            echo "[ipv6]"
            echo "addr-gen-mode=default"
            echo "method=disabled"
            echo ""
            echo "[proxy]"
        } > "${mntpoint}/etc/NetworkManager/system-connections/Wired connection 1.nmconnection"
        chmod 600 "${mntpoint}/etc/NetworkManager/system-connections/Wired connection 1.nmconnection"
    fi

    if [ -z "${SSID}" ] || [ -z "${WIFIPSK}" ]; then
        echo -n "One (or more) variable is missing for configuring WIFI "
        echo "access. Check variables:"
        echo SSID
        echo WIFIPSK
        return
    fi
    {
        echo "[connection]"
        echo "id=${SSID}"
        echo "uuid=3a48e59d-703d-4fae-baa3-176c8b403a95"
        echo "type=wifi"
        echo "interface-name=wlan0"
        echo ""
        echo "[wifi]"
        echo "mode=infrastructure"
        echo "ssid=${SSID}"
        echo ""
        echo "[wifi-security]"
        echo "auth-alg=open"
        echo "key-mgmt=wpa-psk"
        echo "psk=${WIFIPSK}"
        echo ""
        echo "[ipv4]"
        echo "address1=${IP}/${NETMASK},${GATEWAY}"
        echo "dns=$nameservers"
        echo "method=manual"
        echo ""
        echo "[ipv6]"
        echo "addr-gen-mode=default"
        echo "method=disabled"
        echo ""
        echo "[proxy]"
        } > "${mntpoint}/etc/NetworkManager/system-connections/${SSID}.nmconnection"
       chmod 600 "${mntpoint}/etc/NetworkManager/system-connections/${SSID}.nmconnection"
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

    if [[ -f "${SSHKEY}" ]]; then
        # if SSHKEY contain filename pointing to the ssh key, use it
        cat "${SSHKEY}" >> "${mntpoint}/home/pi/.ssh/authorized_keys"
    else
        # or treat it as string containing the key.
        echo "${SSHKEY}" >> "${mntpoint}/home/pi/.ssh/authorized_keys"
    fi
}

copy_sshd_keys() {
    local mntpoint="$1"
    if [ ! -d "sshd_keys" ]; then
        echo "No sshd keys found, skipping"
        return
    fi
    for fname in sshd_keys/*; do
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

disable_interactive_setup() {
    # just replace ExecStart with cancel-rename, which will stop renaming
    # process for user pi and will enable getty.
    local mntpoint="$1"
    sed -ie 's~ExecStart=.*~ExecStart=/usr/bin/cancel-rename~g' \
        "$mntpoint/lib/systemd/system/userconfig.service"
}

disable_regenerating_sshd_keys() {
    # remove regenerate_ssh_host_keys from main in usr/lib/raspberrypi-sys-mods/firstboot
    local mntpoint="$1"
    sed -ie 's/  regenerate_ssh_host_keys$//g' \
        "$mntpoint/usr/lib/raspberrypi-sys-mods/firstboot"
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

write_to_device

boot_mnt=$(mktemp -d pixie.XXX)
fs_mnt=$(mktemp -d pixie.XXX)

mount "${DEVICE}1" "${boot_mnt}"
mount "${DEVICE}2" "${fs_mnt}"

disable_interactive_setup "${fs_mnt}"
if [[ -f sshd_keys ]]; then
    disable_regenerating_sshd_keys "${fs_mnt}"
fi
enable_ssh_on_boot "${boot_mnt}"
set_hostname "${fs_mnt}"
setup_net "${fs_mnt}"
set_locale "${fs_mnt}"
copy_sshd_keys "${fs_mnt}"
copy_authorized_key "${fs_mnt}"
clear_soft_rfkill "${fs_mnt}"
remove_pi_pass "${fs_mnt}"
copy_pi_files "${fs_mnt}/home/pi"

umount "${boot_mnt}"
umount "${fs_mnt}"

rm -fr "${boot_mnt}"
rm -fr "${fs_mnt}"
