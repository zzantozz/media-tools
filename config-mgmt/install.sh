#!/bin/bash

# Official docker setup to get access to compose
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# Installs the things I need for everything here to work (on Ubuntu)
# Which of these things installed postfix??
sudo apt update
sudo apt -y install ffmpeg cifs-utils git iotop nmap sqlite3 emacs
# packages recommended by docker - are all these necessary?
sudo apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER

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
echo "Also, this script has modified init files and user permissions. It would be best to log out and in now."
echo ""
echo "Finally, if all has gone as planned, you should be able to build an image with ffmpeg and encode with it:"
echo ""
echo "docker build -t ffmpeg-for-server ."
echo "rm -f allinone/stop; docker compose down; docker compose up --scale ffmpeg=1 -d; docker compose logs -f"
echo ""
