#!/bin/sh

set -e


UTIL_VERSION=8.6.2535.27
UTIL_FILE=imdt_installer-${UTIL_VERSION}.sh
UTIL_URL=http://memorydrv.com/downloads/${UTIL_VERSION}/${UTIL_FILE}
INSTALL_PATH=/usr/local/bin
CONFIG_PATH=/usr/local/etc
LICENSE_FILE=${CONFIG_PATH}/imdt_license.list
UTIL_PATH=${INSTALL_PATH}/${UTIL_FILE}
OPTANE_DEVICES="0x3904 0x3905"
CONFIG_BASE=https://raw.githubusercontent.com/packethost/imdt-installer/master/
LICENSE_MAP=${CONFIG_BASE}/license_map.txt

# check if intel VT extensions exist or not
vmx=$(grep -o -w vmx /proc/cpuinfo || true)
if [ -z "$vmx" ]; then
  echo "Intel VT-x/VT-d extensions are NOT supported on this computer. IMDT will not work."
  exit 1
fi


drives=
numas=
serials=

# get list of drives and associated numas, model numbers, and serial numbers
for i in /sys/module/nvme/drivers/*nvme*/*/nvme/nvm*; do 
  dev=$(basename $i)
  start=${i#/sys/module/nvme/drivers/*nvme*/}
  id=${start%/nvme/*}
  device_id=$(cat /sys/module/nvme/drivers/*nvme*/$id/subsystem_device)
  model=$(cat $i/model)
  serial=$(cat $i/serial)
  # only use nvme devices that are Optanes
  if ! echo ${OPTANE_DEVICES} | grep ${device_id} ; then
    continue
  fi
  numa=$(cat /sys/module/nvme/drivers/*nvme*/$id/numa*)
  drives="$drives $dev:$numa"
  numas="$numas $numa"
  serials="$serials $serial"
done


# get a unique list of numas
numas=$(echo "${numas}" | tr ' ' '\n' | sort -u)

# download the map of licenses
license_map=$(curl -L $LICENSE_MAP)
# must find a license file for at least two of the drives
license_files=
for i in $serials; do
  file=$(echo "$license_map" | awk -F= "/$i/ "'{print $2}')
  license_files="$license_files $file"
done

# now check that we have exactly two total and one unique license file
license_file_count=$(echo $license_files | wc -w)
license_file_unique=$(echo $license_files  | tr ' ' '\n' | sort -u)
expected=2
if [ $license_file_count -ne $expected ]; then
  echo "Found $license_file_count licensed drives instead of expected ${expected}. Exiting." >&2
  exit 1
fi
if [ $license_file_unique -ne 1 ]; then
  echo "Found $license_file_unique license files instead of required 1. Exiting." >&2
  exit 1
fi

# download license file
curl -L ${CONFIG_BASE}/${license_file_unique} > ${LICENSE_FILE}

# some basic requirements
#   bzip2
#   efibootmgr
echo "Installing basic requirements"
if which yum > /dev/null; then
  yum update -y
  yum install -y efibootmgr bzip2
elif which apt > /dev/null; then
  apt update -y
  apt install -y efibootmgr bzip2
else
  echo "Unknown package manager. Exiting"
  exit 1
fi

# download the installer
echo "Downloading IMDT installer"
mkdir -p $INSTALL_PATH $CONFIG_PATH
cd ${INSTALL_PATH}
curl -O -L ${UTIL_URL}
chmod +x ${UTIL_PATH}

echo "Running installer"

${UTIL_PATH} in -n ${LICENSE_FILE}

echo 
echo "Changing BIOS boot order"

# we want the following order:
#  IMDT (either)
#  previous default
#  PXE UEFI IPv4: Intel Network 00 at Riser 02 Slot 01

# save the current boot order
bootstate=$(efibootmgr)
order=$(echo "$bootstate" | awk '/BootOrder/ {print $2}')
current=$(echo "$bootstate" | awk '/BootCurrent/ {print $2}')

# create a new entry for the IMDT
# insert it before the existing ones, but make sure that the current default 
pxe=$(echo "$bootstate" | awk '/UEFI IPv4: Intel Network 00/ {print $1}')
# this needs to be formatted correctly
pxe=${pxe#Boot}
pxe=${pxe%\*}

# now we can add the desired item and set the boot order
# find where it was installed
devs=$(lsblk  -o NAME -r | grep 'nvme.n.p.' | sed 's/n.p.$//g; s/^nvme//g' | sort -u)
for i in $devs; do
  efibootmgr -c -d /dev/nvme${i}n1 -p 1 -L "IMDT ${i}" -l "\efi\boot\bootx64.efi"
done

# get the devices we just added
imdt_entries=$(efibootmgr | awk '/IMDT/ {print $1}' | sed 's/^Boot//g; s/\*//g' | tr ' ' ',')

# change the boot order
# this is unnecessary, since creating the new ones automatically sets them
neworder="${imdt_entries},${order}"

# check if Intel VT-x/VT-d extensions are enabled in BIOS
if [ ! -e /dev/kvm ]; then
  echo "Intel VT-x and VT-d extensions are NOT enabled in BIOS. You must reboot into BIOS, enable them, and then reboot for IMDT to work."
  echo "   - To enable VT-x, the path normally is 'Advanced | Process Configuration | Intel Virtualization Technology'."
  echo "   - To enable VT-d, the path normally is 'Advanced | Integrated IO Configuration | Intel VT for Directed I/O'."
  echo
fi

echo "Installation complete."


