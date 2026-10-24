# CS2 Core Affinity Manager

Automatically pins Counter-Strike 2 (`cs2.exe`) to the CPU cores you choose, every time the game starts, leaving the rest free for Windows, Discord, OBS and anything else running in the background.

It uses the same Windows setting as Task Manager → Details → **Set affinity**, just applied automatically. It doesn't touch the game's files or memory.

## Features

- **Waits for CS2** and applies the affinity a few seconds after it starts, then again on every relaunch.
- **Frees a whole physical core.** By default it reserves core 0 *and its Hyper-Threading/SMT twin*, so background work gets a real core instead of half of one.
- **Keeps it applied.** If anything resets the affinity while the game is running, it is put back.
- **Any CPU size.** Works on 32, 64 and more threads (the old version crashed above 31).
- **Optional priority boost** (`-Priority AboveNormal` or `High`).
- **Live CPU / RAM** usage of CS2 in the window title.
- **Single instance.** Running it twice (e.g. startup + Steam shortcut) won't stack copies.
- **Log file** for the No Window version, so you can check it's working.

## Downloads

Grab the latest from **[Releases](../../releases)**:

| File | Use it for |
|---|---|
| `CS2 Core Affinity Manager.exe` | Adding to your Steam library (Steam can't add `.bat` files). Shows a console window. |
| `CS2 Core Affinity Manager - No Window.exe` | Running silently at Windows startup. Logs to `%LOCALAPPDATA%\CS2AffinityManager\log.txt`. |
| `CS2-Core-Affinity-Manager.bat` + `.ps1` | The plain script. Keep both files in the same folder. |

The exes are built automatically from the `.ps1` by GitHub Actions, so you can see exactly what's in them.

## Setup

**Run at startup (recommended):** press `Win + R`, type `shell:startup`, and put a shortcut to `CS2 Core Affinity Manager - No Window.exe` in the folder that opens.

**From Steam:** *Games → Add a Non-Steam Game* → pick `CS2 Core Affinity Manager.exe`, and launch it before CS2.

## Options

Pass these to the `.exe` (shortcut target or Steam launch options), the `.ps1`, or set them at the top of the `.bat`.

| Option | Default | What it does |
|---|---|---|
| `-ExcludeCores 0` | `0` | Cores CS2 must not use. e.g. `0`, `0,1`, `0-3` |
| `-LogicalOnly` | off | Free only the exact cores listed, not their Hyper-Threading twins |
| `-Priority High` | unchanged | `Normal`, `AboveNormal` or `High` |
| `-ApplyDelaySeconds 5` | `5` | Wait this long after the game starts before applying |
| `-PollSeconds 5` | `5` | How often to check |
| `-Once` | off | Apply once, exit when the game closes |
| `-Silent` | off | No console output (automatic for the No Window exe) |
| `-LogFile path` | none | Write a log file |

Example shortcut target:

```
"C:\Tools\CS2 Core Affinity Manager - No Window.exe" -ExcludeCores 0-1 -Priority AboveNormal
```

## Will it make CS2 faster?

It depends on your PC. Reserving a core mostly helps when background apps are fighting the game for CPU time, and it can cost a little performance on CPUs with few cores. Try it with and without, using the same demo or benchmark map, and keep whichever gives you better 1% lows.

**Tips:**
- 4 cores or fewer: try `-LogicalOnly` so you only give up one thread.
- AMD X3D chips with two CCDs (7950X3D, 9950X3D…): the cache CCD is usually cores `0-15`, so excluding core 0 removes a cache core. Experiment, or exclude cores on the other CCD instead.
- Intel hybrid CPUs: core numbering assumes P-cores come first, which is standard on Windows.

## Troubleshooting

- **"Access denied"** – CS2 is running as administrator; run this tool as administrator too.
- **"Another copy is already running"** – it's already active (check Task Manager), nothing to do.
- **Nothing happens with the No Window version** – open `%LOCALAPPDATA%\CS2AffinityManager\log.txt`.
- **Windows SmartScreen warns about the exe** – it's unsigned. Use the `.bat` + `.ps1` instead if you prefer.
