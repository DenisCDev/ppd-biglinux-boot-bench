# ppd-biglinux-boot-bench

**English** · [Português](README.pt-BR.md)

Reproduces, on a GitHub Actions Ubuntu 24.04 runner, what `power-profiles-daemon-biglinux` does across simulated boots on a CPU that power-profiles-daemon has no driver for (`acpi`, `late`), on ones where it has one (`epb`: intel_pstate passive without HWP; `pstate2`: intel_pstate active or amd-pstate-epp).

CPU sysfs is a tmpfs with fake `cpufreq` files and `cpupower` is a stub that logs its calls, so this checks the scripts' decisions, not a real frequency change. A "boot" is: kernel default governor (`schedutil`), `systemctl daemon-reload`, then the boot service.

`variants/base` is upstream `b31d712`; `variants/patched` is the proposed change.
