# Launch posts

Ready-to-post copy for announcing Calma. Adjust the tone to match your own voice. Every claim here is accurate as of v0.1.0.

**Links**

- Repo: https://github.com/Milanpatel35/calma
- Website: https://milanpatel35.github.io/calma/
- Download: https://github.com/Milanpatel35/calma/releases/latest

---

## GitHub "About" (≤ 350 chars)

> Free, open-source battery charge limiter for macOS. Hold your MacBook at 80% (or any level), drain while plugged in, heat protection, recalibration, scheduling, MagSafe LED, live power flow, CLI. Every feature free, with no telemetry.

**Website field:** `https://milanpatel35.github.io/calma/`

**Topics:** `macos` `battery` `charge-limit` `menubar` `swift` `swiftui` `apple-silicon` `smc` `open-source` `battery-health`

---

## LinkedIn

> 🔋 I just open-sourced **Calma**, a free battery charge limiter for macOS.
>
> Like a lot of developers, my MacBook sits plugged in on my desk most of the day. Lithium-ion batteries wear fastest when they're held at 100%, so a Mac that's always plugged in spends most of its life in exactly the state that ages it.
>
> Apps that fix this exist, but the useful parts (heat protection, scheduling, draining while plugged in) are often behind a subscription. I wanted a version that's completely free, that anyone can audit, and that the community can keep improving.
>
> **What Calma does**
> ✅ Holds the battery at any limit from 20% to 100%
> ✅ Drains while plugged in, with an automatic mode
> ✅ Pauses charging when the battery runs warm
> ✅ Runs a guided recalibration cycle
> ✅ Schedules limits and full charges
> ✅ Controls the MagSafe LED and shows a live power-flow diagram
> ✅ Includes a CLI and Shortcuts support
>
> **How it's built:** native Swift/SwiftUI, with a tiny root helper that's the only process allowed to touch the charging controller. It accepts a fixed set of commands from admins only, writes nothing outside a short key allowlist, and logs every write locally. There's no telemetry.
>
> **One honest caveat:** macOS 27 removed the documented charge-control keys. On macOS 27 Calma currently runs in monitoring mode, and I chose not to write guessed values to people's charging hardware. If you know the new interface, I'd love your help.
>
> It's GPL-3.0 and contributions are very welcome, especially hardware reports from different MacBook models and translations.
>
> ⭐ GitHub: https://github.com/Milanpatel35/calma
> 🌐 Website: https://milanpatel35.github.io/calma/
>
> #opensource #macOS #Swift #SwiftUI #AppleSilicon #indiedev

---

## X / Twitter thread

