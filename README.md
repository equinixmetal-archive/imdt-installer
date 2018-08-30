# Packet IMDT Installer
This repository contains utilities for installing and managing IMDT on [AccelerateWithOptane](https://www.acceleratewithoptane.com) lab servers at [Packet](https://packet.net).

As of this writing, the installer works on CentOS 7 and Ubuntu 16.04. The formal help page is available at Packet Help at [this location](https://help.packet.net/solutions/platforms/enabling-optane-drives-as-imdt)


1. Install the Optane enabled server using the normal Packet process, either via the UI or the API
2. Log into the server as root
3. Ensure you have the proper licenses available, and an email address at which to receive the license file.
4. On the host, run `curl https://raw.githubusercontent.com/packethost/imdt-installer/master/imdt-deployer.sh | sh`
5. Follow the instructions to complete the installation

For any problems, open an issue here.

## License Files
The license files are included in this repository under [licenses/](./licenses/). These can be included as they are usable _omnly_ with the particular physical drive and are digitally signed.



