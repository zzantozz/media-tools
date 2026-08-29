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
echo "Local drives should be shared via cifs, not vbox shared folders. It performs better, and I can mount them consistently"
echo "across multiple other devices. fstab entries should look like this:"
echo ""

echo "//192.168.1.100/d /mnt/d cifs credentials=/home/ryan/smbcreds,uid=1000,gid=1000,vers=3.1.1,nofail"
echo "//192.168.1.100/j /mnt/j cifs credentials=/home/ryan/smbcreds,uid=1000,gid=1000,vers=3.1.1,nofail"
echo "//192.168.1.100/k /mnt/k cifs credentials=/home/ryan/smbcreds,uid=1000,gid=1000,vers=3.1.1,nofail"
echo "//192.168.1.100/l /mnt/l cifs credentials=/home/ryan/smbcreds,uid=1000,gid=1000,vers=3.1.1,nofail"
echo "//192.168.1.101/plex-media /mnt/plex-media cifs credentials=/home/ryan/smbcreds,uid=1000,gid=1000,vers=3.1.1,nofail"
echo ""
echo "Then create the 'smbcreds' file in your home dir with the following content:"
echo ""
echo "username=<user>"
echo "password=<pass>"
echo ""
echo "and then secure it:"
echo ""
echo "chmod 400 ~/smbcreds"
echo ""
