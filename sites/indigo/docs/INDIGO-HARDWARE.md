# Hardware

In order to bootstrap the Indigo site you will need:
* 3x rpi4.4gb.arm64
* 3x rpi4.8gb.arm64
* 3x dell.r320.amd64

Standard accessories assumed included for all Raspberry Pi's are:
* Raspberry Pi PoE+ Hat
* 128GB USB Flash Drive
* \>128GB SSD Drive w/USB adaptor

Rack accessories include:
* [UCTRONICS 5x rpi4 + SSDs 1U rack (SKU U6264)](https://www.uctronics.com/cluster-and-rack-mount/uctronics-19-1u-raspberry-pi-rackmount-ssd-bracket-for-any-2-5-ssds.html)
* [UCTRONICS SATA to USB 3.0 Adaptor (SKU U6193)](https://www.uctronics.com/uctronics-sata-usb-adapter-cable-sata-hard-drive-disk-converter.html)
* M2.5 x 15mm bolts to thread the POE+ hat => rpi4 board => rack caddy

We are assuming you have separately:
* Upgraded the EEPROM for all Raspberry Pi's to the latest version
* Ensure all Raspberry Pi's boot order is `0xf41`
  * Boot order: SD Card (`1`), USB Drive (`4`), Retry (`f`)
  * Boot order is [documented here](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#BOOT_ORDER)
  * This is because all nodes have Talos manually installed and boot that directly (no PXE/etc)
* Plugged in the 128GB Flash Drive and \>128GB SSD Drive into the blue USB 3.0 ports on the Raspberry Pis
* All drives should be completely wiped and empty

This will form 1x k8s clusters:
| Cluster           | Role          | Hardware        | Quantity |
|-------------------|---------------|-----------------|----------|
| dal-indigo-core-1 | Control Plane | rpi4.4gb.arm64  |        3 |
| dal-indigo-core-1 | Workers       | rpi4.8gb.arm64  |        3 |
| dal-indigo-core-1 | Workers       | dell.r320.amd64 |        3 |
