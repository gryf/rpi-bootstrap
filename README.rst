=========================
Raspberry Pi OS bootstrap
=========================

This repository contains simple script, which will prepare modified image of
`Raspbery Pi OS`_ and write it to microSD card/usb drive (if the destination
is a device), so that Raspberry Pi can be first-boot in completely headless
manners.

With this script you will be able to:

- modify a copy of `Raspberry Pi OS`_ Bookworm (preferably Lite version)
- configure network:
  - selects country for wlan and configure ssid and password
  - configure static ip address for both - wifi and ethernet
- remove soft rfkill for wifi and bt
- enable sshd
- set locale, keyboard layout and timezone
- add public ssh key to access RPi
- add password to the default user
- set hostname
- copy sshd keys (server keys, just to avoid annoying key change notice
  during ssh from clients)
- copy user files which speeds up configuration - like dotfiles, scripts, other
  files into default user directory. Note, that image will not be resized, so
  available space is a little above 300MB.


Requirements
============

- MicroSD card or some working USB drive (pendrive, hdd on usb and so on)
- Downloaded and unpacked `Raspberry Pi OS`_
- ``sudo``/``doas`` programs to execute some of the commands with elevated
  privileges
- some tools, like programs from ``coreutils``, ``sed``, ``grep`` and ``fdisk``

Before you start, you need to prepare ``custom.toml``.


custom.toml
-----------

This file is officially supported method of `Raspberry Pi OS`_ customization.
Repository with the code for this mechanism can be `found on GitHub`_. It can
be used without this script by just copying it into boot partition. Although
`this repo holds modified`_ ``init_config`` script, which adds additional
config options. All currently supported fields are as follows:

.. code:: toml

   config_version = 1  # this line is required, otherwise file will be ignored

   [system]
   hostname =  # string, set a hostname

   [user]
   name =  # string, default user name
   password =  # string, optional password for the user
   password_encrypted =  # bool, indicates if above password is encrypted

   [ssh]
   ssh_import_id =  # string, import keys from i.e. github
   enabled =  # bool, if true, make sshd to start with system
   password_authentication =  # bool, whether or not enable pass auth
   authorized_keys = []  # list of strings, public keys to be add for a user

   [wlan]
   ssid =  # string, SSID of the wireless network
   password =  # string, password for Wi-Fi
   password_encrypted =  # bool, whether or not above password is encrypted
   hidden =  # bool, indicates network SSID is hidden
   country =  # string, two-letter country code (uppercase)
   ip =  # string, IP address
   netmask =  # string, netmask
   gateway =  # string, address of the
   dns = []  # list of strings, DNS addresses

   [wired]
   ip =  # string, IP address
   netmask =  # string, netmask
   gateway =  # string, address of the
   dns = []  # list of strings, DNS addresses

   [locale]
   keymap =  # string, two-letter country code (lowercase)
   timezone =  # string timezone, like Europe/Warsaw
   default_locale =  # string, default system LANG variable, i.e. en_US.UTF-8


User files
==========

Optionally, you can make a ``pi`` directory in current directory, or use ``-u``
commandline option to point directory which holds the files, which all the
contents would be copy to the ``/home/pi`` directory, so you'll find
those after RPi boots up.

Note, that if you define new user name using ``custom.toml`` file, those files
will be accessible under new user.


SSHD keys
=========

If you want to preserve SSH server keys, you can do that by copying them to the
``sshd_keys`` directory in current path, or use commandline option ``-s`` to
point to directory, which holds sshd keys. It will be copied if found,
otherwise keys will be generated again next time you master the image and run
the system.


Usage
=====

Now, you can invoke the command:

.. code:: shell-session

   $ ./bootstrap_rpi.sh <options> source_image [destination_image|device]

Given, the /dev/sdk is the device which you will want to populate with the
Raspberry Pi OS, that would be:

.. code:: shell-session

   $ ./bootstrap_rpi.sh ~/Downloads/2024-07-04-raspios-bookworm-arm64-lite.img /dev/sdk

This will create a copy of provided image, make the changes on that copy and
write it to the device.

When RPi is booted with that device (whatever it was, USB pendrive, microSD
card, hardrive/SSD connected by USB) and depending of what you configured using
``custom.toml`` you'll be able to connect to RPi via SSH using whatever address
you provided using either Ethernet or Wi-Fi.

Now, you can run whatever post-install things you want to perform either
manually or script - that's up to you.

.. _Raspberry Pi OS: https://www.raspberrypi.com/software/operating-systems
.. _found on GitHub: https://github.com/RPi-Distro/raspberrypi-sys-mods
.. _this repo hold modified: https://github.com/gryf/raspberrypi-sys-mods
