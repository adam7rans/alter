# alter

> Two tiny macOS background tools for nudging your mind toward where you want it to go.

`alter` is three native Swift programs that run quietly in the background while you work:

- **`breathe`** — every ~3–10 minutes (random), the word *breathe* fades in across your screen with a gentle sine-wave distortion, holds for a few seconds, then fades away. Conscious, intentional, a moment to inhale.
- **`affirm`** — every 15–60 seconds (random), one affirmation from your personal list flashes for 33 ms at a random spot on screen, immediately scrubbed by a 120 ms random-character mask. **Subliminal:** you won't consciously read it, but your visual cortex still processes it.
- **`alterprefs`** — a tiny SwiftUI menu-bar app (waveform icon in your status bar) for tweaking every parameter of both tools live — intervals, durations, opacity, wave shape, font size — with sliders. Includes "Fire now" buttons to test changes immediately. Changes save instantly and the next firing picks them up; no rebuild.

The overlays are **click-through** (won't steal focus or block typing), **idle-aware** (do nothing if you've walked away), and hold **no power assertions** (won't keep your Mac awake).

## Why

The `breathe` overlay is a low-friction mindfulness nudge — most reminder apps are either dismissible notifications you ignore, or modal interruptions you resent. A 6-second translucent fade above all your windows is hard to ignore and impossible to dismiss.

The `affirm` overlay is built on the subliminal-priming literature (Bargh, Custers, Aarts et al.) — brief masked presentation of goal-related words has measurable effects on subsequent behavior and decision-making. By cycling through *your* affirmations at random intervals and positions, you reprogram the substrate without ever consciously rehearsing the words.

```diagram
launchd tick (every 60s)
        │
        ▼
   binary runs ─── idle >2 min?    ──▶ exit silently
        │
        ├── too soon since last?  ──▶ exit silently
        │
        ▼
   show overlay → exit
```

## Requirements

- macOS 12+ (Apple Silicon or Intel)
- Xcode Command Line Tools (for `swiftc`): `xcode-select --install`

## Install

```bash
git clone https://github.com/adam7rans/alter.git
cd alter
./install.sh
```

The installer:
1. Compiles `breathe.swift` and `affirm.swift` with `swiftc -O`.
2. Copies `affirmations.example.txt` → `affirmations.txt` (if you don't have one yet).
3. Generates two launchd plists pointed at your install path.
4. Copies them to `~/Library/LaunchAgents/` and loads them.

You'll also get a one-time macOS prompt to allow file access to the install directory. Click **Allow**.

## Customizing

### Your affirmations
Edit [`affirmations.txt`](./affirmations.example.txt) — one per line, `#` for comments, blank lines OK. Changes are picked up on the next firing; no rebuild needed.

```txt
I am calm.
I am focused.
Money flows to me.
My body is healthy.
```

`affirmations.txt` is **gitignored** — your personal list stays on your machine and never leaves it.

### Timing, typography, colors, wave shape
Easiest path: click the waveform icon in your menu bar (`alterprefs`) and drag the sliders. Every change writes to `~/Library/Application Support/breathe/config.json` and the next firing picks it up. No rebuild, no reload.

Power-user path: edit `~/Library/Application Support/breathe/config.json` directly in any text editor. Both binaries fall back to their compiled-in defaults for any field that's missing or unparseable, so a partial config is fine.

Defaults / hard caps: each source file has its `Config` struct at the top with defaults, and `alterprefs.swift` defines the slider ranges. Edit those and re-run `./install.sh` if you need values outside the slider ranges.

## Verifying it works

The `breathe` overlay is, well, visible.

For `affirm`, since each flash is briefer than conscious recognition, you have two easy ways to test it:

- Click `Preview` in the `alterprefs` menu-bar app. That runs the next affirmation with a longer visible dwell and no mask so you can inspect wrapping and placement.
- Or run `./affirm --preview` from the repo root for the same visible preview behavior.

If you want to stress-test layout, add one intentionally long affirmation, set a larger font size in `alterprefs`, then hit `Preview` several times to sample different random positions.

For background verification, watch one of these instead:

```bash
# index increments every time an affirmation flashes
cat "$HOME/Library/Application Support/breathe/affirm_index"

# any errors?
cat /tmp/alter-affirm.err.log
```

## Uninstall

```bash
./uninstall.sh
```

This unloads the agents and removes the plists from `~/Library/LaunchAgents/`. Source files, binaries, and your `affirmations.txt` remain on disk.

## How it's built

Both binaries are single-file Swift programs:

- `breathe.swift` uses `Cocoa` + `IOKit` + `Metal` + `CoreImage`. The wave distortion is a `CIWarpKernel` (Core Image Kernel Language) rendered via `MTKView` — a direct port of the WebGL fragment shader used in [CAST](https://github.com/) for caption animation.
- `affirm.swift` uses `Cocoa` + `IOKit`. Idle detection is via `IOHIDSystem`'s `HIDIdleTime`. State (cycle index + next-allowed timestamp) lives in `~/Library/Application Support/breathe/`.

Scheduling is via per-user `launchd` agents in `~/Library/LaunchAgents/`. launchd ticks each binary every 60 seconds; the binary itself decides whether to actually show something or exit silently.

## License

MIT — see [LICENSE](./LICENSE).