**1/**
I built Calma 🔋: a free, open-source app that stops your MacBook charging past the level you choose.

Every feature is free. No Pro tier, no account, no telemetry.

https://github.com/Milanpatel35/calma

**2/**
Why? Batteries wear fastest when they're held at 100%, and a Mac that lives on a desk is plugged in most of the day.

Pick 80% (or anything from 20–100%) and the adapter powers the Mac while the battery rests.

**3/**
It also includes:
• drain while plugged in (manual + auto)
• pause charging when the battery is warm
• guided recalibration
• scheduling
• MagSafe LED colours
• live power-flow diagram
• `calma` CLI + Shortcuts URLs

**4/**
Safety first: a tiny root helper is the only thing that touches the charging controller. It only accepts fixed commands from admins, refuses any key outside its allowlist, logs every write, and restores normal charging if anything goes quiet.

**5/**
Honest note: macOS 27 removed the known charge-control keys, so Calma runs in monitoring mode there for now.

GPL-3.0. Hardware reports, translations and PRs are all welcome 🙏
🌐 https://milanpatel35.github.io/calma/

---

## Reddit, r/macapps

**Title:** [Open Source] Calma: a free menu bar app to limit your MacBook's charge (heat protection, drain, schedule, CLI, all free)

**Body:**

> Hi r/macapps! I'm the developer. Calma is a **free and open-source** (GPL-3.0) menu bar app that limits how far your MacBook charges, so it isn't sitting at 100% all day while plugged in.
>
> **Features (all free):** charge limit 20–100%, drain while plugged in (manual and automatic), a "drift range" so it doesn't top up 1% at a time, heat protection with sensible hysteresis, a guided recalibration cycle, full charge that reverts when you unplug, pause on sleep, a scheduler, MagSafe LED control, a live power-flow view, battery health and temperature, low/high power mode toggles, and a `calma` CLI plus `calma://` URLs for Shortcuts.
>
> **How it works:** a small root helper is the only process that writes to the SMC. It accepts a fixed set of commands from admin users over a local socket, refuses any key outside a short allowlist, and logs every write locally. There's no telemetry, and the update check is off by default.
>
> **Please read before installing:**
> - **macOS 27:** Apple removed the documented charge-control keys, so on macOS 27 Calma runs in **monitoring mode** only (stats, power flow, health). I didn't want to write guessed values to people's charging hardware. macOS 13–26 and Intel are supported, but I need **hardware reports** to confirm specific models.
> - **Not notarized yet** (no paid developer account), so the first launch needs one approval in System Settings → Privacy & Security → Open Anyway. You can also build it from source with `swift build`.
> - Don't run it alongside another charge-limiting app.
>
> Download: https://github.com/Milanpatel35/calma/releases/latest
> Source: https://github.com/Milanpatel35/calma
>
> Feedback, bug reports and "works on my M2 Air" reports are all hugely appreciated!

---

## Hacker News

**Title:** Show HN: Calma – Free, open-source battery charge limiter for macOS

**URL:** https://github.com/Milanpatel35/calma

**First comment:**

> Hi HN, I built Calma because my MacBook spends most of its life plugged in at 100%, and the tools that fix that often put the useful features behind a subscription.
>
> Calma is a SwiftUI menu bar app plus a small root LaunchDaemon (`calmad`). Some design choices that might interest people:
>
> - **All the decision logic is a pure function** (`ChargeEngine.evaluate`): settings + battery snapshot + previous state in, a decision out (charge on/off, adapter on/off, sleep assertion, LED). Limits, drift hysteresis, heat protection and the recalibration state machine are all unit-tested without touching hardware.
> - **IPC is newline-delimited JSON over a Unix socket**, not XPC. Validating XPC code signatures only really works with a paid Developer ID, and community builds are ad-hoc signed. The daemon checks the caller with `getpeereid` and requires root or `admin` group membership for anything that changes state. No command can name an SMC key, and a hardcoded allowlist sits in front of IOKit.
> - **The SMC access layer is ~150 lines of C** so the `SMCKeyData_t` layout matches the kernel exactly.
>
> The awkward part: **macOS 27 firmware removed CH0B/CH0C/CHTE/CH0I.** I confirmed this on an M4 MacBook Pro. The new keys (`bfD0/bfE0/bfF0`) are undocumented and unreadable without privileges. One workaround toggles the adapter via `CHIE`, but that micro-cycles the battery, so Calma doesn't use it. It runs in monitoring mode on 27 instead. If anyone understands the new interface, I'd love to hear from you.
>
> GPL-3.0. Happy to answer questions.

---

## Product Hunt

**Name:** Calma

**Tagline (≤ 60 chars):** Free, open-source charge limiter for your MacBook

**Description (≤ 260 chars):**
> Calma stops your MacBook charging past the level you choose, so the battery lasts longer. It also offers drain while plugged in, heat protection, recalibration, scheduling, MagSafe LED control, live power flow and a CLI. Every feature is free, and there's no telemetry.

**Topics:** Mac, Open Source, Productivity, Developer Tools

**First comment (maker):**
> Hey Product Hunt 👋 I'm Milan, the maker of Calma.
>
> My Mac lives on my desk, plugged in, and batteries age fastest when they sit at 100%. I wanted a charge limiter where **every feature is free**, the code is open for anyone to audit, and nothing phones home. So I built one.
>
> What I'm proudest of is the safety design. A tiny helper is the only thing allowed to touch the charging controller, it accepts only a fixed set of commands, logs every change locally, and restores normal charging if anything goes wrong.
>
> Two honest notes: on **macOS 27** Calma currently runs in monitoring mode, because Apple removed the documented charging keys. And builds aren't notarized yet, so the first launch needs one approval in System Settings → Privacy & Security.
>
> I'd love your feedback, and if you own a MacBook model I haven't tested, a quick hardware report on GitHub would help a lot. 🙏
