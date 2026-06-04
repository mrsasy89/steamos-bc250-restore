/*
 * SSDT-PST.dsl — Custom P-States for AMD BC-250 / Cyan Skillfish
 *
 * Tested on: SteamOS 3.9.0, kernel linux-neptune-618 (6.18.33-valve1)
 *
 * Compile with:
 *   iasl SSDT-PST.dsl  →  SSDT-PST.aml
 *
 * Install to: /etc/initcpio/acpi_override/SSDT-PST.aml
 * Add hook:   HOOKS=(acpi_override ...) in /etc/mkinitcpio.conf.d/20-steamdeck.conf
 * Rebuild:    sudo mkinitcpio -p linux-neptune-618
 *
 * Verification:
 *   cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
 *   dmesg | grep "Table Upgrade"
 */

DefinitionBlock ("SSDT-PST.aml", "SSDT", 2, "HACK", "PSTATES", 0x00000001)
{
    External (_PR_.CPU0, ProcessorObj)
    External (_PR_.CPU1, ProcessorObj)
    External (_PR_.CPU2, ProcessorObj)
    External (_PR_.CPU3, ProcessorObj)
    External (_PR_.CPU4, ProcessorObj)
    External (_PR_.CPU5, ProcessorObj)
    External (_PR_.CPU6, ProcessorObj)
    External (_PR_.CPU7, ProcessorObj)
    External (_PR_.CPU8, ProcessorObj)
    External (_PR_.CPU9, ProcessorObj)
    External (_PR_.CPUA, ProcessorObj)
    External (_PR_.CPUB, ProcessorObj)

    /*
     * P-State package format (ACPI spec):
     *   CoreFreq (MHz), Power (mW), TransLatency (us), BusMasterLatency (us),
     *   Control (MSR value), Status (MSR value)
     *
     * BC-250 / Cyan Skillfish — 8 P-States
     * Frequencies derived from hardware testing and SMU readouts.
     */
    Name (PSDF, Package ()
    {
        // P0 — Maximum performance
        Package () { 3200, 0, 10, 10, 0x00, 0x00 },
        // P1
        Package () { 2550, 0, 10, 10, 0x01, 0x01 },
        // P2
        Package () { 2325, 0, 10, 10, 0x02, 0x02 },
        // P3
        Package () { 1960, 0, 10, 10, 0x03, 0x03 },
        // P4
        Package () { 1820, 0, 10, 10, 0x04, 0x04 },
        // P5
        Package () { 1600, 0, 10, 10, 0x05, 0x05 },
        // P6
        Package () { 1271, 0, 10, 10, 0x06, 0x06 },
        // P7 — Minimum performance
        Package () { 800,  0, 10, 10, 0x07, 0x07 }
    })

    /* Inject _PSS (P-State Support) into each CPU object */
    Scope (_PR_.CPU0) { Method (_PSS, 0) { Return (PSDF) } }
    Scope (_PR_.CPU1) { Method (_PSS, 0) { Return (PSDF) } }
    Scope (_PR_.CPU2) { Method (_PSS, 0) { Return (PSDF) } }
    Scope (_PR_.CPU3) { Method (_PSS, 0) { Return (PSDF) } }
    Scope (_PR_.CPU4) { Method (_PSS, 0) { Return (PSDF) } }
    Scope (_PR_.CPU5) { Method (_PSS, 0) { Return (PSDF) } }
    Scope (_PR_.CPU6) { Method (_PSS, 0) { Return (PSDF) } }
    Scope (_PR_.CPU7) { Method (_PSS, 0) { Return (PSDF) } }
    Scope (_PR_.CPU8) { Method (_PSS, 0) { Return (PSDF) } }
    Scope (_PR_.CPU9) { Method (_PSS, 0) { Return (PSDF) } }
    Scope (_PR_.CPUA) { Method (_PSS, 0) { Return (PSDF) } }
    Scope (_PR_.CPUB) { Method (_PSS, 0) { Return (PSDF) } }
}
