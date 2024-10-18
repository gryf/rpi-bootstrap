=========================
Raspberry Pi OS bootstrap
=========================

This repository contains simple bootstrap script, which will prepare sdcard/usb
drive, so that Raspberry Pi can be first-boot in completely headless manners.
With this script you will be able to:

- modify a copy of `Raspberry Pi OS`_ Bookworm (preferably Lite version)
- configure network:
  - selects country for wlan and configure ssid and password
  - configure static ip address for both - wifi and ethernet
- remove soft rfkill for wifi and bt, so it will be active during
- enable sshd with some basic config
- set locale, keyboard layout and timezone
- add public ssh key to access RPi
- optionally add password to the default user
- set hostname
- optionally copy sshd keys


Requirements
============

- Raspberry Pi (tested with Pi4)
- MicroSD card or some working USB drive (pendrive, hdd on usb and so on)
- Root/sudo privileges
- Downloaded and unpacked Raspberry Pi OS
- ``sudo``/``doas`` programs to execute some of the commands with elevated
  privileges

Before you start, you need to prepare two files. One of them is already
supported ``custom.toml`` and/or ``params`` for more fine grained network and
system configuration.


custom.toml
-----------

todo

params
------

``params`` is a shell file, which is expected to contain variables:

- ``DEFAULTLOCALE`` - locale for the system, default is *en_UK.utf-8*.
- ``PIHOSTNAME`` - hostname for the OS. Default is 'raspberrypi'.
- ``KBDLAYOUT`` - keyboard layout for the console. Default *gb*.
- ``SSHKEY`` - public key for accessing pi account.
- ``SSID`` - wifi SSID network. Leave it if you don't want to configure wifi.
- ``WIFIPSK`` - wifi password. Leave it if you don't want to configure wifi.
- ``GATEWAY`` - IP address for gateway. Leave it if you like to use DHCP.
- ``IP`` - IP address for RPi. Leave it if you like to use DHCP.
- ``NAMESERVERS`` - space separated DNS servers for RPi. Leave it if you like
  to use DHCP.
- ``NETMASK`` - network netmask for RPi. Leave it if you like to use DHCP.

First one is a setting to override default ``en_GB.UTF-8`` locale variable,
which might be inaccurate for some people.

All the rest are the variables used to set static IP address for both wired and
wireless interfaces. Note, that basic wireless configuration is done within
``custom.toml`` file.

Optionally, you may want to prepare directory with ssh server keys, to have
predictable SSH server access. To do so, you'll need to create directory
``ssh_keys`` in current path and copy all the keys (both ssh_host_*_key and
ssh_host_*_key.pub) from some running instance.

User files
==========

Optionally, you can make a ``pi`` directory in current directory, which all the
contents would be copy to the ``/home/[username]`` directory, so you'll find
those after RPi boots up.

SSHD keys
=========

If you want to preserve SSH server keys, you can do that by copying them to the
``sshd_keys`` directory. It will be copied if found, otherwise keys will be
generated again next time you master the image.

Usage
=====

Now, you can invoke the command:

.. code:: shell-session

   $ ./bootstrap_rpi.sh <source image> <destination image>


Given, the /dev/sdk is the device which you will want to populate with the
Raspberry Pi OS, that would be:

.. code:: shell-session

   $ ./bootstrap_rpi.sh ~/Downloads/2023-12-11-raspios-bookworm-arm64-lite.img modified.img

When it finishes, write the image with your favorite program, i.e. with ``dd``:

.. code:: shell-session

   $ sudo dd if=./modified.img of=/dev/sdk

then, remove the device (sdcard, usb thumb drive or disk drive connected by the
usb interface) connect it to the Raspberry Pi and boot it up. Now you'll be
able to connect to it via ssh. RPi can be connected via the ethernet cable or
the wifi - it will have same IP address for both interfaces, and ethernet will
be preferred over wifi.

Now, you can run whatever post-install things you want to perform either
manually or script - that's up to you.

.. _Raspberry Pi OS: https://www.raspberrypi.com/software/operating-systems
