PandaProd - a desktop panda that reacts to what you're working on
=====================================================================

SETUP
1. Install Python 3 from https://www.python.org/downloads/
   In the installer, tick "Add python.exe to PATH".
2. Extract this whole zip into a folder. PandaProd.exe and tracker.py
   must stay together in the same folder.
3. Double-click PandaProd.exe. Windows may say "Windows protected your PC"
   because the app isn't signed: click "More info", then "Run anyway".

USING IT
- The panda lives along the bottom of your screen. Hold left-click on him
  to pick him up by the tail, swing him around, and let go to throw him.
- Right-click him to open his status window: mood, name, sleep mode,
  settings, achievements and help (the "?" tab).
- His mood rises while you use productive apps and drops on distracting
  ones. Both lists start empty: add your own apps and sites in the status
  window's "!" tab (e.g. "Code" or "YouTube"). Until you do, everything
  counts as neutral and his mood slowly drops.
- To quit: click him, then press Esc.

NOTES
- This is a demo build: his mood changes about 30 times faster than
  normal, so you can watch him react.
- His save is kept in %APPDATA%\Godot\app_userdata\PandaProd
  (delete that folder to start over).
- Privacy: the app only looks at the name and title of the window you're
  using, on your own machine. Nothing about the windows you use is saved,
  and nothing is sent over the internet.
