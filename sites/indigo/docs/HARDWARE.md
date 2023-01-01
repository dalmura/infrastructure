# Hardware

In order to bootstrap the Indigo site you will need:
* 6x rpi4.4gb.arm64
* 3x rpi4.8gb.arm64
* 3x dell.r320.amd64

Standard accessories assumed included for all Raspberry Pi's are:
* Raspberry Pi PoE+ Hat
* \>32GB SD Card
* \>128GB SSD Drive w/USB adaptor

Rack accessories include:
* [UCTRONICS 5x rpi4 + SSDs 1U rack (SKU U6264)](https://www.uctronics.com/cluster-and-rack-mount/uctronics-19-1u-raspberry-pi-rackmount-ssd-bracket-for-any-2-5-ssds.html)
* [UCTRONICS SATA to USB 3.0 Adaptor (SKU U6193)](https://www.uctronics.com/uctronics-sata-usb-adapter-cable-sata-hard-drive-disk-converter.html)
* M2.5 x 15mm bolts to thread the POE+ hat => rpi4 board => rack caddy

We are assuming you have separately:
* Upgraded the EEPROM for all Raspberry Pi's to the latest version
* Update the boot order depending on the cluster in question
  * Boot order is [documented here](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#BOOT_ORDER)
* For dal-k8s-mgmt-1 leave the EEPROM boot order to `0xf41`
  * Boot order: SD Card, USB Drive
  * As these nodes have Talos installed directly
* For dal-k8s-core-1 update the EEPROM boot order to `0xf21`
  * Boot order: SD Card, Network (Sidero will then attempt USB as necessary)
  * As these nodes are PXE booted from Sidero

This will form 2x k8s clusters:
| Cluster                          | Role          | Hardware        | Quantity |
|----------------------------------|---------------|-----------------|----------|
| dal-k8s-mgmt-1.indigo.dalmura.au | Control Plane | rpi4.4gb.arm64  |        3 |
| dal-k8s-core-1.indigo.dalmura.au | Control Plane | rpi4.4gb.arm64  |        3 |
| dal-k8s-core-1.indigo.dalmura.au | Workers       | rpi4.8gb.arm64  |        3 |
| dal-k8s-core-1.indigo.dalmura.au | Workers       | dell.r320.amd64 |        3 |
