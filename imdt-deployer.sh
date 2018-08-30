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

drives=
numas=

# get list of drives and associated numas
for i in /sys/module/nvme/drivers/*nvme*/*/nvme/nvm*; do 
  dev=$(basename $i)
  start=${i#/sys/module/nvme/drivers/*nvme*/}
  id=${start%/nvme/*}
  device_id=$(cat /sys/module/nvme/drivers/*nvme*/$id/subsystem_device)
  model=$(cat $i/model)
  serial=$(cat $i/serial)
  # only use nvme devices that are Optanes
  if ! echo ${OPTANE_DEVIES} | grep ${device_id} ; then
    continue
  fi
  numa=$(cat /sys/module/nvme/drivers/*nvme*/$id/numa*)
  drives="$drives $dev:$numa"
  numas="$numas $numa"
done


# get a unique list of numas
numas=$(echo "${numas}" | tr ' ' '\n' | sort -u)

# for now, we just take the last two ignoring duplicates, but that will have to change

# download the installer
mkdir -p $INSTALL_PATH $CONFIG_PATH
cd ${INSTALL_PATH}
curl -O -L ${UTIL_URL}
chmod +x ${UTIL_PATH}

# the below will be automated in the next revision
echo "Will run installer"
echo "When requested, select the correct drives to use. They must meet the following criteria:"
echo "  1) they must be Optanes"
echo "  2) they must not share numas"
echo
echo "The list of nvme drives and associated numas is the following:"
for i in $drives; do
  echo $i | tr ':' ' '
done

${UTIL_PATH} in -n

echo
echo "Now await the license file via provided email."
echo "You CANNOT copy the contents of the file, as it is digitally signed."
echo "You MUST upload the file as is."
echo "We recommend using scp."
echo "The license file should be saved as ${LICENSE_FILE}"

echo "When the license file is uploaded, hit enter to continue"
read wait

${UTIL_PATH} in -n ${LICENSE_FILE}

echo 
echo "Changing BIOS boot order"

# we want the following order:
#  IMDT (either)
#  previous default
#  PXE UEFI IPv4: Intel Network 00 at Riser 02 Slot 01

# some basic requirements
#   bzip2
#   efibootmgr
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


