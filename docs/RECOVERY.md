# Recovery: what to do if your Mac stops charging

Don't panic. Calma doesn't change anything permanently, and every setting it touches goes back to stock behaviour through one of the steps below. Work through them in order.

## 1. Check it isn't just doing its job

Open the Calma menu. If it says **Holding at 80%**, **Charging paused** or **Paused — battery warm**, charging is paused on purpose.

- Drag the limit to **100%**, turn off **Pause Charging**, or click **Cancel** on an active drain or recalibration.
- Or from Terminal: `calma limit 100 && calma resume && calma cancel`

## 2. Emergency Reset

- In the app: **Settings → Advanced → Emergency Reset**
- Or from Terminal:
  ```sh
  calma reset
  ```

This re-enables charging and the adapter on every supported key, clears special modes, and returns the MagSafe LED to macOS. Unplug and plug the adapter back in afterwards.

## 3. Stop and remove the helper

If the app or CLI can't reach the helper, remove it by hand. Stopping the helper also restores charging.

```sh
sudo launchctl bootout system/io.github.milanpatel35.calmad
sudo rm -f /Library/LaunchDaemons/io.github.milanpatel35.calmad.plist /Library/PrivilegedHelperTools/calmad /var/run/calmad.sock
sudo rm -rf "/Library/Application Support/Calma"
```

Optionally remove the logs and the CLI link:

```sh
sudo rm -rf /Library/Logs/Calma
sudo rm -f /usr/local/bin/calma
```

Then unplug and replug the adapter.

## 4. Reset the SMC

An SMC reset always clears every key Calma may have written.

### Apple Silicon (M1 and later)

1. Choose **Apple menu → Shut Down**. A restart isn't enough.
2. Wait **at least 30 seconds**.
3. Press the power button to start up again.

### Intel Mac with the T2 chip (2018–2020)

1. Shut down.
2. Press and hold **Control (left) + Option (left) + Shift (right)** for **7 seconds**. Keep holding them, then also press and hold the **power button** for another **7 seconds**.
3. Release all keys, wait a few seconds, then press the power button to start up.

### Intel Mac without T2 (2016–2017)

1. Shut down.
2. Press and hold **Shift + Control + Option** (left side) **and the power button** together for **10 seconds**.
3. Release all keys, then press the power button to start up.

## 5. Still not charging?

It may not be Calma at all. Check:

- Another charge-limiting app, or macOS's own **Optimised Battery Charging** or **Charge Limit** in System Settings → Battery
- A different cable, adapter or port
- **System Settings → Battery → Battery Health** reporting "Service Recommended"

If you think Calma is responsible, please [open a bug report](https://github.com/Milanpatel35/calma/issues/new?template=bug_report.yml) and include:

```sh
sysctl -n hw.model; sw_vers
calma probe
tail -n 100 /Library/Logs/Calma/calmad.log
```

The log shows exactly which keys were written, when, and why.
