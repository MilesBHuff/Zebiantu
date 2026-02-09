#!/bin/sh
./sas3flash -c 0 -f SAS9305_16i_IT_P.bin -b mptsas3.rom -b mpt3x64.rom
./sas3flash -c 1 -f SAS9305_16i_IT_P.bin -b mptsas3.rom -b mpt3x64.rom
exit $?
