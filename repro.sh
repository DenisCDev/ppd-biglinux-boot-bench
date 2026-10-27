#!/bin/bash
# Reproduce what power-profiles-daemon-biglinux does across boots on a CPU
# with no frequency driver power-profiles-daemon understands.
# Usage: sudo ./repro.sh VARIANT_DIR CPU_KIND(acpi|epb) OUT_CSV
set -u
variant=$1 cpu=$2 out=$3
cpudir=/sys/devices/system/cpu
gov=$cpudir/cpu0/cpufreq/scaling_governor
log=/run/cpupower.log

DEBIAN_FRONTEND=noninteractive apt-get install -y -qq power-profiles-daemon >/dev/null
dpkg-query -W power-profiles-daemon
ppd_bin=$(command -v power-profiles-daemon || ls /usr/libexec/power-profiles-daemon)
[ -e /usr/lib/power-profiles-daemon ] || ln -s "$ppd_bin" /usr/lib/power-profiles-daemon
systemctl mask --now power-profiles-daemon.service

# Fake CPU sysfs.
#   acpi:    acpi-cpufreq style governors, no knob power-profiles-daemon knows
#   epb:     same governors plus the Intel EPB knob (intel_pstate passive
#            without HWP), so power-profiles-daemon has a real CPU driver
#   pstate2: only performance/powersave plus EPB (intel_pstate active,
#            amd-pstate-epp), where the daemon owns the CPU and no governor
#            change is expected
#   late:    acpi, but cpufreq appears 12 s after the boot service starts
governors="conservative ondemand userspace powersave performance schedutil"
default_gov=schedutil
[ "$cpu" = pstate2 ] && governors="performance powersave" default_gov=powersave
mount -t tmpfs tmpfs $cpudir
make_cpufreq() {
    mkdir -p $cpudir/cpu0/cpufreq
    echo "$governors" > $cpudir/cpu0/cpufreq/scaling_available_governors
    echo $default_gov > $gov
}
make_cpufreq
if [ "$cpu" = epb ] || [ "$cpu" = pstate2 ]; then
    mkdir -p $cpudir/cpu0/power
    echo 6 > $cpudir/cpu0/power/energy_perf_bias
fi

cat > /usr/local/bin/cpupower <<EOF
#!/bin/bash
echo "\$*" >> $log
[ "\$1 \$2" = "frequency-set -g" ] && [ -n "\$3" ] && echo "\$3" > $gov
EOF
printf '#!/bin/sh\necho "Adapter 0: on-line"\n' > /usr/local/bin/acpi
chmod +x /usr/local/bin/cpupower /usr/local/bin/acpi
: > $log

install -m755 "$variant"/power-profiles-daemon-biglinux "$variant"/power-profiles-daemon-biglinux-cpufreq /usr/bin/
install -m644 "$variant"/*.service "$variant"/*.path /usr/lib/systemd/system/
systemctl daemon-reload
systemctl enable power-profiles-daemon-biglinux.service power-profiles-daemon-biglinux-cpufreq.path

echo "step,fake_env_running,profiles,active,governor,state_ini_mtime,cpupower_calls,boot_service_result" > "$out"
record() {
    local env profiles active mtime
    env=$(systemctl show -p Environment --value power-profiles-daemon-biglinux-start | grep -c FAKE_DRIVER)
    profiles=$(powerprofilesctl list 2>/dev/null | grep -cE '^[ *] [a-z-]+:$')
    active=$(powerprofilesctl get 2>/dev/null)
    mtime=$(stat -c %Y /var/lib/power-profiles-daemon/state.ini 2>/dev/null || echo none)
    echo "$1,$env,$profiles,$active,$(cat $gov),$mtime,$(wc -l < $log),$(systemctl show -p Result --value power-profiles-daemon-biglinux.service)" | tee -a "$out"
}

# A boot: the kernel starts with its default governor and systemd reads the
# unit files from disk, then the boot service runs.
boot() {
    systemctl stop power-profiles-daemon-biglinux.service power-profiles-daemon-biglinux-start.service power-profiles-daemon-biglinux-cpufreq.path
    if [ "$cpu" = late ]; then
        rm -rf $cpudir/cpu0/cpufreq
        (sleep 12; make_cpufreq) &
    else
        echo $default_gov > $gov
    fi
    systemctl daemon-reload
    systemctl start power-profiles-daemon-biglinux-cpufreq.path
    systemctl start power-profiles-daemon-biglinux.service
    for _ in $(seq 60); do
        [ "$(systemctl show -p SubState --value power-profiles-daemon-biglinux.service)" = exited ] && [ -e $gov ] && break
        sleep 1
    done
    wait
    sleep 3
    record "$1"
}

set_profile() {
    powerprofilesctl set "$1" || echo "set $1 failed"
    sleep 3
    record "$2"
}

boot boot1
set_profile performance set-performance
boot boot2
boot boot3
boot boot4
set_profile power-saver set-power-saver
boot boot5
boot boot6

echo "--- cpupower calls"; cat $log
echo "--- state.ini"; cat /var/lib/power-profiles-daemon/state.ini 2>/dev/null
echo "--- boot service journal"; journalctl -b -u power-profiles-daemon-biglinux.service --no-pager | tail -40
umount $cpudir
