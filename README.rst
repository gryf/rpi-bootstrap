=========================
Raspberry Pi OS bootstrap
=========================

This repository contains simple bootstrap script, which will prepare sdcard/usb
drive, so that Raspberry Pi can be first-boot in completely headless manners.
This script will:

- write `Raspberry Pi OS`_ Bullseye (preferably Lite version) on selected device
- configure network (both - wifi and ethernet) with static address
- remove soft rfkill for wifi and bt, so it will be active during
- enable ssh
- set locale/keyboard layout
- add ssh key
- remove password for pi user (so no one will be able to login using default
  or any password for that user)
- set hostname
- optionally copy sshd keys


Requirements
============

- Raspberry Pi (tested with Pi4)
- MicroSD card or some working USB drive (pendrive, hdd on usb and so on)
- Root/sudo privileges
- Downloaded and unpacked Raspberry Pi OS


Usage
-----

Before you start, you need to prepare `params` shell file, which would contain
all, or some of the variables:

- ``COUNTRY`` - needed for wifi configuration. *UK* by default.
- ``DEFAULTLOCALE`` - locale for the system, default is *en_UK.utf-8*.
- ``PIHOSTNAME`` - hostname for the OS. Default is 'raspberrypi'.
- ``KBDLAYOUT`` - keyboard layout for the console. Default *gb*.
- ``SSHKEY`` - public key for accessing pi account.
- ``SSID`` - wifi SSID network. Leave it if you don't want to configure wifi.
- ``WIFIPSK`` - wifi password. Leave it if you don't want to configure wifi.
- ``GATEWAY`` - IP address for gateway. Leave it if you like to use DHCP.
- ``IP`` - IP address for RPi. Leave it if you like to use DHCP.
- ``NAMESERVERS`` - DNS servers for RPi. Leave it if you like to use DHCP.
- ``NETMASK`` - network netmask for RPi. Leave it if you like to use DHCP.

Note, that same IP address will be used for both ``eth0`` and ``wlan0``
interfaces, if variables for wifi ``SSID`` and ``WIFIPSK`` would be found.

Optionally, you may want to prepare directory with ssh server keys, to have
predictable SSH server access. To do so, you'll need to create directory
``ssh_keys`` in current path and copy all the keys (both ssh_host_*_key and
ssh_host_*_key.pub) from some running instance.

Optionally, you can make a ``pi`` directory in current directory, which all the
contents would be copy to the ``/home/pi`` directory, so you'll find those
after RPi boots up.

Now, you can invoke the command:

.. code:: shell-session

   $ sudo ./bootstrap_rpi.sh <device> <image-file-name>


Given, the /dev/sdk is the device which you will want to populate with the
Raspberry Pi OS, that would be:

.. code:: shell-session

   $ sudo ./bootstrap_rpi.sh /dev/sdk ~/Downloads/2022-09-22-raspios-bullseye-arm64-lite.img

When it finishes, move the device (sdcard, usb thumb drive or disk drive
connected by the usb interface) to the Raspberry Pi and boot it up. Now you'll
be able to connect to it via ssh. RPi can be connected via the ethernet cable
or the wifi - it will have same IP addres for both interfaces, and ethernet
will be preferred over wifi.

Now, you can run whatever post-install things you want to perform either
manually or script - that's up to you.

.. _Raspberry Pi OS: https://www.raspberrypi.com/software/operating-systems
