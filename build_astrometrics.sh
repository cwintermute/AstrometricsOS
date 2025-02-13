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
then
    echo "Please run as root"
    exit
fi

printf "Logging stdout to /tmp/astrometrics.log\n"
printf "Starting Build Process at `date`\n" | tee -a /tmp/astrometrics.log

# Pre-define variables used in switches
J=1
DEBUG=false
BLEEDING=false

# Sort out the flags that have been passed
while getopts "a:bdhj:" flag
do
    case "${flag}" in
        a) ADMXVER=${OPTARG};;
        b) BLEEDING=true;;
        d) DEBUG=true;;
        h) HELP=${OPTARG}
            printf "Flags:
-b: Download and Compile libgphoto2 and gphoto2 from the latest source.
    Use only if you have a camera that needs bleeding edge support, e.g. EOS R8
    \033[4;31mWarninig:\033[0m I'm not 100%% sure these libraries can be upgraded easily

-d: Do Debug stuff. For testing only.

-h: Display help for this script\n\n";

exit;
        ;;
        j) 
            J=${OPTARG}
            CMAKE_BUILD_PARALLEL_LEVEL=$J
        ;;
        *)
            echo "Invalid option: $1" >&2
            exit 1
        ;;

    esac
done

printf "Script will use -j"$J" for any compilation\n" | tee -a /tmp/astrometrics.log


# If we are in debug mode, just dump out data lol
if [ "$DEBUG" = true ] 
then

    ETHINT=`lshw -class network -short | grep en | awk '{print $2}'`
    WIFI=`lshw -class network -short | grep wl | awk '{print $2}'`

    echo $ETHINT;
    echo $WIFI;

    exit;
fi

# Determine our architecture for later purposes
ARCH=$(uname -m)
printf "Detected architecture: "$ARCH"\n" | tee -a /tmp/astrometrics.log
# Should match either eth0 or enpXsY style names
#WIFI=`lshw -class network -short 2>&1 | grep "wl\|wifi" | awk '{print $2}'`

#echo $ETH;
#echo $WIFI;

export DEBIAN_FRONTEND=noninteractive


# Add the PPA repository for the INDI software
printf "Adding 3rd party repositories\n"
add-apt-repository ppa:mutlaqja/ppa -y >> /tmp/astrometrics.log

# Add the PPA repository for the PHD2 software
add-apt-repository ppa:pch/phd2 -y >> /tmp/astrometrics.log

# Update the app database
apt-get update >> /tmp/astrometrics.log

# Install the initial set of utilities needed
apt-get install lshw git apt-utils libtool autotools-dev gettext autopoint pkg-config autoconf automake build-essential -y >> /tmp/astrometrics.log

# Enable .local name resolution for this host
# I needed both of these in my testing to get Windows to play nice
printf "Enabling .local lookupg for this host\n" | tee -a /tmp/astrometrics.log
sed -i 's/#LLMNR=no/LLMNR=yes/g' /etc/systemd/resolved.conf
sed -i 's/#MulticastDNS=no/MulticastDNS=yes/g' /etc/systemd/resolved.conf
systemctl restart systemd-resolved.service >> /tmp/astrometrics.log

# Create the user 'seven' for the desktop interface
# Give the user sudo permission for software installation.
useradd -G sudo -s /bin/bash -m seven
echo 'seven:space' | chpasswd

# Add the user to appropriate groups
usermod -aG uucp,sys,audio,input,lp,video,users,dialout seven >> /tmp/astrometrics.log

# Allow members of the sudo group to run all apps with no password.
#sed -i 's/%sudo[[:space:]]ALL=(ALL:ALL) ALL/%sudo   ALL=(ALL:ALL) NOPASSWD: ALL\n\nTEST/g' ~/sudoers

# Allow members of the sudo group to manage packages
echo -e "# Allow members of the sudo group to add packages without password.\n%sudo   ALL=NOPASSWD:/bin/apt,/bin/apt-get" >> /etc/sudoers.d/allow_apt
# Fix permissions on the file
chown root:root /etc/sudoers.d/allow_apt
chmod 440 /etc/sudoers.d/allow_apt


