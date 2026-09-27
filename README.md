# PandaProd

A desktop panda that reacts to what you're working on. He lives along the bottom of your screen, walks, sits, climbs the screen edges, and his mood rises while you use productive apps and drops on distracting ones.

Windows only. The repo holds the source, not a ready-made exe: build one with the steps below.

## What you need

- **Windows 10 or 11.**
- **Python 3** from [python.org](https://www.python.org/downloads/). In the installer, tick **"Add python.exe to PATH"**. PandaProd runs a small Python script (`sidecar/tracker.py`) to see which app you're using.
- **Godot 4.7.2**, the standard version (not .NET), from [godotengine.org](https://godotengine.org/download/archive/). It's a zip with two exes; keep both.

## Get the code

```powershell
git clone https://github.com/chase-the-dream/panda-prod.git
cd panda-prod
```

## Option A: run it from the Godot editor

1. Open Godot, click **Import**, and pick `project.godot` in the repo folder.
2. In the editor's **Game** tab, turn off **"Embed Game on Next Play"**. Embedded, the panda runs inside the editor as a normal window instead of on your desktop.
3. Press **F5**.

## Option B: build the exe

1. **Install the export templates** (once): in the Godot editor, **Editor > Manage Export Templates > Download and Install**.
2. **Run the export script** from PowerShell in the repo folder, pointing `GODOT` at the `_console.exe` from the Godot zip (PowerShell waits for it; it doesn't wait for the other exe):

   ```powershell
   $env:GODOT = "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
   powershell -ExecutionPolicy Bypass -File .\export.ps1
   ```

   `-ExecutionPolicy Bypass` is only there because Windows blocks unsigned scripts by default. Add `-DebugBuild` at the end for a debug build (it also makes `PandaProd.console.exe`, which shows Godot's output in a terminal).
3. **Find the build** in `build\` (not in git):
   - `PandaProd.exe` and `tracker.py`: the app. `tracker.py` must stay in the same folder as the exe.
   - `README.txt`: setup notes for whoever runs it.
   - `PandaProd.zip`: all three in one file, to share. Whoever you send it to needs Python 3 too.
4. **Run `build\PandaProd.exe`.** Windows may say "Windows protected your PC" because the app isn't signed: click **More info**, then **Run anyway**.

## Using it

- Hold left-click on the panda to pick him up by the tail, swing him around, and let go to throw him. Throw him at the edge of the screen and he'll cling on and climb.
- Right-click him to open his status window: mood, name, sleep mode, settings, achievements and help (the **?** tab).
- Both app lists start empty: add your own apps and sites in the status window's **!** tab (for example "Code" or "YouTube"). An entry matches any app or window title containing it. Until you add some, everything counts as neutral and his mood slowly drops.
- Rub your cursor back and forth over him to pet him.
- To quit: click him, then press **Esc**.

## Notes

- **Demo speed:** his mood currently changes about 30 times faster than normal, so you can watch him react (`RATE_SCALE` in `autoload/pet_brain.gd`).
- **Save data** is kept in `%APPDATA%\Godot\app_userdata\PandaProd`. Delete that folder to start over.
- **Privacy:** the app only looks at the name and title of the window you're using, on your own machine. Nothing about the windows you use is saved, and nothing is sent over the internet.
