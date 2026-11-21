# First-run bootstrap — what the player sees

Target: a player taps **Shaiya Farlords**, and ends up at the game's login screen
without ever seeing Wine, a container, a config file, or a command prompt.

## Screens

### 1. Engine setup (once, ~20 s)
Silent. Installs the bundled Wine runtime into app storage and creates the
container. Only visible if something fails.

    Preparing the game engine…
    [############------------]  62 %

### 2. Game files (once, 2–15 min)
Two paths, decided by what it finds on the phone:

| Found | Action | Time |
|---|---|---|
| `/sdcard/ShaiyaMobile/ShaiyaFarlords-Mobile.zip` | extract in place, verify, delete zip | 5–15 min |
| `/sdcard/ShaiyaMobile/ShaiyaFarlordsClient/` | use as-is | 5 s |
| neither | offer download of the 2.52 GB pack | 10 min–2 h |
| zip truncated / wrong hash | say so, offer re-download | — |

Copy for the extract path:

    Installing game files…
    Unpacking data.saf (4.4 GB)…
    [########----------------]  38 %
    4.1 GB free after install

### 3. Ready
Shortcut created, game launched. Subsequent taps skip straight to the login
screen — screens 1 and 2 never appear again.

## Rules

- **Never** ask the player to install anything else.
- If storage looks insufficient, say so **before** extracting, not at 80 %.
- Verify the zip's size against the expected byte count before extracting;
  a truncated MTP copy is the single most likely field failure.
- Peak space needed: 7.1 GB (2.52 zip + 4.56 game + 0.5 prefix). Require 8 GB.
- Extracted `data.saf` is 4.56 GB — will not fit on a FAT32 SD card, so the
  game directory stays in internal storage.
- Everything is resumable: a killed app re-enters at the step it stopped on.

## Fixed paths

    /sdcard/ShaiyaMobile/ShaiyaFarlords-Mobile.zip     source zip
    /sdcard/ShaiyaMobile/ShaiyaFarlordsClient/         installed game
    <app files>/wine/                                  bundled runtime
    <app files>/imagefs/                               container

The game directory is outside app storage on purpose: it survives reinstall and
uninstall, so a player updating the APK doesn't re-download 2.52 GB.

## Failure messages (plain language, no jargon)

| What broke | What the player reads |
|---|---|
| no zip, no folder | "Game files not found. Download them now? (2.5 GB)" |
| zip is 2.3 GB instead of 2.52 | "The game file was copied incompletely. Please copy it again." |
| < 8 GB free | "This phone needs about 8 GB free. It has 3.2 GB." |
| engine failed | "Setup failed. Restart the app to try again." + code |
