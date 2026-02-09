The scripts in this directory are wrappers for SAS3FLASH, the final version of which can be found [here](https://docs.broadcom.com/docs/Installer_P16_for_Linux.zip_p).
SAS3FLASH is used to flash firmware to the LSI 93xx-series of HBAs.

The command syntax is `sas3flash -c ${CORE_INDEX} -f ${FIRMWARE}.bin -b ${BIOS}.rom -b ${UEFI}.rom`. Usually, `BIOS=mptsas3` and `UEFI=mpt3x64`. `CORE_INDEX` is a non-negative integer.
If your card has multiple SAS cores, you must run the above command once for each SAS core. The first core always has an index of `0`.

Here are links to the final public firmware releases for some SAS3FLASH-compatible LSI cards:
* 9300-8i: [Firmware](https://docs.broadcom.com/docs/9300_8i_Package_P16_IR_IT_FW_BIOS_for_MSDOS_Windows_Old.zip), [Patch](https://truenas.com/community/resources/lsi-9300-xx-firmware-update.145/download)
* 9305-16i: [Firmware](https://docs.broadcom.com/docs/9305_16i_Pkg_P16.12_IT_FW_BIOS_for_MSDOS_Windows.zip)
Once you download these archives, you will have to poke through their contents and extract a firmware bin, a BIOS ROM, and a UEFI ROM.

If you are using SecureBoot with default keys, you should flash the signed UEFI binary.
If you use your own SecureBoot keys, you likely need to sign the unsigned binary else you may be unable to boot from the HBA.
If you are not booting from the HBA, signed vs unsigned shouldn't matter.

For the sake of clarity:
* The following files were written from scratch by Miles Bradley Huff in 2025:
    * `./9300-8i/flash.sh`
    * `./9305-16i/flash.sh`
* The following files were written from scratch by Miles Bradley Huff in 2026:
    * `./README.md`
    * `./install.sh`
