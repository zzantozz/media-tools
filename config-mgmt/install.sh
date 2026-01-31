#!/bin/bash

# Installs the things I need for everything here to work (on Ubuntu)
# Which of these things installed postfix??
#
sudo apt -y install ffmpeg cifs-utils git iotop nmap sqlite3 emacs
sudo update-alternatives --set editor "$(which emacs)"
echo "alias em=emacs" >>~/.bashrc
for mount in d j k l plex-media; do
  sudo mkdir -p /mnt/$mount
done

if ! grep '^set expandtab$' ~/.vimrc &>/dev/null; then
  cat <<EOF >> ~/.vimrc
set tabstop=2
set shiftwidth=2
set expandtab
set autoindent
EOF
fi

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
echo ''
echo " ******************* "
echo " ******************* "
echo "  IMPORTANT NOTE: To analyze blurays, you need a lot of RAM - at least 8G, if not more. Optimizing that script might"
echo "  be a good idea..."
echo " ******************* "
echo " ******************* "
