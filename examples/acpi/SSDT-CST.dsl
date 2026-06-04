/*
 * SSDT-CST.dsl — Custom C-States for AMD BC-250 / Cyan Skillfish
 *
 * Tested on: SteamOS 3.9.0, kernel linux-neptune-618 (6.18.33-valve1)
 *
 * Compile with:
 *   iasl SSDT-CST.dsl  →  SSDT-CST.aml
 *
 * Install to: /etc/initcpio/acpi_override/SSDT-CST.aml
 * Add hook:   HOOKS=(acpi_override ...) in /etc/mkinitcpio.conf.d/20-steamdeck.conf
 * Rebuild:    sudo mkinitcpio -p linux-neptune-618
 *
 * Verification:
 *   dmesg | grep "Table Upgrade"
 *   → SSDT-CST [HACK P_CST3] ✅
 */

DefinitionBlock ("SSDT-CST.aml", "SSDT", 2, "HACK", "P_CST3", 0x00000001)
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
     * C-State package format (ACPI spec _CST):
     *   Count, then for each C-State:
     *     ResourceTemplate (Register descriptor), CStateType, Latency (us), Power (mW)
     *
     * 3 C-States defined:
     *   C1  — Clock halt (MWAIT 0x00) — instant wake
     *   C2  — Light sleep (MWAIT 0x10) — 100 us latency
     *   C3  — Deep sleep (MWAIT 0x20) — 200 us latency
     */
    Name (CSTF, Package ()
    {
        0x03,  /* Number of C-States */

        /* C1 — Processor clock halt */
        Package ()
        {
            ResourceTemplate () { Register (FFixedHW, 0x01, 0x02, 0x0000000000000000, 0x01) },
            0x01,   /* C-State type: C1 */
            0x0001, /* Latency: 1 us */
            0x03E8  /* Power: 1000 mW */
        },

        /* C2 — Processor stop clock (light sleep) */
        Package ()
        {
            ResourceTemplate () { Register (FFixedHW, 0x01, 0x02, 0x0000000000000010, 0x03) },
            0x02,   /* C-State type: C2 */
            0x0064, /* Latency: 100 us */
            0x01F4  /* Power: 500 mW */
        },

        /* C3 — Deep sleep */
        Package ()
        {
            ResourceTemplate () { Register (FFixedHW, 0x01, 0x02, 0x0000000000000020, 0x03) },
            0x03,   /* C-State type: C3 */
            0x00C8, /* Latency: 200 us */
            0x00C8  /* Power: 200 mW */
        }
    })

    /* Inject _CST into each CPU object */
    Scope (_PR_.CPU0) { Method (_CST, 0) { Return (CSTF) } }
    Scope (_PR_.CPU1) { Method (_CST, 0) { Return (CSTF) } }
    Scope (_PR_.CPU2) { Method (_CST, 0) { Return (CSTF) } }
    Scope (_PR_.CPU3) { Method (_CST, 0) { Return (CSTF) } }
    Scope (_PR_.CPU4) { Method (_CST, 0) { Return (CSTF) } }
    Scope (_PR_.CPU5) { Method (_CST, 0) { Return (CSTF) } }
    Scope (_PR_.CPU6) { Method (_CST, 0) { Return (CSTF) } }
    Scope (_PR_.CPU7) { Method (_CST, 0) { Return (CSTF) } }
    Scope (_PR_.CPU8) { Method (_CST, 0) { Return (CSTF) } }
    Scope (_PR_.CPU9) { Method (_CST, 0) { Return (CSTF) } }
    Scope (_PR_.CPUA) { Method (_CST, 0) { Return (CSTF) } }
    Scope (_PR_.CPUB) { Method (_CST, 0) { Return (CSTF) } }
}
