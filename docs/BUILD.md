# Fotufilm Windows 构建与打包

> 本文件面向维护者。下面出现的 `F:\Futo\...` 是本机的工具链与工作区布局；
> 仓库本身的脚本都接受 `-Source` / `-AotDir` / `-HalideRoot` 参数，换台机器改参数即可。

## 工作区布局

```
F:\Futo\                    维护者工作区（不在仓库里）
├─ toolchain\                Swift 6.2、Flutter 3.41.7、Halide、vcpkg
├─ m0\aot-windows\           生成好的 Halide AOT 核
├─ work\1.15\                scripts\sync-upstream.ps1 重放出来的树
└─ dist\                     产物
```

一条命令产出可直接分发的单文件 exe。

```
F:\Futo\build.cmd                    完整构建（引擎 + 界面 + 单文件）
F:\Futo\build.cmd -SkipEngine        引擎没改时，跳过 Swift 这一步（约 25 秒）
F:\Futo\build.cmd -Algo lzms         更小的 exe（约 1.9x 压缩），首次解包更慢

跟随上游时按版本目录构建（不覆盖 upstream\）：

  .\scripts\build.ps1 -Source work\1.15 -Version 1.15 -AotDir build\aot -Elevate

-Source    要构建的树，默认 F:\Futo\upstream
-Version   上游版本号，默认读 version.env（上游常忘记随发布更新，同步后显式给）
-AotDir    AOT 核目录，默认 F:\Futo\m0\aot-windows
-Elevate   以管理员重开：Flutter 的插件符号链接在非管理员下会因缺少特权失败
```

## 输出

| 路径 | 内容 |
|---|---|
| `dist\Fotufilm-<版本>-win64.exe` | 单文件发行版，双击即用 |
| `dist\app\` | 解包后的运行时目录（排查问题时直接运行里面的 `fotufilm.exe`） |
| `dist\build-<时间>.log` | 每次构建的完整日志 |

## 构建步骤

1. **引擎** `swift build -c release --product FotufilmHost`
   需要 `SDKROOT` 指向 Swift 的 `Windows.sdk`、`FOTUFILM_AOT_DIR` 指向 AOT 核目录（脚本已设）。
2. **界面** `flutter build windows --release --no-pub`
3. **暂存** 把 `FotufilmHost.dll` 改名为 `libfotufilm.dll`，连同 32 个 Swift 运行时 DLL 与 `data\` 复制到 `dist\app`。
4. **打包** `packaging\bin\fotufilm-pack.exe` 把 `dist\app` 压进启动器存根，得到单文件。

## 单文件怎么工作

exe = 启动器存根 + 压缩归档。第一次运行时解包，然后启动 `fotufilm.exe`；
之后每次只做一次目录存在性检查，直接启动。

解包位置按顺序尝试，第一个能写的就是最终位置：

1. `--runtime-dir <路径>` 或环境变量 `FOTUFILM_RUNTIME_DIR`
2. `--portable` → exe 旁边的 `Fotufilm.runtime\<归档哈希>\`
3. `%LOCALAPPDATA%\Fotufilm\runtime\<归档哈希>\`（默认）
4. exe 旁边的 `Fotufilm.runtime\<归档哈希>\`
5. `%TEMP%\Fotufilm\<归档哈希>\`

用户目录被策略锁死、exe 放在只读介质、U 盘里换机器，都会自动落到下一档，不会再弹错误框。

- 归档哈希参与路径，所以换新版本会解包到新目录，不会混用旧 DLL。
- `--clean` 清掉旧版本留下的运行时目录。
- `--extract-only` 只解包并打印路径，不启动。
- 解包中途显示进度窗口；两个实例同时启动时，后一个等前一个 15 秒，仍不成就自己解包到独立临时目录再改名就位，结果一致。
- 排查时设 `FOTUFILM_LAUNCH_LOG=<日志路径>`，启动器会写每一步的路径与 Win32 错误码。
## 压包工具

`packaging\launcher.cpp` 一个源文件编出两个程序：

```
packaging\build-tools.ps1     -> bin\fotufilm-launch.exe（存根）
                               bin\fotufilm-pack.exe   （打包器）
