# SMC keys

This is a community-maintained reference for the System Management Controller keys Calma reads and writes. Apple doesn't document these keys. Everything here comes from public open-source work and from hardware reports.

> **Rule:** a key may only be added to the write allowlist (`Sources/CalmaHardware/SMCKeys.swift`) after this file documents its meaning, size, values, safe default and at least one confirmed model.

## Write allowlist

These are the only keys `calmad` will ever write.

| Key | Type / size | Values | Safe default | Meaning | Platform |
|---|---|---|---|---|---|
| `CH0B` | `ui8` / 1 | `02` inhibit · `00` allow | `00` | Charge inhibit (set together with `CH0C`) | Apple Silicon (older firmware), many Intel |
| `CH0C` | `ui8` / 1 | `02` inhibit · `00` allow | `00` | Charge inhibit (set together with `CH0B`) | Apple Silicon (older firmware), many Intel |
| `CHTE` | `ui32` / 4 | `01000000` inhibit · `00000000` allow | `00000000` | Charge inhibit | Apple Silicon, macOS 15–26 firmware |
| `CH0I` | `ui8` / 1 | `01` adapter off · `00` adapter on | `00` | Run from battery while plugged in | Apple Silicon (older firmware), Intel |
| `CHIE` | `hex_` / 1 | `08` adapter off · `00` adapter on | `00` | Run from battery while plugged in | Apple Silicon, macOS 15+ firmware |
| `BCLM` | `ui8` / 1 | percent, e.g. `50` = 80% | `64` (100%) | Hardware charge ceiling | Intel |
| `ACLC` | `ui8` / 1 | `00` system · `01` off · `03` green · `04` amber | `00` | MagSafe 3 LED | Apple Silicon with MagSafe 3 |

Multi-byte values are listed in the byte order they're written.

## Read-only keys

| Key | Type | Meaning | Notes |
|---|---|---|---|
| `TB0T`, `TB1T`, `TB2T` | `flt ` (Apple Silicon, little-endian float) / `sp78` (Intel) | Battery temperature sensors in °C | Calma uses the highest valid reading |
| `BRSC` | `ui8` | Battery controller state of charge (%) | Used to cross-check True Percentage |
| `CHLT`, `bfG0` | `hex_` / 3 | macOS's built-in charge limit on macOS 27 (first byte = percent) | Read-only. Shown as the native limit |
| `#KEY` | `ui32` | Number of keys | Used by `calma probe` |

## Backend detection

| Condition | Backend |
|---|---|
| `CHTE` readable | `appleSiliconModern` (`CHTE` + `CHIE`) |
| `CH0B` and `CH0C` readable on Apple Silicon | `appleSiliconLegacy` (`CH0B`/`CH0C` + `CH0I`) |
| Intel CPU and `BCLM` readable | `intel` |
| None of the above | `unsupported`: monitoring only |

## Confirmed hardware

Reports from real machines. Please add yours with a [hardware report](https://github.com/Milanpatel35/calma/issues/new?template=hardware_report.yml).

| Model id | Mac | Chip | macOS | Keys present | Backend | Charge limit | Drain | MagSafe Light | Reporter |
|---|---|---|---|---|---|---|---|---|---|
| `Mac16,1` | MacBook Pro 14" (2024) | M4 | 27.0 | `CHIE`, `ACLC`, `TB0T`–`TB2T`, `BRSC`, `CHLT`, `bfG0`. **Absent:** `CH0B`, `CH0C`, `CHTE`, `CH0I` | `unsupported` | ❌ (monitoring) | ❌ | not tested | @Milanpatel35 |

### Needs hardware reports

- Intel MacBook Pro / Air, 2016–2020 (`BCLM`)
- Apple Silicon on macOS 13–14 (`CH0B`/`CH0C`/`CH0I`)
- Apple Silicon on macOS 15–26 (`CHTE`/`CHIE`)
- MagSafe 3 LED behaviour (`ACLC`) on any supported firmware

## macOS 27 ("Golden Gate" firmware)

Verified on `Mac16,1` running macOS 27.0 with read-only `calma probe`:

- `CH0B`, `CH0C`, `CHTE` and `CH0I` **don't exist**.
- `CHIE` exists (`hex_`, value `00`).
- `CHLT` and `bfG0` read `50 05 05`. The first byte, `0x50` = 80, matches the charge limit set in System Settings.
- `bfD0`, `bfE0` and `bfF0` exist but **can't be read** without privileges. Other projects report they're refused even from a root process, and no public documentation of their layout exists.

What this means for Calma:

- Calma selects the `unsupported` backend and runs in **monitoring mode**.
- Calma does **not** use `CHIE` to fake a limit by switching the adapter on and off. That was tried elsewhere and dropped, because it repeatedly cycles the battery and wears it faster, which defeats the purpose.
- Calma does **not** write to `bf*` keys until their meaning is documented and verified safe.
- Users can set 80–100% in System Settings → Battery → Charge Limit. Calma shows that value.

Research is tracked in the **"macOS 27 charge control"** help-wanted issue. Please share findings there, not by adding keys to the allowlist.

## Running a probe

```sh
calma probe          # no root needed; read-only
```

It prints every key above with its type and raw bytes, plus the list of charge-related keys (`CH*`, `AC*`, `BC*`, `bf*`) present on your Mac. Paste the output into your hardware report.

## Sources and prior art

- [charlie0129/batt](https://github.com/charlie0129/batt): Apple Silicon charge control, including capability checks for newer firmware
- [mhaeuser/Battery-Toolkit](https://github.com/mhaeuser/Battery-Toolkit)
- [actuallymentor/battery](https://github.com/actuallymentor/battery), including the macOS 27 discussions
- [zackelia/bclm](https://github.com/zackelia/bclm): `BCLM` on Intel
- [hholtmann/smcFanControl](https://github.com/hholtmann/smcFanControl): the AppleSMC user-client structure layout
- [Asahi Linux](https://asahilinux.org) `macsmc` power-supply driver: `CH0C`/`CH0I`/`CHTE` semantics and the macOS 27 `BCF0` size change
