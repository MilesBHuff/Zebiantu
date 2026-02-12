#!/usr/bin/env bash
#TODO: Enable hibernation

## Right before hibernation happens, we create a new sparse zvol with compression enabled. It always has the same name/path.
## We then format it as a sparse swap partition equal to total RAM. It always has the same UUID.
## We set its priority to the absolute minimum (-1) so that no live data is ever sent there.
## Then we hibernate to it.
##
## initramfs needs to be told to unhibernate from this zvol swap. This must happen immediately after it unlocks the pool(s).
## After the system is fully restored, we delete the zvol.
## We also delete the zvol on normal boots (and log a warning), just in case anything ever goes wrong and a dead zvol swap is ever somehow left behind.

#TODO: Enable automatic hibernation when NUT detects that the UPS is low on battery.