# Pull down the scripts, configs and such for building the OS
su seven -c "git clone https://github.com/cwintermute/AstrometricsOS.git /home/seven/.astrometrics" >> /tmp/astrometrics.log

# Install the XFCE4 for GUI
printf "Installing XFCE\n" | tee -a /tmp/astrometrics.log
apt-get install xubuntu-core -y >> /tmp/astrometrics.log

# Setup auto login
cp /home/seven/.astrometrics/configs/12-autologin.conf /etc/lightdm/lightdm.conf.d/

# Enable the gui at startup
systemctl set-default graphical.target >> /tmp/astrometrics.log

# Install Samba
printf "Installing Samba\n" | tee -a /tmp/astrometrics.log
apt-get install samba -y >> /tmp/astrometrics.log

# Copy the config over for Samba
printf "Copying the samba config\n" | tee -a /tmp/astrometrics.log
rm /etc/samba/smb.conf ; cp /home/seven/.astrometrics/configs/smb.conf /etc/samba/

# Change the SMB password for seven
(echo space; echo space) | smbpasswd -s -a seven

# Restart samba so we can access the server
systemctl restart smb >> /tmp/astrometrics.log

I915=`lsmod | grep i915 | head -n 1 | awk '{print $1}'`
echo $I915

if [ ! -z "$I915" ] 
then 
    echo "Found an intel video driver, copying config" | tee -a /tmp/astrometrics.log
    cp /home/seven/.astrometrics/configs/99-intel-acceleration.conf /etc/X11/xorg.conf.d/
fi

if [ $ARCH = "aarch64" ]
then
    echo "Found a potential RPi, copying disable v3d config" | tee -a /tmp/astrometrics.log
    cp /home/seven/.astrometrics/configs/99-v3d.conf /etc/X11/xorg.conf.d/
fi

# Install libgphoto2 and gphoto2 either from src or package
if [ "$BLEEDING" = true ]; 
then
    # Install the needed packages for compiling libgphoto2
    printf "Installing libgphoto2 and gphoto2 from source. Ahead be dragons.\n" | tee -a /tmp/astrometrics.log
    apt-get install libjpeg-dev libxml2-dev libcurl4-gnutls-dev libgd-dev libexif-dev libusb-dev libpopt-dev -y >> /tmp/astrometrics.log
    mkdir /root/src/
    git clone https://github.com/gphoto/libgphoto2.git /root/src/libgphoto2 >> /tmp/astrometrics.log
    cd /root/src/libgphoto2/
    autoreconf --install --symlink >> /tmp/astrometrics.log
    ./configure --prefix=/usr/local 
    read -p "Hopefully this looks right. Press any key to continue" -n1 -s
    make -j $J
    make install >> /tmp/astrometrics.log
    
    git clone https://github.com/gphoto/gphoto2.git /root/src/gphoto2
    cd /root/src/gphoto2/
    autoreconf --install --symlink >> /tmp/astrometrics.log
    ./configure --prefix=/usr/local
    read -p "Hopefully this looks right. Press any key to continue" -n1 -s
    make -j $J
    make install >> /tmp/astrometrics.log

    printf "Installing needed libs and packages for INDI compilation\n" | tee -a /tmp/astrometrics.log
    apt-get install libfftw3-dev libev-dev cdbs cmake git libcfitsio-dev \
        libnova-dev libusb-1.0-0-dev libjpeg-dev libusb-dev libftdi-dev fxload \
        libkrb5-dev libcurl4-gnutls-dev libraw-dev libgsl0-dev dkms libboost-regex-dev \
        libgps-dev libxisf-dev libtheora0 librtlsdr-dev libgtest-dev libgmock-dev -y >> /tmp/astrometrics.log #libgphoto2-dev
   #apt-get install libgphoto2-6t64 libgphoto2-l10n libgphoto2-port12 libgphoto2-port12t64

    printf "Compiling INDI\n" | tee -a /tmp/astrometrics.log
    git clone https://github.com/indilib/indi.git /root/src/indi >> /tmp/astrometrics.log
    cd /root/src/indi/
    mkdir -p build/indi
    cd build/indi
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Debug  /root/src/indi >> /tmp/astrometrics.log
    make install >> /tmp/astrometrics.log

    printf "Compiling INDI 3rd party\n" | tee -a /tmp/astrometrics.log
    apt-get install libnova-dev libcfitsio-dev libusb-1.0-0-dev zlib1g-dev libgsl-dev build-essential cmake git libjpeg-dev libcurl4-gnutls-dev libtiff-dev libftdi-dev libgps-dev libraw-dev libdc1394-dev libgphoto2-dev libboost-dev libboost-regex-dev librtlsdr-dev liblimesuite-dev libftdi1-dev libgps-dev libavcodec-dev libavdevice-dev libzmq3-dev -y
    git clone --depth=1 https://github.com/indilib/indi-3rdparty /root/src/indi-3rdparty >> /tmp/astrometrics.log
    cd /root/src/indi-3rdparty
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Debug -DBUILD_LIBS=1 /root/src/indi-3rdparty >> /tmp/astrometrics.log
    make -j $J
    make install >> /tmp/astrometrics.log
    make clean
    cd /root/src/indi-3rdparty
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Debug  /root/src/indi-3rdparty >> /tmp/astrometrics.log
    make -j $J
    make install >> /tmp/astrometrics.log
    make clean
    cd /root/src/indi-3rdparty/indi-eqmod
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Debug  /root/src/indi-3rdparty/indi-eqmod >> /tmp/astrometrics.log
    make -j $J
    make install >> /tmp/astrometrics.log
    make clean
    cd /root/src/indi-3rdparty/indi-gphoto
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Debug  /root/src/indi-3rdparty/indi-gphoto >> /tmp/astrometrics.log
    make -j $J
    make install >> /tmp/astrometrics.log
    make clean
    cd /root/src/indi-3rdparty/indi-gpsd
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Debug  /root/src/indi-3rdparty/indi-gpsd >> /tmp/astrometrics.log
    make -j $J
    make install >> /tmp/astrometrics.log
    make clean
