# Safety

Calma changes how your Mac's charging hardware behaves. This page explains the risks, what Calma does to contain them, and what you should know before using it.

## The short version

- Nothing Calma does is permanent. Every key it writes goes back to stock behaviour after an SMC reset, and on Apple Silicon after a full shutdown.
- Calma writes only a short allowlist of documented keys, and only from one small root helper.
- If Calma or its helper stops, charging returns to normal (unless you asked it to keep the limit).
- If anything looks wrong, use **Emergency Reset** or `calma reset`, then see [RECOVERY.md](RECOVERY.md).

## What can go wrong

| Risk | Example | How Calma handles it |
|---|---|---|
| The Mac won't charge | Inhibit left set after a crash | Heartbeat watchdog, restore on exit, Emergency Reset, SMC reset |
| The battery drains unexpectedly | Drain mode left on | Drains stop at the target, drains are refused below 20%, the adapter is always re-enabled when unplugged |
| The Mac dies while draining in a closed bag | Sleep assertion while draining | The assertion is only held **while plugged in**. Unplugging ends it |
| Charging while hot | High ambient temperature | Optional Heat Guard, and draining is refused if temperature can't be read |
| New firmware changes key meanings | macOS 27 removed the known keys | Backend detection at every start, and unknown firmware gets monitoring mode only |
| Privilege misuse | Another local user or process | Admin-only IPC, no arbitrary key writes (see [ARCHITECTURE.md](ARCHITECTURE.md#threat-model)) |

## Safeguards in detail

1. **Allowlist.** `calmad` refuses to write any key except `CH0B`, `CH0C`, `CHTE`, `CH0I`, `CHIE`, `BCLM` and `ACLC`. The size of every write must match the key's declared size.
2. **No generic commands.** The IPC protocol only has high-level commands like "set limit 80" and "drain to 60". It has no way to name a key.
3. **First-run probe.** Before its first write, the helper records every relevant key's original value in `/Library/Application Support/Calma/smc-probe.json`.
4. **Write log.** Every write records the time, key, old value, new value and reason in `/Library/Logs/Calma/calmad.log`. The log rotates automatically and never leaves your Mac.
5. **Restore on exit.** When the helper receives `SIGTERM` (shutdown, logout of the system, uninstall), it re-enables charging and the adapter and hands the MagSafe LED back to macOS. The exception is when **Keep Limit After Quit** is on.
6. **Heartbeat watchdog.** The app pings the helper every 20 seconds. If Keep Limit After Quit is off and the helper hears nothing for 90 seconds, it stops enforcing and restores stock charging.
7. **Input limits.** The charge limit is clamped to 20–100%, Drift Range to 1–20%, and the Heat Guard threshold to 25–50 °C.
8. **Drain preconditions.** Draining needs a readable temperature, a battery level of at least 20%, and a target below the current level. Recalibration also requires the Mac to be plugged in.
9. **Confirmation dialogs.** The app asks before Recalibrate, Drain and Emergency Reset.
10. **Emergency Reset.** This writes the stock value to every allowlisted key present on the Mac, clears all special modes and pauses, and returns the LED to macOS.

## About Recalibrate

Recalibration deliberately runs the battery from 100% down to 10% and back. It uses one full cycle, which is why it's manual or scheduled and never automatic. Running it every month or two is plenty. Keep the Mac plugged in, somewhere cool, and awake. Calma holds a sleep assertion while it runs.

## About Keep Limit After Quit

With this on, the SMC keeps its inhibit state after you quit Calma, and the helper keeps enforcing your limit. On Apple Silicon a full shutdown resets the SMC to stock behaviour anyway, and the helper re-applies your settings at the next boot.

## Uninstalling

Use **Settings → Advanced → Uninstall Helper**, or run `sudo Scripts/uninstall-daemon.sh`. Both restore stock charging before removing anything. If the helper is already gone, [RECOVERY.md](RECOVERY.md) has manual steps.

## No warranty

Calma is licensed under GPL-3.0 and provided **as-is, without warranty of any kind**. You're responsible for how you use it.
