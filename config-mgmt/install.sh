#!/bin/bash

# Installs the things I need for everything here to work (on Ubuntu)

sudo apt -y install ffmpeg cifs-utils git iotop nmap sqlite3 emacs
sudo update-alternatives --set editor "$(which emacs)"

echo ""
echo " ***"
echo "Assuming, drives are shared in vbox using their lowercase drive letters, you'll want some fstab entries like this:"
echo "d /mnt/d vboxsf defaults,nofail"
echo "j /mnt/j vboxsf defaults,nofail"
echo "k /mnt/k vboxsf defaults,nofail"
echo "l /mnt/l vboxsf defaults,nofail"
echo ""
echo "You can mount the plex-media output dir with the following:"
echo 'sudo mount -t cifs -o user=ryan,uid=$USER,gid=$USER //192.168.1.125/plex-media /mnt/plex-media/'