else
    printf "Installing libgphoto2 and gphoto2 from package\n" | tee -a /tmp/astrometrics.log
    apt-get install libgphoto2-6 gphoto2 -y >> /tmp/astrometrics.log

    printf "Installing the rest of libgphoto2 and gphoto2\n" | tee -a /tmp/astrometrics.log
    apt-get install libgphoto2-6 libgphoto2-6t64 libgphoto2-l10n libgphoto2-port12 libgphoto2-port12t64 -y >> /tmp/astrometrics.log

    printf "Installing INDI full server package\n" | tee -a /tmp/astrometrics.log
    apt-get install indi-full -y >> /tmp/astrometrics.log
fi

printf "Setup Virtual Environment for indi-web\n" | tee -a /tmp/astrometrics.log
apt-get install python3.12-venv -y >> /tmp/astrometrics.log
su -c "/bin/bash /home/seven/.astrometrics/scripts/setup_venv.sh" seven >> /tmp/astrometrics.log

cp /home/seven/.astrometrics/systemd/indi-web.service /etc/systemd/system/
# Different install paths have different locations unfortunately
if [ "$BLEEDING" = true ]; 
then
    cp /home/seven/.astrometrics/defaults/indi-web.bleeding /etc/default/indi-web
else
    cp /home/seven/.astrometrics/defaults/indi-web.package /etc/default/indi-web
fi
systemctl daemon-reload >> /tmp/astrometrics.log
systemctl enable indi-web >> /tmp/astrometrics.log

printf "Installing PHD2\n" | tee -a /tmp/astrometrics.log
apt-get install build-essential subversion cmake pkg-config libwxgtk3.2-dev wx-common \
    wx3.2-i18n libindi-dev libnova-dev zlib1g-dev libeigen3-dev libogmacam -y >> /tmp/astrometrics.log

apt-get install phd2 -y >> /tmp/astrometrics.log

printf "Downloading and Installing AstroDMX\n" | tee -a /tmp/astrometrics.log
cd /root
if [ $ARCH = "x86_64" ] 
then
    wget "https://www.astrodmx-capture.org.uk/downloads/astrodmx/current/linux-x86_64/astrodmx-capture_${ADMXVER}_amd64.deb" -O astrodmx.deb >> /tmp/astrometrics.log
