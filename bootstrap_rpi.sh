#!/usr/bin/env bash

# Create raspios image based on Bookworm (Debian 12) provided via commandline
# to the destination image or device, do the basic configuration - configure
# network, add ssh key and so on.

set -e

#defaults
CUSTOM="custom.toml"
VERBOSE=0
DEBUG=0

show_help() {
    cat <<EOF
$0 <options> src_image [dst_image|device]

Options:
-h      this help
-c      path to custom.toml, default: "./custom.toml"
-v      be verbose
EOF
    exit ${1:-0}
}

_verbose() {
    [[ "$VERBOSE" -eq 1 ]] && return 0 || return 3
}

_sudo() {
    if which sudo &>/dev/null; then
        sudo "$@"
    elif which doas &>/dev/null; then
        doas "$@"
    else
        echo "Fatal: no sudo/doas found!"
        exit 10
    fi
}

write_to_device() {
    local image=$1
    local dest=$2
    _verbose && echo "Writing image to device ${dest}"
    _sudo dd status=progress if="${image}" of="${dest}" bs=10240
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
            echo "address1=${IP}/${NETMASK},${GATEWAY}"
            echo "dns=$nameservers"
            echo "method=manual"
            echo ""
            echo "[ipv6]"
            echo "addr-gen-mode=default"
            echo "method=disabled"
            echo ""
            echo "[proxy]"
        } | _sudo tee "${mntpoint}/etc/NetworkManager/system-connections/Wired connection 1.nmconnection" > /dev/null
        _sudo chmod 600 "${mntpoint}/etc/NetworkManager/system-connections/Wired connection 1.nmconnection"
    fi
}

copy_sshd_keys() {
    local mntpoint="$1"
    if [ ! -d "sshd_keys" ]; then
        echo "No sshd keys found, skipping"
        return
    fi
    for fname in sshd_keys/*; do
        _sudo cp "${fname}" "$mntpoint/etc/ssh"
    done
    _sudo chmod 600 $mntpoint/etc/ssh/*key
    _sudo chmod 644 $mntpoint/etc/ssh/*pub

    # don't (re)generate keys, which are already there.
    _sudo rm "${mntpoint}/etc/systemd/system/multi-user.target.wants/"`
        `"regenerate_ssh_host_keys.service"
}

set_locale() {
    local mntpoint="$1"
    # most of the cases C.UTF-8 will be enough
    _sudo sed -ie "s/en_GB.UTF-8/${DEFAULTLOCALE}/" "$mntpoint/etc/default/locale"
}

clear_soft_rfkill() {
    local mntpoint="$1"
    for fname in $mntpoint/var/lib/systemd/rfkill/platform*; do
        echo 0 | _sudo tee $fname >/dev/null
    done
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

copy_customization() {
    _verbose && echo "Copying ${CUSTOM} as custom.toml on boot partition"
    local dst="$1"
    if [[ -e "${CUSTOM}" ]]; then
        _sudo cp "${CUSTOM}" "$dst/custom.toml"
    else
        echo "'${CUSTOM}' file not found"
    fi
}

disable_interactive_setup() {
    # just replace ExecStart with cancel-rename, which will stop renaming
    # process for user pi and will enable getty.
    local mntpoint="$1"
    _sudo sed -ie 's~ExecStart=.*~ExecStart=/usr/bin/cancel-rename~g' \
        "$mntpoint/lib/systemd/system/userconfig.service"
}

disable_regenerating_sshd_keys() {
    # remove regenerate_ssh_host_keys from main in usr/lib/raspberrypi-sys-mods/firstboot
    local mntpoint="$1"
    _sudo sed -ie 's/  regenerate_ssh_host_keys$//g' \
        "$mntpoint/usr/lib/raspberrypi-sys-mods/firstboot"
}

while getopts c:s:u:hvd opt; do
    case $opt in
        c)
            CUSTOM="${OPTARG}"
            ;;
        v)
            VERBOSE=1
            ;;
        d)
            DEBUG=1
            ;;
        h)
            show_help
            ;;
        *)
            show_help 1
            ;;
    esac
done

if [[ "$DEBUG" -eq 1 ]]; then
    set -x
fi

SRC="${@:$OPTIND:1}"
DST="${@:$OPTIND+1:1}"

if [[ -z "${SRC}" || -z "${DST}" ]]; then
    show_help 1
fi

if [ ! -f params ]; then
    echo "File 'params' doesn't exists. Expecting to have this file "
    echo "filled with right information."
    exit 2
fi

source ./params

write_to_device "$SRC" "$DST"

boot_mnt=$(mktemp -d pixie.XXX)
fs_mnt=$(mktemp -d pixie.XXX)

mount "${DST}1" "${boot_mnt}"
mount "${DST}2" "${fs_mnt}"

# get init_config and apply customization
copy_customization "${boot_mnt}"
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
