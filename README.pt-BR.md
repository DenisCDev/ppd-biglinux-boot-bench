# ppd-biglinux-boot-bench

[English](README.md) · **Português**

Reproduz, num runner Ubuntu 24.04 do GitHub Actions, o que o `power-profiles-daemon-biglinux` faz em inicializações simuladas numa CPU para a qual o power-profiles-daemon não tem driver (`acpi`, `late`) e em CPUs para as quais tem (`epb`: intel_pstate passivo sem HWP; `pstate2`: intel_pstate ativo ou amd-pstate-epp).

O sysfs da CPU é um tmpfs com arquivos `cpufreq` falsos, e o `cpupower` é um substituto que registra as chamadas. Por isso, o teste confere as decisões dos scripts, não uma mudança real de frequência. Uma "inicialização" é: governor padrão do kernel (`schedutil`), `systemctl daemon-reload` e, depois, o serviço de inicialização.

`variants/base` é o `b31d712` do projeto original; `variants/patched` é a mudança proposta.
