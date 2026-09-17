# FAQ

### Is Calma really free?
Yes. Every feature is free, with no Pro tier, licence key, account or ads. Calma is GPL-3.0, so it stays open source.

### Does limiting the charge actually help?
Lithium-ion cells age faster when kept at a high state of charge, especially when warm. Keeping the battery around 50–80% when you're mostly plugged in reduces that stress. How much it helps depends on temperature, usage and the battery itself, so we don't promise a specific number.

### Which limit should I pick?
80% for everyday use. 50–60% if your Mac almost never leaves the desk. Use **Full Charge** before a trip.

### Why does the battery sit at 80% but macOS says "Not Charging"?
That's Calma working. The adapter powers the Mac directly and the battery rests.

### Why does it charge past my limit while the Mac sleeps?
While the Mac is fully asleep, the helper can't run. Turn on **Pause on Sleep**, which stops charging before sleep, or **Stay Awake to Limit**.

### Does my limit survive quitting the app?
Only if **Keep Limit After Quit** is on. With it off, charging returns to normal when you quit, which is the safe default.

### Does it work on macOS 27?
Only in monitoring mode, for now. macOS 27 firmware removed the documented charge-control keys. See the [README](../README.md#macos-27-status) and [SMC_KEYS.md](SMC_KEYS.md#macos-27-golden-gate-firmware). Meanwhile, macOS's own **System Settings → Battery → Charge Limit** (80–100%) works, and Calma shows it.

### Why does it need an administrator password?
Changing charging behaviour means writing to the SMC, which only root can do. Calma installs one small helper (`calmad`) for that, and everything else runs as your user.

### macOS says the app "can't be opened" or is from an unidentified developer.
Community builds aren't notarized yet (that needs a paid Apple Developer account). Right-click the app and choose **Open**, or run `xattr -dr com.apple.quarantine /Applications/Calma.app`. You can also [build it yourself](../README.md#build-from-source).

### Does Calma collect data?
No. The only network request is the optional update check against GitHub Releases, and it's off by default.

### Can I use it with another battery app?
Please don't. Two apps writing the same SMC keys will fight each other. Quit and remove the other app's helper first.

### What is True Percentage?
macOS smooths the percentage it shows you. True Percentage uses the battery controller's raw reading, which can differ by a few percent. When it's on, all Calma features use the raw value.

### What does Drift Range do?
Once the battery reaches your limit, Calma waits until it drops a few percent below it before charging again. This avoids constant 1% top-ups.

### Is Recalibrate bad for the battery?
It uses one full cycle, so don't run it often. Every month or two is plenty. It helps macOS's percentage reading stay accurate.

### How do I remove Calma completely?
Go to **Settings → Advanced → Uninstall Helper**, then drag Calma.app to the Bin. Manual steps are in [RECOVERY.md](RECOVERY.md#3-stop-and-remove-the-helper).

### My Mac stopped charging entirely!
See [RECOVERY.md](RECOVERY.md). A full shutdown on Apple Silicon, or an SMC reset on Intel, always restores stock behaviour.
