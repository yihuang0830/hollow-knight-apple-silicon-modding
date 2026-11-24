# Technical notes

These were tested on an Apple M4 running macOS 26.4.1, with Hollow Knight 1.5.12620 (Unity 6000.0.61f1) from Steam. Builds used .NET SDK 11.0.100 and Homebrew mono 6.14.1.

## Status of the Unity 6 Modding API (hk-modding/api#164)

The port lives on [SFGrenade/api `hk-beta-branch-unity-6-update`](https://github.com/SFGrenade/api/tree/hk-beta-branch-unity-6-update). As of 2026-11-24, its two most recent commits (a1e3932, 837b267, 2026-11-23) switch from vendored MonoMod code to NuGet packages. That breaks it in two ways:

1. **The build fails.** NuGet has no MonoMod v25 HookGen package; the latest `MonoMod.RuntimeDetour.HookGen` is 22.7.31.1, which targets the v22 RuntimeDetour API. Without the vendored HookGen, `MonoMod.RuntimeDetour.HookGen.exe` is never built and PostBuild fails with "Cannot open assembly".
2. **No mods load.** NuGet `MonoMod.Patcher 25.0.1` relinks the nested BCL types `Dictionary<K,V>.Enumerator`, `.KeyCollection` and `.ValueCollection` to netstandard 2.1, but drops their declaring type. The result is top-level TypeRefs such as `Enumerator` in `netstandard`. At startup this throws:
   ```
   TypeLoadException: Could not resolve type with token 010002e7 from typeref
   (expected class 'Enumerator' in assembly 'netstandard, Version=2.1.0.0, ...')
     at Modding.ModLoader.<LoadModsInit>d__16.MoveNext()
   ```

The vendored patcher at 468f579 emits the correct nested reference (``Dictionary`2/Enumerator`` in mscorlib).

[SFGrenade/api#6](https://github.com/SFGrenade/api/pull/6) restores the vendored projects. It also fixes the `ObjectPool.CreatePool` patch: 1.5.12620 only has `CreatePool(GameObject, int, bool runInitialisation = false)`, but the patch targeted a 2-arg overload, so MonoMod added a dead method with a dangling `orig_` call instead of patching the real one. `hkmod.sh` builds that PR's head, commit 13eee97.

## Apple Silicon works natively

An earlier comment on #164 reported `mprotect returned EACCES` when running natively on arm64. That test used the **MonoMod v22** build. The upgrade to **MonoMod v25** (e533f2c) came later, and v25 runs natively on arm64:

- `vmmap` shows `Code Type: ARM64`.
- A test mod placed a `Hook` and an `ILHook` on `TeamCherry.Localization.Language.Get`, called it, then unhooked it, and every step passed.
- Benchwarp, Enemy HP Bar and Satchel all apply their detours.
- No EACCES.

The same build also runs under Rosetta (`arch -x86_64`).

The only native piece is `libunityscenerepacker.dylib`, used for preloading. The package ships separate x64 and arm64 builds. The project's CI merges them with `lipo`, but a local `--runtime osx-x64` build copies only the x64 one. `hkmod.sh` merges them itself.

## Old mods and the language system

In 1.5.12620 the `Language` class moved to `TeamCherry.Localization.Language` (in `TeamCherry.Localization.dll`). The API keeps a compatibility shim for `Language.Language`, but HookGen only emits `On.TeamCherry.Localization.Language`, not `On.Language.Language`. Mods that hook `On.Language.Language.*` fail with a TypeLoadException and must be rebuilt.

`EventRegister.SendEvent(string)` also changed to `SendEvent(string, GameObject = null)`. This is a binary break only: recompiling fixes it.

## Benchwarp patch

[`patches/benchwarp/`](../patches/benchwarp/) is about 20 lines, applied to Benchwarp 3.2.6.1:

- Replace `Language.Language.Get`/`CurrentLanguage` and `On.Language.Language.DoSwitch` with their `TeamCherry.Localization.Language` equivalents, and `LanguageCode` with `TeamCherry.Localization.LanguageCode`.
- csproj changes:
  - reference `TeamCherry.Localization.dll`, `MMHOOK_TeamCherry.Localization.dll` and the game's `netstandard.dll`;
  - set `FrameworkPathOverride` to `$(HollowKnightRefs)`, a copy of the modded Managed folder (`hkmod.sh` uses `~/HKMod/build/refs`). Unity 6's `ImageConversion.LoadImage` has `ReadOnlySpan<byte>` overloads, and the net472 reference mscorlib lacks Span.

Static checks on the result:
- every reference resolves against the modded game assemblies;
- the reflection target `GameManager.sceneLoad` still exists;
- all 49 bench scenes exist.

## Building by hand on macOS

```bash
git clone https://github.com/yihuang0830/api.git && cd api && git checkout 13eee97
# Vanilla/ (in the repo root) = the files of an unmodified game's Managed folder. Leave out leftovers
# from earlier mod installs: MMHOOK_*, MonoMod.*, Mono.Cecil*, *.xml, Assembly-CSharp.dll.v*,
# libunityscenerepacker.dylib, System.ValueTuple.dll, README.md, and the Mods/ folder.
dotnet build PrePatcher  -o PrePatcher/Output  -p:Configuration=Release
dotnet build PostPatcher -o PostPatcher/Output -p:Configuration=Release
dotnet build TeamCherry.Localization --runtime osx-x64 -p:Configuration=Release -p:CopyDir=
dotnet build Assembly-CSharp         --runtime osx-x64 -p:Configuration=Release -p:CopyDir=
lipo -create -output OutputFinal/libunityscenerepacker.dylib \
  Assembly-CSharp/packages/unityscenerepacker/*/runtimes/osx-{x64,arm64}/native/libunityscenerepacker.dylib
```

- `mono` must be on PATH.
- Build each project separately. Building the `.sln` with `--runtime` fails with NETSDK1134.
- `-p:CopyDir=` matters: by default the build copies its output to a Linux Steam path (`~/.local/share/Steam/...`).

## Launching

The game must be started through Steam. Otherwise it quits with "Application was not launched through Steam!". The Rosetta fallback (`./hkmod.sh launch --rosetta`) runs the executable with `arch -x86_64` and sets `SteamAppId=367520` and `SteamGameId=367520`. Steam must be running.

## How hkmod.sh recognises vanilla files and backups

- **Vanilla:** `Assembly-CSharp.dll` and `TeamCherry.Localization.dll` match the SHA-256 of the unmodified 1.5.12620 files:
  - `Assembly-CSharp.dll`: `7ea3415ccc5c1b7c7101d958043d564de19d4be2cd37283ced5d63770f2cfd78`
  - `TeamCherry.Localization.dll`: `a98c28d352cbcdd9d291fd998ece9a42fba6811e52a79e4ba118a9cc41a386cc`
- **Modded:** `Assembly-CSharp.dll` contains `ModHooks`, which means this Modding API is installed.
- **Unknown:** anything else (another mod loader, or damaged files). `install` and `restore game` refuse to work with these.
- **`HKMOD_FORCE=1`** (for other game versions): files count as vanilla when `Assembly-CSharp.dll` is larger than 1 MB, contains no `ModHooks`, and `TeamCherry.Localization.dll` contains no `MonoMod`.
- **Backups** are written to `~/HKMod/backups/.partial-<ts>`, verified, and only then renamed to `<ts>` with a `BACKUP_INFO` file (`state`, `game_version`, `complete=1`). Interrupted backups are never used.
- **`restore game`** also checks that the backup has every game file present in the live `Managed` folder (API files and leftovers excepted).
- **Restores** copy and verify the backup next to the live folder first, then swap it in, so the live folder is never half-written.
