# 在 Apple Silicon Mac 上给 Hollow Knight 装 mod（1.5.12620）

[English](README.md) | **简体中文**

Steam 版 Hollow Knight 更新到 **1.5.12620** 后，游戏换成了 Unity 6，原来的 Modding API 不能用了，Scarab、Lumafly 这些安装器暂时也装不了这个版本的 mod。新版 API 的适配正在 [hk-modding/api#164](https://github.com/hk-modding/api/pull/164) 里进行，但还没有正式发布。

`hkmod.sh` 会从源码编译这个新版 API 并装到你的 Mac 上。它在 **Apple Silicon 上原生运行，不需要 Rosetta**。之后再从官方 mod 列表安装 mod。

- `install` 在改动任何东西之前，会先备份存档和游戏文件，并逐个核对备份。
- 一条命令就能恢复原版游戏。只有在你运行 `restore save` 或 `restore all` 时，`hkmod.sh` 才会写入存档文件夹。
- mod 都来自作者的官方发布版本，其中 Benchwarp 是用官方源码加一个小补丁编译的。这个 repo 里没有任何 mod 或游戏文件。

> **这是过渡期的方案。** 等 Unity 6 版 API 正式发布后，Scarab 和 Lumafly 应该会重新支持 1.5.12620。到时先运行 `./hkmod.sh restore game`（或在 Steam 里验证完整性），再照常使用 Scarab 或 Lumafly。

## 快速开始

1. **打开“终端”**（按 Cmd+空格，输入 `Terminal`，回车）。
2. **安装工具**（只需一次）：
   ```bash
   xcode-select --install          # 苹果的命令行工具（包含 git 等），在弹窗里点“安装”
   ```
   然后安装 [Homebrew](https://brew.sh)（从它主页复制安装命令）。装完后，运行它在 **Next steps** 下面给出的那几行命令（或者关掉终端重新打开），再运行：
   ```bash
   brew install dotnet mono
   ```
3. **下载并运行本工具。** 先退出 Hollow Knight。确保你至少启动过一次游戏，这样才有存档可以备份。
   ```bash
   git clone https://github.com/yihuang0830/hollow-knight-apple-silicon-modding.git
   cd hollow-knight-apple-silicon-modding
   ./hkmod.sh doctor                                 # 检查环境，告诉你还缺什么
   ./hkmod.sh install Benchwarp "Enemy HP Bar"       # 备份 + 安装 Modding API + 装 mod（依赖会自动装上）
   ```
4. **开玩。** 从 Steam 启动游戏。主菜单左上角应该会显示 `Modding API: 1.5.12620.0-78` 和你装的 mod。

第一次运行 `install` 需要几分钟，因为要下载并编译 API。

**以后再用时**：新开终端窗口后，先回到本工具的文件夹：`cd ~/hollow-knight-apple-silicon-modding`。想更新本工具，就在那里运行 `git pull`。

### 需要准备

| 需要什么 | 怎么装 |
|---|---|
| Apple Silicon（M1 或更新）的 Mac。Intel Mac 理论上可以，但没测试过。 | |
| Steam 版 Hollow Knight **1.5.12620**，且 Steam 装在 `/Applications` 里 | Steam 上的当前版本 |
| Xcode 命令行工具（git、lipo 等） | `xcode-select --install` |
| .NET SDK 10 或更新（已在 11 上测试） | `brew install dotnet` |
| Mono（编译 API 时要用） | `brew install mono` |

`./hkmod.sh doctor` 会检查这些是否已安装。

### 文件都在哪

- **游戏**：`~/Library/Application Support/Steam/steamapps/common/Hollow Knight/hollow_knight.app`。在访达里打开的方法：Steam → 右键 Hollow Knight → 管理 → 浏览本地文件，再右键 `hollow_knight.app` → 显示包内容。
- **游戏代码**在 `Contents/Resources/Data/Managed/` 里，Modding API 就装在这里。mod 放在 `Managed/Mods/<Mod 名>/`。
- **存档**：`~/Library/Application Support/unity.Team Cherry.Hollow Knight/`。
- **本工具的文件**：`~/HKMod/`（备份、编译文件、下载缓存）。

如果你的 Steam 游戏库在别的硬盘上，先在同一个终端窗口里指定游戏位置（关掉窗口后失效）：
`export HKMOD_GAME_APP="/Volumes/<硬盘名>/SteamLibrary/steamapps/common/Hollow Knight/hollow_knight.app"`

## 命令

| 命令 | 作用 |
|---|---|
| `./hkmod.sh doctor` | 检查电脑、游戏版本和所需工具 |
| `./hkmod.sh install [MOD...]` | 备份，编译并安装 Modding API，可以顺便装 mod。之后可以重复运行，它会从原版备份重新编译。 |
| `./hkmod.sh install-mod "Mod 名" ...` | 从官方 ModLinks 安装 mod，依赖会一起装。对已安装的 mod 再运行一次会重新安装（旧的挪到 `~/HKMod/replaced/`）。 |
| `./hkmod.sh remove-mod "Mod 名" ...` | 删除 mod（挪到 `~/HKMod/replaced/<日期>/`）。Satchel 这类依赖会保留。 |
| `./hkmod.sh list-mods [关键词]` | 列出 ModLinks 里的所有 mod，并标出测试过的 |
| `./hkmod.sh status` | 查看已安装的内容、备份和占用的磁盘空间 |
| `./hkmod.sh backup` | 额外再备份一次 |
| `./hkmod.sh restore game [目录]` | **恢复原版**：用最新的原版备份（或指定目录）换回原版游戏文件，Modding API 随之失效。不动存档 |
| `./hkmod.sh restore save [目录] [--yes]` | 恢复最新备份里的存档（或指定目录里的）。备份之后的进度会丢失，所以会先问你确认 |
| `./hkmod.sh restore all [目录] [--yes]` | 以上两项都做 |
| `./hkmod.sh launch [--rosetta]` | 通过 Steam 启动游戏；加 `--rosetta` 则直接用 Rosetta 启动，作为备用方案（要先打开 Steam） |
| `./hkmod.sh clean` | 删除编译文件（约 600 MB）、下载缓存、中断的备份，以及中断的恢复留下的临时文件。备份、`~/HKMod/replaced/` 和 `~/HKMod/pre-restore-*/` 会保留，不需要时可以手动删除 |

mod 名是 ModLinks 里的英文名（例如 `"Enemy HP Bar"`，不是“敌人血条”），要完全一致，区分大小写。不确定的话先用 `list-mods` 查。另外还有 `help` 和 `--version`。

## Mod

`install-mod` 会按官方 [ModLinks](https://github.com/hk-modding/modlinks) 列表里的链接下载 mod，并核对 SHA-256。你也可以自己装：把 mod 的发布包解压到 `Managed/Mods/<Mod 名>/` 就行。

在 1.5.12620 上测试过（Apple M4，原生运行）：

| Mod | 状态 | 作者 |
|---|---|---|
| [Benchwarp](https://github.com/homothetyhk/HollowKnight.BenchwarpMod) | ✅ 官方 3.2.6.1 版在 1.5.12620 上加载失败（TypeLoadException），`hkmod.sh` 会用[一个小补丁](patches/benchwarp/)从源码编译 | homothetyhk |
| [Enemy HP Bar](https://github.com/ygsbzr/Enemy-HP-Bars)（敌人血条） | ✅ 官方版直接可用 | ricardosouzag、ygsbzr、Clazex |
| [Satchel](https://github.com/PrashantMohta/Satchel)（前置库，Enemy HP Bar 需要） | ✅ 官方版直接可用 | Dandy、Mulhima、Ruttie |

其他 mod 在 1.5.12620 上不一定能用，因为很多旧 mod 挂钩的游戏代码在这个版本里改了。mod 加载不了的话，看 `~/Library/Application Support/unity.Team Cherry.Hollow Knight/ModLog.txt`，再用 `./hkmod.sh remove-mod` 删掉。

## 恢复原版

```bash
./hkmod.sh restore game     # 恢复原版游戏文件，不动存档
```

另一种方法：Steam → Hollow Knight → 属性 → 已安装文件 → **验证游戏文件的完整性**，也能关掉 mod。

- **备份**：放在 `~/HKMod/backups/<日期>/`，每份约 65 MB。每次 `install` 都会新建一份。
- **`restore save` 用的是最新的备份**，也就是你最近一次 `install` 或 `backup` 时的存档。想恢复更早的，就指定那个备份的目录：`./hkmod.sh restore save ~/HKMod/backups/<目录名>`。`./hkmod.sh status` 会列出所有备份目录。
- **只有游戏还是原版时做的备份**（第一次 `install` 时）能用于 `restore game`。装了 API 之后做的备份在 `status` 里标为 `modded`，只能用于 `restore save`。
- **`restore game 目录`** 也接受你自己复制的 `Managed` 文件夹：直接传这个 `Managed` 文件夹，或包含它的文件夹都可以。里面必须是完整、未修改的 1.5.12620 文件，工具会检查。
- **不会在没有副本的情况下覆盖任何东西。** 恢复时会先复制并核对备份，再把你当前的文件挪到 `~/HKMod/pre-restore-<日期>/`。
- **Steam 更新游戏后**，`restore game` 会拒绝恢复旧版本的游戏文件，这时请用 Steam 的验证完整性。
- **原版游戏照样能读你的存档。** API 把 mod 的数据存在单独的文件里（`*.GlobalSettings.json`、`user*.modded.json`），`user1.dat` 保持原版格式。
- **Steam 云存档**：`restore save` 之后如果 Steam 提示云存档冲突，选“本地”文件。

## 原理

1. **备份**：把存档文件夹和游戏的 `Managed/` 文件夹复制到 `~/HKMod/backups/`，并核对每个文件的哈希。
2. **编译 API**：下载固定版本的 Unity 6 版 Modding API 源码，用你电脑上的游戏文件编译，并把原生场景库合并成同时支持 x86_64 和 arm64 的版本。
3. **安装**：把 API 复制进 `Managed/`。游戏的可执行文件始终不改。
4. **装 mod**：从 ModLinks 下载每个 mod，并核对 SHA-256。需要补丁的 Benchwarp 会用 `patches/` 里的补丁从源码编译。

API 源码固定在 [`yihuang0830/api@13eee97`](https://github.com/yihuang0830/api/tree/13eee977fd9da125df5b51458a2f846b497e9d84)，也就是 PR #164 加上 [SFGrenade/api#6](https://github.com/SFGrenade/api/pull/6)。后者做了两件事：
- 恢复内置的 MonoMod patcher 和 HookGen。没有它，PR 当前的版本编译不过，也加载不了 mod。
- 修正 `ObjectPool.CreatePool` 补丁。

技术细节（包括为什么现在 Apple Silicon 能原生运行）见 [docs/TECHNICAL.md](docs/TECHNICAL.md)（英文）。

## 设置（环境变量）

在运行 `./hkmod.sh` 之前，在同一个终端窗口里用 `export 变量名=值` 设置，关掉窗口后失效。

| 变量 | 默认值 | 用途 |
|---|---|---|
| `HKMOD_GAME_APP` | `~/Library/Application Support/Steam/steamapps/common/Hollow Knight/hollow_knight.app` | 游戏位置 |
| `HKMOD_SAVE_DIR` | `~/Library/Application Support/unity.Team Cherry.Hollow Knight` | 存档位置 |
| `HKMOD_HOME` | `~/HKMod` | 备份、编译文件、下载缓存 |
| `HKMOD_FORCE` | `0` | 设为 `1` 可在 1.5.12620 以外的游戏版本上强行尝试 |
| `HKMOD_API_REPO` / `HKMOD_API_REF` | `https://github.com/yihuang0830/api.git` @ `13eee97` | 编译哪个 Modding API 源码 |
| `HKMOD_BENCHWARP_REPO` / `HKMOD_BENCHWARP_REF` | Benchwarp 仓库 @ `1ac5a3c`（3.2.6.1） | 编译哪个 Benchwarp 源码 |
| `HKMOD_MODLINKS_URL` | `https://raw.githubusercontent.com/hk-modding/modlinks/main/ModLinks.xml` | mod 列表 |

## 常见问题

- **提示 "Application was not launched through Steam! Shutting down"**：要从 Steam 启动，或用 `./hkmod.sh launch`，不要直接打开 `hollow_knight.app`。
- **提示 "Hollow Knight is running"**：运行任何命令前先退出游戏。
- **主菜单上没有 mod**：查看 `~/Library/Application Support/unity.Team Cherry.Hollow Knight/ModLog.txt` 和 `~/Library/Logs/Team Cherry/Hollow Knight/Player.log`。
- **编译失败**：屏幕上会显示日志的最后几行，完整日志在 `~/HKMod/build/api-build.log` 和 `~/HKMod/build/benchwarp-build.log`。先运行 `./hkmod.sh doctor` 检查环境。
- **提示 "game files are neither vanilla 1.5.12620 nor this Modding API"**：游戏装了别的 mod 加载器，或者文件损坏了。先在 Steam 里验证完整性，再重新运行 `./hkmod.sh install`。
- **Steam 更新后**：mod 会失效，这是正常的。如果新的游戏版本还是 1.5.12620，重新运行 `./hkmod.sh install` 即可；否则要等 API 更新。

## 致谢

- [hk-modding/api](https://github.com/hk-modding/api)，以及 SFGrenade 等人做的 Unity 6 适配（MIT）
- [MonoMod](https://github.com/MonoMod/MonoMod)（MIT）
- [Benchwarp](https://github.com/homothetyhk/HollowKnight.BenchwarpMod)，作者 homothetyhk（LGPL-2.1）。`hkmod.sh` 用官方源码加我们的补丁在本地编译。
- 其他 mod 作者见上表，mod 都从他们自己的发布页下载。
- Hollow Knight © Team Cherry。这是非官方的社区工具，不包含任何游戏文件。

## 许可证

脚本和文档使用 [MIT 许可证](LICENSE)。`patches/benchwarp/` 里的补丁是对 Benchwarp 的修改，和 Benchwarp 一样使用 [LGPL-2.1](patches/benchwarp/LICENSE)。
