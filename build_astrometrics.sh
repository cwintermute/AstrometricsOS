#!/bin/bash
# Bash script to do a full install of Astrometrics from
# a clean install of ubuntu-server.
#
# Inspired by AstroArch and AstroBerry located at:
# https://github.com/devDucks/astroarch
# https://github.com/rkaczorek/astroberry-server

# Error out at first signs of trouble
set -e

# Make sure we are running this as root, otherwise exit.
if [ "$EUID" -ne 0 ]
    then echo "Please run as root"
    exit
fi

# Sort out the flags that have been passed
while getopts bdh flag
do
    case "${flag}" in
        b) BLEEDING=True;;
        d) DEBUG=True;;
        h) HELP=${OPTARG}
            printf "Flags:
-b: Download and Compile libgphoto2 and gphoto2 from the latest source.
    Use only if you have a camera that needs bleeding edge support, e.g. EOS R8
    \033[4;31mWarninig:\033[0m I'm not 100%% sure these libraries can be upgraded easily

-d: Do Debug stuff. For testing only.

-h: Display help for this script\n\n";

exit;
        ;;
       *)
        echo "Invalid option: $1" >&2
        exit 1
        ;;

    esac
done

# If we are in debug mode, just dump out data lol
if [ "$DEBUG" = True ]
then

    ETHINT=`lshw -class network -short | grep en | awk '{print $2}'`
    WIFI=`lshw -class network -short | grep wl | awk '{print $2}'`

    echo $ETHINT;
    echo $WIFI;

    exit;
fi

# Determine our architecture for later purposes
ARCH=$(uname -m)
ETH=`lshw -class network -short 2>&1 | grep en | awk '{print $2}'`
WIFI=`lshw -class network -short 2>&1 | grep wl | awk '{print $2}'`

#echo $ETH;
#echo $WIFI;


# Add the PPA repository for the INDI software
printf "Adding 3rd party repositories\n"
add-apt-repository ppa:mutlaqja/ppa -y

# Add the PPA repository for the PHD2 software
add-apt-repository ppa:pch/phd2 -y

# Update the app database
apt-get update

# Install the initial set of utilities needed
apt-get install git libtool autotools-dev gettext autopoint pkg-config autoconf automake build-essential -y

# Enable .local name resolution for this host
# I needed both of these in my testing to get Windows to play nice
printf "Enabling .local lookupg for this host\n"
sed -i 's/#LLMNR=no/LLMNR=yes/g' /etc/systemd/resolved.conf
sed -i 's/#MulticastDNS=no/MulticastDNS=yes/g' /etc/systemd/resolved.conf
systemctl restart systemd-resolved.service

# Create the user 'seven' for the desktop interface
# Give the user sudo permission for software installation.
useradd -G sudo -m seven
echo 'seven:space' | chpasswd

# Add the user to appropriate groups
usermod -aG uucp,sys,audio,input,lp,video,users seven

# Allow members of the sudo group to run all apps with no password.
#sed -i 's/%sudo[[:space:]]ALL=(ALL:ALL) ALL/%sudo   ALL=(ALL:ALL) NOPASSWD: ALL\n\nTEST/g' ~/sudoers

# Allow members of the sudo group to manage packages
echo -e "# Allow members of the sudo group to add packages without password.\n%sudo   ALL=NOPASSWD:/bin/apt,/bin/apt-get" >> /etc/sudoers.d/allow_apt
# Fix permissions on the file
chown root:root /etc/sudoers.d/allow_apt
chmod 440 /etc/sudoers.d/allow_apt


# Pull down the scripts, configs and such for building the OS
su seven -c "git clone https://github.com/cwintermute/astrometrics.git /home/seven/.astrometrics"

# Install the XFCE4 for GUI
printf "Installing XFCE\n"
apt install xubuntu-core -y

# Setup auto login
cp /home/seven/.astrometrics/configs/12-autologin.conf /etc/lightdm/lightdm.conf.d/

# Enable the gui at startup
systemctl set-default graphical.target

# Install Samba
printf "Installing Samba\n"
apt-get install samba -y

# Copy the config over for Samba
printf "Copying the samba config\n"
rm /etc/samba/smb.conf ; cp /home/seven/.astrometrics/configs/smb.conf /etc/samba/

# Change the SMB password for seven
(echo space; echo space) | smbpasswd -s -a seven

# Restart samba so we can access the server
systemctl restart smb

I915=`lsmod | grep i915 | head -n 1 | awk '{print $1}'`
echo $I915

if [ ! -z "$I915" ]
    then echo "Found an intel video driver, copying config"
    cp /home/seven/.astrometrics/configs/99-intel-acceleration.conf /etc/X11/xorg.conf.d/
fi

# Install libgphoto2 and gphoto2 either from src or package
if [ ! -z "$BLEEDING" ]; then
    # Install the needed packages for compiling libgphoto2
    printf "Installing libgphoto2 and gphoto2 from source. Ahead be dragons."
    apt-get install libjpeg-dev libxml2-dev libcurl4-gnutls-dev libgd-dev libexif-dev libusb-dev libpopt-dev -y
    mkdir /root/src/
    git clone https://github.com/gphoto/libgphoto2.git /root/src/libgphoto2
    cd /root/src/libgphoto2/
    autoreconf --install --symlink
    ./configure --prefix=/usr/local
    read -p "Hopefully this looks right. Press any key to continue" -n1 -s
    make
    make install
    
    git clone https://github.com/gphoto/gphoto2.git /root/src/gphoto2
    cd /root/src/gphoto2/
    autoreconf --install --symlink
    ./configure --prefix=/usr/local
    read -p "Hopefully this looks right. Press any key to continue" -n1 -s
    make
    make install

    printf "Installing needed libs and packages for INDI compilation\n"
    apt-get install libfftw3-dev libev-dev cdbs cmake git libcfitsio-dev \
        libnova-dev libusb-1.0-0-dev libjpeg-dev libusb-dev libftdi-dev fxload \
        libkrb5-dev libcurl4-gnutls-dev libraw-dev libgsl0-dev dkms libboost-regex-dev \
        libgps-dev libxisf-dev libtheora0 librtlsdr-dev libgtest-dev libgmock-dev -y #libgphoto2-dev
   #apt-get install libgphoto2-6t64 libgphoto2-l10n libgphoto2-port12 libgphoto2-port12t64

    printf "Compiling INDI\n"
    git clone https://github.com/indilib/indi.git /root/src/indi
    cd /root/src/indi/
    mkdir -p build/indi
    cd build/indi
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Debug /root/src/indi
    make install

else
    printf "Installing libgphoto2 and gphoto2 from package\n"
    apt-get install libgphoto2-6 gphoto2

    printd "Installing the rest of libgphoto2 and gphoto2\n"
    apt-get install libgphoto2-6 libgphoto2-6t64 libgphoto2-l10n libgphoto2-port12 libgphoto2-port12t64

    printf "Installing INDI full server package"
    apt-get install indi-full -y
fi

printf "Setup Virtual Environment for indi-web\n"
mkdir -p /root/indi-web
cd /root/indi-web
apt-get install python3.12-venv -y
python3 -m venv venv
source venv/bin/activate
pip3 install indiweb importlib-metadata
cp /home/seven/.astrometrics/systemd/indi-web.service /etc/systemd/system/
# Different install paths have different locations unfortunately
if [ ! -z "$BLEEDING" ]; then
    cp /home/seven/.astrometrics/defaults/indi-web.bleeding /etc/default/indi-web
else
    cp /home/seven/.astrometrics/defaults/indi-web.package /etc/default/indi-web
fi
systemctl daemon-reload
systemctl enable indi-web

printf "Installing PHD2\n"
apt-get install build-essential subversion cmake pkg-config libwxgtk3.2-dev wx-common \
    wx3.2-i18n libindi-dev libnova-dev zlib1g-dev libeigen3-dev libogmacam -y

apt-get install phd2 -y

cd /root
wget "https://www.astrodmx-capture.org.uk/downloads/astrodmx/current/linux-x86_64/astrodmx-capture_2.10.1_amd64.deb"
dpkg --install astrodmx-capture_2.10.1_amd64.deb

printf "Copying Desktop icons\n"
su -c "mkdir ~/Desktop/" seven
cp /home/seven/.astrometrics/desktop/* /home/seven/Desktop/
chmod +x /home/seven/Desktop/*.desktop
chown seven:seven /home/seven/Desktop/*.desktop

sudo -u seven -g seven /home/seven/.astrometrics/scripts/fix_desktop_icons.sh

apt-get install gpsd-clients -y
apt-get install firefox -y

print "Script finished install base system.\n"
exit;

echo $LIBG
echo $ARCH