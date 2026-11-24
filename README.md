# Hollow Knight modding on Apple Silicon (1.5.12620)

[中文说明](README.zh-CN.md)

Steam updated Hollow Knight to **1.5.12620**, which moved the game to Unity 6. That broke the Modding API, so mod installers like Scarab and Lumafly can't install mods for this version yet. A port is in progress at [hk-modding/api#164](https://github.com/hk-modding/api/pull/164), but it hasn't been released.

`hkmod.sh` builds that port from source and installs it on your Mac. It runs **natively on Apple Silicon**, with no Rosetta needed. It then installs mods from the official mod list.

- `install` backs up your save and game files before changing anything, and checks every file in the backup.
- One command takes you back to the unmodded game. `hkmod.sh` writes to your save folder only when you run `restore save` or `restore all`.
- Mods come from their authors' official releases. Benchwarp is built from its official source plus a small patch. This repo contains no mods and no game files.

> **Temporary solution.** Once the Unity 6 API is officially released, Scarab and Lumafly should support 1.5.12620 again. When that happens, run `./hkmod.sh restore game` (or Steam's Verify integrity), then use Scarab or Lumafly as usual.

## Quick start

1. **Open Terminal** (press Cmd+Space, type `Terminal`, press Enter).
2. **Install the tools** (one time):
   ```bash
   xcode-select --install          # Apple's command line tools (git and others); click Install in the popup
   ```
   Then install [Homebrew](https://brew.sh) (copy the command from its home page). When it finishes, run the commands it shows under **Next steps** (or close and reopen Terminal). Then run:
   ```bash
   brew install dotnet mono
   ```
3. **Get this tool and run it.** Quit Hollow Knight first. Make sure you've started the game at least once, so there is a save to back up.
   ```bash
   git clone https://github.com/yihuang0830/hollow-knight-apple-silicon-modding.git
   cd hollow-knight-apple-silicon-modding
   ./hkmod.sh doctor                                 # checks everything and tells you what's missing
   ./hkmod.sh install Benchwarp "Enemy HP Bar"       # backup + Modding API + mods (dependencies are added automatically)
   ```
4. **Play.** Start Hollow Knight from Steam. The top-left corner of the main menu should list `Modding API: 1.5.12620.0-78` and your mods.

The first `install` takes a few minutes, because it downloads and compiles the API.

**Coming back later:** in a new Terminal window, go to the tool's folder first: `cd ~/hollow-knight-apple-silicon-modding`. To update the tool, run `git pull` there.

### Requirements

| What | How to get it |
|---|---|
| A Mac with Apple Silicon (M1 or newer). Intel Macs should work but are untested. | |
| Hollow Knight **1.5.12620** from Steam, with Steam in `/Applications` | the current Steam version |
| Xcode Command Line Tools (git, lipo, …) | `xcode-select --install` |
| .NET SDK 10 or newer (tested with 11) | `brew install dotnet` |
| Mono (used by the API build) | `brew install mono` |

`./hkmod.sh doctor` checks that these are installed.

### Where things are

- **The game:** `~/Library/Application Support/Steam/steamapps/common/Hollow Knight/hollow_knight.app`. To open it in Finder: Steam → right-click Hollow Knight → Manage → Browse local files, then right-click `hollow_knight.app` → Show Package Contents.
- **The game's code** lives in `Contents/Resources/Data/Managed/`. That's where the Modding API goes. Mods go in `Managed/Mods/<Mod Name>/`.
- **Your save:** `~/Library/Application Support/unity.Team Cherry.Hollow Knight/`.
- **This tool's files:** `~/HKMod/` (backups, build files, downloads).

If your Steam library is on another drive, set the game's location first, in the same Terminal window (it lasts until you close the window):
`export HKMOD_GAME_APP="/Volumes/<drive>/SteamLibrary/steamapps/common/Hollow Knight/hollow_knight.app"`

## Commands

| Command | What it does |
|---|---|
| `./hkmod.sh doctor` | Checks the Mac, the game version and the tools |
| `./hkmod.sh install [MOD...]` | Backs up, builds and installs the Modding API, and optionally installs mods. You can run it again later; it rebuilds from a vanilla backup. |
| `./hkmod.sh install-mod "Mod Name" ...` | Installs mods and their dependencies from the official ModLinks. Running it again for an installed mod reinstalls it (the old copy goes to `~/HKMod/replaced/`). |
| `./hkmod.sh remove-mod "Mod Name" ...` | Removes mods (they are moved to `~/HKMod/replaced/<date>/`). Dependencies such as Satchel stay installed. |
| `./hkmod.sh list-mods [filter]` | Lists every mod in ModLinks and marks the tested ones |
| `./hkmod.sh status` | Shows what's installed, the backups, and the disk space used |
| `./hkmod.sh backup` | Takes an extra backup |
| `./hkmod.sh restore game [DIR]` | **Back to vanilla.** Puts back the vanilla game files from the newest vanilla backup (or from `DIR`), so the Modding API is gone. Your save is not touched. |
| `./hkmod.sh restore save [DIR] [--yes]` | Puts back the save from the newest backup, or from `DIR`. Progress made after that backup is lost, so it asks first. |
| `./hkmod.sh restore all [DIR] [--yes]` | Both of the above |
| `./hkmod.sh launch [--rosetta]` | Starts the game through Steam. With `--rosetta`, it starts it under Rosetta instead, as a fallback (open Steam first). |
| `./hkmod.sh clean` | Deletes build files (about 600 MB), the download cache, interrupted backups and leftovers of interrupted restores. Backups, `~/HKMod/replaced/` and `~/HKMod/pre-restore-*/` are kept; delete those by hand when you no longer need them. |

Mod names are the English names from ModLinks, case-sensitive (for example `"Enemy HP Bar"`). Use `list-mods` to find them. `help` and `--version` are also available.

## Mods

`install-mod` downloads each mod from the link in the official [ModLinks](https://github.com/hk-modding/modlinks) list and checks its SHA-256. You can also install mods yourself: unzip a mod's release into `Managed/Mods/<Mod Name>/`.

Tested on 1.5.12620 (Apple M4, native):

| Mod | Status | Authors |
|---|---|---|
| [Benchwarp](https://github.com/homothetyhk/HollowKnight.BenchwarpMod) | ✅ The official 3.2.6.1 release fails to load on 1.5.12620 (TypeLoadException), so `hkmod.sh` builds it from source with [a small patch](patches/benchwarp/) | homothetyhk |
| [Enemy HP Bar](https://github.com/ygsbzr/Enemy-HP-Bars) | ✅ official release works | ricardosouzag, ygsbzr, Clazex |
| [Satchel](https://github.com/PrashantMohta/Satchel) (library; Enemy HP Bar needs it) | ✅ official release works | Dandy, Mulhima, Ruttie |

Other mods may or may not work on 1.5.12620. Many old mods hook game code that changed in this version. If a mod doesn't load, `~/Library/Application Support/unity.Team Cherry.Hollow Knight/ModLog.txt` says why. Remove it with `./hkmod.sh remove-mod`.

## Undoing everything

```bash
./hkmod.sh restore game     # vanilla game files; save untouched
```

Another option: Steam → Hollow Knight → Properties → Installed Files → **Verify integrity of game files**. It also turns the mods off.

- **Backups.** They're stored in `~/HKMod/backups/<date>/`, about 65 MB each. `install` takes a new one every time.
- **`restore save` picks the newest backup,** from your most recent `install` or `backup`. To go back further, pass that backup's folder: `./hkmod.sh restore save ~/HKMod/backups/<folder>`. `./hkmod.sh status` lists the folders.
- **Only backups taken while the game was vanilla** (the first `install`) can be used for `restore game`. Backups taken while the API was installed are marked `modded` in `status` and are only good for `restore save`.
- **`restore game DIR`** also accepts a copy of the `Managed` folder you made yourself: pass the copied `Managed` folder, or the folder that contains it. It must hold the complete, unmodified 1.5.12620 files; the tool checks this.
- **Nothing is overwritten without a copy.** A restore first copies and checks the backup, then moves your current files to `~/HKMod/pre-restore-<date>/`.
- **After a Steam update,** `restore game` refuses to put back older game files. Use Steam's Verify integrity instead.
- **Your save stays readable by the unmodded game.** The API saves mod data in separate files (`*.GlobalSettings.json`, `user*.modded.json`), and `user1.dat` stays in the vanilla format.
- **Steam Cloud.** If Steam reports a Cloud conflict after a `restore save`, choose the LOCAL files.

## How it works

1. **Backup.** Copies the save folder and the game's `Managed/` folder to `~/HKMod/backups/`, then checks every file's hash.
2. **Build the API.** Clones the Unity 6 port of the Modding API at a pinned commit, compiles it against your copy of the game's own assemblies, and makes the native scene repacker library universal (x86_64 + arm64).
3. **Install.** Copies the API into `Managed/`. The game executable is never changed.
4. **Mods.** Downloads each mod from ModLinks and checks its SHA-256. Benchwarp, which needs a patch, is built from source with the patch in `patches/`.

The API source is pinned to [`yihuang0830/api@13eee97`](https://github.com/yihuang0830/api/tree/13eee977fd9da125df5b51458a2f846b497e9d84). That is PR #164 plus [SFGrenade/api#6](https://github.com/SFGrenade/api/pull/6), which does two things:
- It restores the vendored MonoMod patcher and HookGen. Without that, the current PR head fails to build and loads no mods.
- It fixes the `ObjectPool.CreatePool` patch.

See [docs/TECHNICAL.md](docs/TECHNICAL.md) for details, including why native Apple Silicon works now.

## Settings (environment variables)

Set them with `export NAME=value` in the same Terminal window before running `./hkmod.sh`. They last until the window is closed.

| Variable | Default | What it's for |
|---|---|---|
| `HKMOD_GAME_APP` | `~/Library/Application Support/Steam/steamapps/common/Hollow Knight/hollow_knight.app` | where the game is |
| `HKMOD_SAVE_DIR` | `~/Library/Application Support/unity.Team Cherry.Hollow Knight` | where the save is |
| `HKMOD_HOME` | `~/HKMod` | backups, build files, download cache |
| `HKMOD_FORCE` | `0` | set to `1` to try on a game version other than 1.5.12620 |
| `HKMOD_API_REPO` / `HKMOD_API_REF` | `https://github.com/yihuang0830/api.git` @ `13eee97` | which Modding API source to build |
| `HKMOD_BENCHWARP_REPO` / `HKMOD_BENCHWARP_REF` | the Benchwarp repo @ `1ac5a3c` (3.2.6.1) | which Benchwarp source to build |
| `HKMOD_MODLINKS_URL` | `https://raw.githubusercontent.com/hk-modding/modlinks/main/ModLinks.xml` | the mod list |

## Troubleshooting

- **"Application was not launched through Steam! Shutting down"**: start the game from Steam or with `./hkmod.sh launch`. Don't open `hollow_knight.app` directly.
- **"Hollow Knight is running"**: quit the game before running any command.
- **Mods missing from the main menu**: check `~/Library/Application Support/unity.Team Cherry.Hollow Knight/ModLog.txt` and `~/Library/Logs/Team Cherry/Hollow Knight/Player.log`.
- **The build failed**: the last lines of the log are printed. Full logs are in `~/HKMod/build/api-build.log` and `~/HKMod/build/benchwarp-build.log`. Run `./hkmod.sh doctor` first.
- **"game files are neither vanilla 1.5.12620 nor this Modding API"**: the game has a different mod loader or is damaged. Run Steam's Verify integrity, then `./hkmod.sh install` again.
- **After a Steam update**: mods stop loading, which is normal. Run `./hkmod.sh install` again if the new game version is still 1.5.12620, or wait for an updated API.

## Credits

- [hk-modding/api](https://github.com/hk-modding/api) and the Unity 6 port by SFGrenade and contributors (MIT)
- [MonoMod](https://github.com/MonoMod/MonoMod) (MIT)
- [Benchwarp](https://github.com/homothetyhk/HollowKnight.BenchwarpMod) by homothetyhk (LGPL-2.1). `hkmod.sh` builds it locally from the official source with our patch.
- Other mod authors: see the table above. Their mods are downloaded from their own releases.
- Hollow Knight © Team Cherry. This is an unofficial community tool. It contains no game files.

## License

The scripts and docs are under the [MIT License](LICENSE). The Benchwarp patch in `patches/benchwarp/` is a modification of Benchwarp and is under the [LGPL-2.1](patches/benchwarp/LICENSE), like Benchwarp itself.
