#!/usr/bin/env bash

# Create raspios image based on Bookworm (Debian 12) provided via commandline
# to the destination image or device, do the basic configuration - configure
# network, add ssh key and so on.

set -e

#defaults
SSHD_KEYS_DIR="sshd_keys"
USER_FILES="pi"
CUSTOM="custom.toml"
VERBOSE=0
DEBUG=0

show_help() {
    cat <<EOF
$0 <options> src_image [dst_image|device]

Options:
-h      this help
-c      path to custom.toml, default: "./custom.toml"
-s      sshd directory, which holds server ssh keys, "./sshd_keys" by default
-u      user files directory, which contents be copy to default user,
        "./pi" by default
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

mount_image() {
    local mountpoint=$1
    local image=$2
    local partition=$3

    startblock=$(fdisk -l -o device,start "${image}" | \
        grep ^"$partition" | cut -d ' ' -f 2- | sed -e 's/^\ *//')
    fssize=$(fdisk -l -o device,sectors "${image}" | \
        grep ^"$partition"| cut -d ' ' -f 2- | sed -e 's/^\ *//')
    offset=$((startblock * 512))
    sizelimit=$((fssize * 512))
    _sudo mount -o offset=$offset,sizelimit=$sizelimit "$image" "$mountpoint"
}

copy_sshd_keys() {
    _verbose && echo "Copying sshd keys"
    local mntpoint="$1"
    local script="$1/usr/lib/raspberrypi-sys-mods/regenerate_ssh_host_keys"
    if [ ! -d "${SSHD_KEYS_DIR}" ]; then
        echo "No sshd keys found, skipping"
        return
    fi
    for fname in "${SSHD_KEYS_DIR}"/*; do
        _sudo cp "${fname}" "$mntpoint/etc/ssh"
    done
    _sudo chmod 600 $mntpoint/etc/ssh/*key
    _sudo chmod 644 $mntpoint/etc/ssh/*pub

    # don't (re)generate keys, which are already there.
    _sudo sed -i -e 's/^rm/#rm/' "${script}"
    _sudo sed -i -e 's/^ssh-keygen/#ssh-keygen/' "${script}"
}

clear_soft_rfkill() {
    _verbose && echo "Clear soft rfkill - enabling BT and Wlan on boot"
    local mntpoint="$1"
    for fname in $mntpoint/var/lib/systemd/rfkill/platform*; do
        echo 0 | _sudo tee $fname >/dev/null
    done
}

copy_user_files() {
    _verbose && echo "Copying user files"
    local dst="${1}"
    local src="${USER_FILES}"
    if [[ ! -e "${src}" ]]; then
        echo "No user files to copy"
        return
    fi

    cp -r ${src}/. "${dst}/"
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

get_and_copy_init_config() {
    _verbose && echo "Clone raspberrypi-sys-mods repo and replace init_config with the one from repo"

    local dst="$1"
    git clone https://github.com/gryf/raspberrypi-sys-mods \
        /tmp/rsm -b 2024-07-04 &>/dev/null
    _sudo cp /tmp/rsm/usr/lib/raspberrypi-sys-mods/init_config \
        "$dst/usr/lib/raspberrypi-sys-mods/"
    rm -fr /tmp/rsm
}

while getopts c:s:u:hvd opt; do
    case $opt in
        c)
            CUSTOM="${OPTARG}"
            ;;
        s)
            SSHD_KEYS_DIR="${OPTARG}"
            ;;
        u)
            USER_FILES="${OPTARG}"
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

# Prepare mountpoints. both are the same with a pattern rpi_X.YYY, where X is
# partition number and Y is random character
_verbose && echo "Creating temporary mountpoint directory"
boot_mnt=$(mktemp -d rpi_1.XXX)
fs_mnt=${boot_mnt/1/2}
mkdir "${fs_mnt}"

# copy image. if destination is device, make a phony file
if [[ "${DST}" == /dev/* ]]; then
    _verbose && echo "Copy image to temporary place"
    tmp_imgname=$(mktemp)
else
    _verbose && echo "Copy image to destination file"
    tmp_imgname="${DST}"
fi

cp "${SRC}" "${tmp_imgname}"

# identify and mount image
partitions=$(LANG=C fdisk -l -o device "${tmp_imgname}" | \
    sed -n '/^Device$/,$p' | tail -n +2)
_verbose && echo "Mounting image partitions"
for part in $partitions; do
    part_no="${part/$tmp_imgname}"
    mnt_dst="${boot_mnt/1/$part_no}"
    mount_image "${mnt_dst}" "${tmp_imgname}" "${part}"
done

# copy custom.toml file to boot
copy_customization "${boot_mnt}"
# overwrite init_config script
get_and_copy_init_config "${fs_mnt}"
copy_sshd_keys "${fs_mnt}"
clear_soft_rfkill "${fs_mnt}"
copy_user_files "${fs_mnt}/home/pi"

_verbose && echo "Unmounting image"
_sudo umount "${boot_mnt}"
_sudo umount "${fs_mnt}"

_verbose && echo "Removing temporary mountpoints"
rm -fr "${boot_mnt}"
rm -fr "${fs_mnt}"

if [[ "${DST}" == /dev/* ]]; then
    write_to_device "${tmp_imgname}" "${DST}"
    rm "${tmp_imgname}"
fi
_verbose && echo "All done"