elif [ $ARCH = "aarch64" ]
then
    wget "https://www.astrodmx-capture.org.uk/downloads/astrodmx/current/linux-arm/astrodmx-glibc-2.28_${ADMXVER}_arm64.deb" -O astrodmx.deb >> /tmp/astrometrics.log
fi
dpkg --install astrodmx.deb >> /tmp/astrometrics.log    
printf "Copying Desktop icons\n" | tee -a /tmp/astrometrics.log
su -c "mkdir ~/Desktop/" seven
cp /home/seven/.astrometrics/desktop/* /home/seven/Desktop/
chmod +x /home/seven/Desktop/*.desktop
chown seven:seven /home/seven/Desktop/*.desktop

printf "Disabling screen blanking and power management\n" | tee -a /tmp/astrometrics.log
su -c "mkdir -p /home/seven/.config/xfce4/xfconf/xfce-perchannel-xml/" seven
cp /home/seven/.astrometrics/configs/xfce4-power-manager.xml  /home/seven/.config/xfce4/xfconf/xfce-perchannel-xml/
cp /home/seven/.astrometrics/configs/xfce4-screensaver.xml  /home/seven/.config/xfce4/xfconf/xfce-perchannel-xml/
cp /home/seven/.astrometrics/configs/xfce4-desktop.xml  /home/seven/.config/xfce4/xfconf/xfce-perchannel-xml/

apt-get install gpsd-clients -y >> /tmp/astrometrics.log
apt-get install firefox -y >> /tmp/astrometrics.log

printf "Installing KStars\n" | tee -a /tmp/astrometrics.log
if [ "$BLEEDING" = true ];
then
    apt-get install kstars-bleeding -y >> /tmp/astrometrics.log
else
    apt-get install kstars -y >> /tmp/astrometrics.log
fi

printf "Installing and configuring VNC Server\n"
apt-get install tigervnc-scraping-server -y

cp /home/seven/.astrometrics/systemd/x0vncserver.service /etc/systemd/system/
systemctl daemon-reload >> /tmp/astrometrics.log
systemctl enable x0vncserver.service >> /tmp/astrometrics.log

# Tell bash to run the icon fixer once upon login
su -c "mkdir -p /home/seven/.config/autostart/" seven
su -c "cp /home/seven/.astrometrics/autostart/fix_icons.desktop /home/seven/.config/autostart/" seven
chmod +x /home/seven/.astrometrics/scripts/fix_desktop_icons.sh
f=/home/seven/.config/autostart/fix_icons.desktop
su -c "chmod +x $f; dbus-launch gio set -t string $f metadata::xfce-exe-checksum \"$(sha256sum $f | awk '{print $1}')\"" seven

# Netplan time
cp /home/seven/.astrometrics/configs/90-*.yaml /etc/netplan/
# Fixes permissions to prevent a bunch of warnings
chmod 600 /etc/netplan/90-*.yaml 
ETH=`lshw -class network -short 2>&1 | grep "en\|eth" | awk '{print $2}'`
sed -i "s/ETHERNET/$ETH/g" /etc/netplan/90-ethernet.yaml
#sed -i "s/WIFI/$WIFI/g" /etc/netplan/90-wifi.yaml
sed -i "s/SSID/Astrometrics-`tr -dc A-Za-z0-9 </dev/urandom | head -c 4`/g" /etc/netplan/90-wifi.yaml
# Fix systemd-networkd from doubling up the DHCP
sed -i "s/\[Network\]/\[Network\]\nDHCP=no/g" /etc/systemd/networkd.conf
rm /etc/netplan/50-*.yaml
netplan generate
#netplan apply


# NoVNC and  NGINX stuff
apt-get -y install novnc python3-websockify nginx >> /tmp/astrometrics.log
cp /home/seven/.astrometrics/systemd/novnc.service /etc/systemd/system/
systemctl daemon-reload >> /tmp/astrometrics.log
systemctl enable novnc.service >> /tmp/astrometrics.log
cp /home/seven/.astrometrics/configs/astrometrics.local.conf /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/astrometrics.local.conf /etc/nginx/sites-enabled/
systemctl enable nginx

apt-get clean >> /tmp/astrometrics.log

printf "Script finished install base system.\n" | tee -a /tmp/astrometrics.log
exit;

echo $LIBG
echo $ARCH