packaging\selftest.ps1        往返自测（含 40 MB 随机块、中文名、空文件、坏包检测）
```

压缩走 Windows 自带的 Cabinet `Compress` API。实测：

| 算法 | 压缩比 | 打包 285 MB | 首次解包 |
|---|---|---|---|
| `xpress`（默认） | 2.95x | 1.0 s | ≈12 s |
| `lzms` | 4.4x | 23 s | ≈30 s |
| `store` | 1.0x | 0.3 s | ≈5 s |

## 汉化维护

```
tools\zh-catalogue.json   控件目录的标题/说明（运行时由 Catalogue.load 套用）
tools\zh-ui.json          界面字面量（按归一化模板匹配，{0} {1} 是插值占位）
tools\apply-zh.cjs        把上面两张表写回 zh.dart 与源码
```

改完跑一次（工作树由 -Source 指定）：

```
node port\i18n\apply-zh.cjs --root work\1.15 --apply   # 重放：写回 zh.dart 与 lib/**/*.dart
node port\i18n\check-zh.cjs --root work\1.15            # 键位置不得出现中文，分组必须都有
flutter analyze --no-pub                                   # 必须 No issues found
```

重写器按**展示位置**判断，不再靠排除法：它会认出 `c.sliders()` 的分组名、
`profileControls()` 的字段表、`catalogueSlider()` 的分组、
`group:`/`field:`/`id:` 等命名参数、`for (final band in const [...])`
这类拼键的迭代列表，一律不动。列在 `toolsoverlay.txt` 里的文件是移植自己写的，
重放时整份跳过（overlay 优先），所以重放不会覆盖手写版本。

`zh.dart` 的 key 是英文原文，catalogue 的 `unit` 字段是机器标识（`stops`、`printerPoints`），不翻译。

## 术语表（改词时按这张表来）

| 英文 | 中文 | 说明 |
|---|---|---|
| Grade | 调色 | 三向调色（阴影/中间调/高光 × 暖度/色调/亮度），不是「灰阶」 |
| Encoded Grade | 编码调色 | 对编码值而非线性光调色 |
| Paper Grade | 相纸号数 | 可变反差相纸 0–5 |
| Graded Print | 分级印相 | 数字参考的一种转换方式 |
| Level | 亮度 | 调色三轴之一 |
| Warmth / Tint | 暖度 / 色调 | 调色三轴另外两个 |
| Band (Red/Green/Blue) | 波段 | 接收波段是波长，不是「通道」 |
| Channel Contrast Match | 通道反差匹配 | |
| Edge Contrast | 边缘反差 | 显影边缘效应 |
| Edge Printing | 片边字 | 胶片片边上的字符 |
| Frame Number / Frames | 画幅编号 / 画幅数 | 135 边框上的编号 |
| Push / Pull | 增感 / 减感 | 显影工艺 |
| Printer | 印片机 | 不是「印相机」 |
| Bleach Bypass | 漂白旁路 | |
| Fringe / Fringing | 色边 | 不是「色散」（dispersion） |
| Lamp / Lamp Temperature | 灯源 / 灯源色温 | 放大机灯；「光源」留给 Light Source |
| Negative Viewing | 负片观看 | |
| Upright | 正向 | 旋转 0° |
| Vibrance | 自然饱和度 | |
| Crosstalk | 串扰 | |
| Move to Trash | 移到回收站 | Windows 用「回收站」 |
| Show in Folder | 在资源管理器中显示 | |
| Legal | 法律 | |

**注意**：`lib/ui/inspector/grade_deck.dart` 的 `bands` / `axes` 是引擎参数键的一部分（`gradeShadowsWarmth`），必须保持英文，显示时才用 `t()`。

## Windows 宿主能力（lib/app/host_windows.dart）

macOS 版通过原生 MethodChannel 提供「打开浏览器 / 在访达中显示 / 用默认程序打开 / 移到废纸篓」。
Windows runner 没有这套原生侧，所以这些调用在这里统一用 Win32 实现，不再依赖插件：

| 能力 | 实现 | 说明 |
|---|---|---|
| `openUrl` | `ShellExecuteW("open", url)` | 开源许可 / 隐私政策 / 服务条款等外链 |
| `openFile` | `ShellExecuteW("open", path)` | 导出完成后的「打开」 |
| `reveal` | `explorer.exe /select,"path"` | 「在资源管理器中显示」 |
| `trash` | `SHFileOperationW(FO_DELETE + FOF_ALLOWUNDO)` | 「移到回收站」，进回收站可还原 |

仍在 macOS 侧、Windows 上已被隐藏（避免点了没反应）：`openRecent`（最近打开）、
`useSamplePhoto`（示例照片，Mac 端是运行中生成的图表）。判断在 `HostWindow.hasRecentFiles`
与 `HostWindow.hasSamplePhoto`。

## 两条不能破的约定

1. **分组名、波段名、轴名是标识**，不是文案。`catalogue.sliders` 的 `group`、
   `GradeDeck.bands/axes` 参与拼参数键（`gradeShadowsWarmth`）或做分组查找，
   必须保持英文；只在显示处用 `t()` 翻译。
2. **全大写标识串不翻译**（`HISTOGRAM`、`LEGAL_MENU` 等是 `controls.json` 的键）。
3. **按名字查表用的键不翻译**：`palette.systemColors` 的 `'Red'` 等来自字形里的
   `var(--fotu-systemRed, …)`，翻了就查不到，图标配色退化。

`tools\apply-zh.cjs` 已经内置这三条守卫（大写串、`module['…']`、`'X': Color(…)`），
再跑一次不会把它们改回去。

改完可以跑两个检查：

```
node tools\check-groups.cjs        # 每个 c.sliders('X') 都能在 catalogue.dart 里找到同名分组
node tools\scan-unapplied.cjs      # 列出“词表里有、源码里还没替换”的字符串，剩下的应当都是标识
```


## 回归测试

`flutter test` 需要 SDK 里已下载的 flutter_tester，本机缓存不全，尚未执行；联网后先跑一次
`flutter pub get`，再：

```
flutter test test\catalogue_test.dart
```

覆盖：四个面板要的分组都有滑块、调色板参数键拼得对、`module[...]` 的键都在、滑块标签没有英文残留。

## vcpkg 依赖

编解码库来自 vcpkg 的静态树（`toolchain\vcpkg`），triplet `x64-windows-static-md`
（静态库 + 动态 C 运行时，与 Swift 的 /MD 一致）。安装命令：

```powershell
vcpkg install `
  libraw[openmp] lcms2 libjpeg-turbo libpng libtiff libheif openexr jasper libde265 x265 libdeflate `
  libspng liblzma openjph imath zlib zstd flatbuffers `
  --triplet x64-windows-static-md
```

**`libraw[openmp]` 那对方括号不能省。** vcpkg 的 libraw 端口 `"default-features": false`，
不带这个 feature 编出来的是单线程库——RAW 打开会慢 3–4 倍，而且没有任何报错提示。
引擎会因此链接 MSVC 的 OpenMP 运行时，`build.ps1` 会把 `vcomp140.dll` 一并放进发行包。
