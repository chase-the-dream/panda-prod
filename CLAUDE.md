# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

PandaProd is a Godot 4.7 (Forward Plus, GDScript) desktop-pet app: a small borderless, transparent, always-on-top 256×320 window showing a pet sprite that reacts to the user's currently active application.

## Running

There is no build system, linter, or test suite. The project is run from the Godot 4.7 editor (open `project.godot`, press F5), or from the command line if a Godot binary is available (it is not on PATH by default):

```
godot --path . # run main scene (res://pet/pet.tscn)
godot --path . -e # open in editor
```

Press Esc in the running pet window to quit.

Python 3 must be on PATH (`python` or `py`): `autoload/tracker.gd` spawns `sidecar/tracker.py` as a sidecar process on startup.

The editor's game embedding (Game tab, "Embed Game on Next Play") must be **off** for F5 runs: an embedded game ignores the borderless/transparent/always-on-top settings and can't move its own window, so the pet looks like a normal non-draggable window.

## Exporting

Requires the Godot 4.7.2 export templates (Editor > Manage Export Templates). Run `./export.ps1` (PowerShell; set `$env:GODOT` to override the Godot binary path) to make a debug export with the "Windows Desktop" preset in `export_presets.cfg`. The output goes to `build/` (gitignored): `PandaProd.exe`, `PandaProd.console.exe` (shows Godot output in a terminal), and a copy of `sidecar/tracker.py`, which must sit directly beside the exe. The target machine needs Python on PATH.

## Layout

- Root — project config (`project.godot`, `export_presets.cfg`), `export.ps1`, and `icon.svg` (Godot default, now unused; the app icon is `art/pandatemp.png`).
- `autoload/` — global singletons registered under `[autoload]`: `tracker.gd`, `save_manager.gd`, `classifier.gd`, `pet_brain.gd` now; planned `activity.gd`, `stats.gd`.
- `data/` — runtime config loaded via `res://`: `classification.json`.
- `sidecar/` — out-of-process helpers Godot launches (not Godot resources): `tracker.py`.
- `pet/` — the pet scene and its parts: `pet.tscn`, `pet.gd`; planned `panda_right.tscn`, `spring_part.gd`.
- `ui/` — UI scenes and their art/fonts: `status.tscn`/`status.gd` (+ `status.png`, `Game Font.ttf`); planned `settings.tscn`, `tasks.tscn`.
- `art/` — exported PNGs and their `.ase` sources.

## Architecture

