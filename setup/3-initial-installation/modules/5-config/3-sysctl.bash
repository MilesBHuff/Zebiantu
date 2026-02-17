#!/usr/bin/env bash
#NOTE: This script is a fragment sourced by a parent script running in a `chroot`.
echo ':: Configuring sysctl...'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/61-io-static.conf
idempotent_append 'vm.legacy_va_layout=0'            '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'kernel.io_delay_type=2'           '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.compact_unevictable_allowed=0' '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.watermark_scale_factor=125'    '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.watermark_boost_factor=2500'      '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.oom_kill_allocating_task=0'    '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.overcommit_memory=0'           '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.overcommit_ratio=80'           '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.memory_failure_recovery=1'     '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.memory_failure_early_kill=1'   '/etc/sysctl.d/961-io-static.conf'
idempotent_append 'vm.laptop_mode=0'                 '/etc/sysctl.d/961-io-static.conf'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/62-io-tweakable.conf
idempotent_append 'vm.zone_reclaim_mode=0'          '/etc/sysctl.d/62-io-tweakable.conf'
#NOTE: `vm.swappiness` was set in the "S W A P" section of this file.
idempotent_append 'vm.vfs_cache_pressure=50'        '/etc/sysctl.d/62-io-tweakable.conf'
idempotent_append 'vm.vfs_cache_pressure_denom=100' '/etc/sysctl.d/62-io-tweakable.conf'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/68-debug.conf
idempotent_append 'net.ipv4.icmp_errors_use_inbound_ifaddr=1'    '/etc/sysctl.d/968-debug.conf'
idempotent_append 'net.ipv4.icmp_ignore_bogus_error_responses=1' '/etc/sysctl.d/968-debug.conf'
idempotent_append 'net.ipv4.conf.all.log_martians=1'             '/etc/sysctl.d/968-debug.conf'
idempotent_append 'vm.block_dump=0'                              '/etc/sysctl.d/968-debug.conf'
idempotent_append 'vm.oom_dump_tasks=0'                          '/etc/sysctl.d/968-debug.conf'
idempotent_append 'vm.stat_interval=1'                           '/etc/sysctl.d/968-debug.conf'
idempotent_append 'vm.panic_on_oom=0'                            '/etc/sysctl.d/968-debug.conf'
idempotent_append 'kernel.printk = 3 5 2 3'                      '/etc/sysctl.d/968-debug.conf'
idempotent_append 'vm.mem_profiling=0'                           '/etc/sysctl.d/968-debug.conf'
### See the following for explanations: https://github.com/MilesBHuff/Dotfiles/blob/master/Linux/etc/sysctl.d/69-security.conf
idempotent_append 'kernel.dmesg_restrict=1'    '/etc/sysctl.d/969-security.conf'
idempotent_append 'kernel.kptr_restrict=1'     '/etc/sysctl.d/969-security.conf'
idempotent_append 'kernel.yama.ptrace_scope=1' '/etc/sysctl.d/969-security.conf'
idempotent_append 'vm.mmap_min_addr=65536'     '/etc/sysctl.d/969-security.conf'
idempotent_append 'fs.protected_fifos = 1'     '/etc/sysctl.d/969-security.conf'
idempotent_append 'fs.protected_hardlinks = 1' '/etc/sysctl.d/969-security.conf'
idempotent_append 'fs.protected_regular = 2'   '/etc/sysctl.d/969-security.conf'
idempotent_append 'fs.protected_symlinks = 1'  '/etc/sysctl.d/969-security.conf'
sysctl --system