- `pet/pet.tscn` / `pet/pet.gd` — the only scene (`Pet`, a `Node2D` with `Sprite2D` and `Label` children) and the main scene. The whole OS window is the pet body: `pet.gd` keeps a float window position/velocity and writes `get_window().position` every `_physics_process` tick. A `Pose` state machine (`HELD`, `AIRBORNE`, `GROUNDED`, `CLING_LEFT`/`RIGHT`/`TOP`, announced via `pose_changed`) handles the movement. Left mouse picks the pet up, and releasing throws it with the velocity of the last `THROW_SAMPLE_TIME` of drag. Gravity then applies, and the sprite rect (not the label) collides with the usable rect (taskbar excluded) of the monitor it's on. Side and top edges make it cling (placeholder: sprite rotated) until grabbed again; the floor bounces or lands it, then it slides to a stop. Double-clicking opens the status window (see below; the pair's first click is still a normal pick-up and drop). It also quits on Esc and shows the mood state/value plus the active app and its category in the label.
- `ui/status.tscn` / `ui/status.gd` — the status window, a `Window` root that `pet.gd` instantiates on first double-click and then reuses (`open_centered(screen)`). It's a separate native OS window because `display/window/subwindows/embed_subwindows=false`; with embedding on it would be drawn inside the small pet window. It's borderless, transparent and always on top. Controls are laid out in `status.png`'s native 144×142 pixels, and `content_scale_mode = canvas_items` scales them by `UI_SCALE` (5; keep it an integer so art pixels stay even), so the art stays crisp and text renders at full resolution. A `Window` has its own viewport that ignores the project's nearest-filter setting, so `status.gd` sets `canvas_item_default_texture_filter` to nearest itself (any new `Window` needs the same). `Game Font.ttf` is imported without antialiasing, hinting or subpixel positioning so the pixel text stays sharp. Regions (native px): eraser X close button (0,0,13,13), pencil drag handle (13,0,131,13), field (21,21,48,64) with a static `pandatemp.png` drawn 36 px wide inside it, white box with mood state + value (21,93,96,40), pet name (72,31,51,12) right-aligned under the two banners. Double-clicking the name swaps its `NameLabel` for a same-rect `NameEdit` LineEdit (flat, zero-margin theme styles so it looks like the label). Enter or focus loss (including closing the window) commits via `PetBrain.set_pet_name()`, and Esc reverts. All text uses `ui/Game Font.ttf` through the root Control's Theme. The window is informational only; the pet keeps running while it's open.
- `autoload/tracker.gd` — autoload singleton `Tracker` (registered under `[autoload]` in `project.godot`) exposing `active_app_changed(app: String, title: String)`, which `pet.gd` and `PetBrain` listen to. It binds UDP `127.0.0.1:47823` and, when `SPAWN_SIDECAR` is true, launches the sidecar via `OS.create_process` (`res://sidecar/tracker.py` in editor runs, `tracker.py` beside the exe in exported builds; tries `python`, then `py`; opens a console in debug builds) and kills it on exit.
- `autoload/save_manager.gd` — autoload `SaveManager`. `load_json(path)` (missing/corrupt → `{}`) and `save_json(path, data)` (writes `.tmp` then renames over the target). Persisted files live in `user://` (`%APPDATA%\Godot\app_userdata\PandaProd\`, shared by editor runs and exports): `save.json` (`{"version", "mood", "name"}`, owned by `PetBrain`) and `classification.json` (the user's custom lists, owned by `Classifier`), kept separate so resetting one never wipes the other.
- `autoload/classifier.gd` — autoload `Classifier`. Loads the `{"productive": [...], "distracting": [...]}` keyword lists from `user://classification.json` if present, else the shipped defaults in `data/classification.json`. `set_lists()` saves custom lists to `user://` and `reset_to_defaults()` deletes them; both emit `lists_changed` (meant for the future settings UI). `classify(app, title)` returns `Category.PRODUCTIVE`/`DISTRACTING`/`NEUTRAL` by case-insensitive substring match (`containsn`) on process name or window title; distracting is checked first.
- `autoload/pet_brain.gd` — autoload `PetBrain`. Holds `mood` (1–100, 50 on first run), restored exactly from `user://save.json` on launch and saved on exit plus every `AUTOSAVE_INTERVAL` (30 s). Mood drifts per minute by the current category (`PRODUCTIVE_RATE`/`NEUTRAL_RATE`/`DISTRACTING_RATE`; `RATE_SCALE` speeds it up for testing). States come from the `STATES` threshold table (≤33 Chud, ≤66 Content, else Chad). Emits `mood_changed(mood, state)` when the integer mood or state changes. Also holds `pet_name` (default `DEFAULT_NAME` "Panda", max `NAME_MAX_LENGTH` 12 chars, restored from the save). `set_pet_name()` strips it, ignores blanks, emits `name_changed` and saves immediately. It reclassifies the current app on `Classifier.lists_changed`. Autoload order matters: `Tracker`, `SaveManager`, `Classifier`, then `PetBrain`.
- `sidecar/tracker.py` — stdlib-only Python sidecar. Polls the Windows foreground window via ctypes/Win32 and sends one JSON datagram per change (`{"app", "title", "pid", "ts"}`), plus a 2 s heartbeat. Given `--parent-pid`, it ignores the pet's own window and exits when Godot dies. Can be run standalone for testing: `python sidecar/tracker.py`.
- Window transparency depends on several settings working together in `project.godot` (`window/size/transparent`, `window/per_pixel_transparency/allowed`, `viewport/transparent_background`, borderless, always-on-top), plus `get_viewport().transparent_bg = true` in `pet.gd`. Changing any of these can break the see-through desktop-pet effect.
- Mouse passthrough (click-through outside the sprite) is sketched but commented out in `pet.gd` `_ready()`.
- Rendering uses the D3D12 driver on Windows and nearest-neighbor texture filtering (pixel-art friendly). The sprite is `art/pandatemp.png` (256×256, centered at (128,128) so it fills the top of the 256×320 viewport), with the 64 px label below it.

## Conventions

- `.godot/` is an editor cache (gitignored) — don't edit it. It's safe to delete; rebuild with `godot --headless --path . --import`.
- `*.import` and `*.uid` files are generated by Godot but should stay alongside their assets/scripts; `.tscn` files reference resources by `uid://`, so when renaming/moving files prefer doing it in the Godot editor. When moving by hand (editor closed), keep the `.uid`/`.import` file with its file and fix the text `path=`/`res://` references in `.tscn`, `.import` (`source_file`) and `project.godot` (`run/main_scene`, `[autoload]`).
- `project.godot` is normally edited via the editor UI; hand edits are fine but keep the existing section format.
