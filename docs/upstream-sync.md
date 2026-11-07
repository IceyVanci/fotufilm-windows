# 跟随上游

这个移植不 fork 上游，也不向上游提 PR。跟随的方式是**在新版本上重放移植层**。

```
scripts\sync-upstream.ps1 -Tag v1.15
  ├ vendor/upstream        克隆并检出该 tag（只读）
  ├ work/1.15              干净副本
  ├ 铺 port/overlay        移植自己写的文件
  ├ git apply port/patches 对上游文件的改动
  ├ node port/i18n/apply-zh.cjs --root work/1.15 --apply
  ├ node port/i18n/check-zh.cjs --root work/1.15
  └ 更新 upstream.lock
scripts\build.ps1 -Source work\1.15 -Version 1.15
```

## 一次同步要多久

按 1.15 的实测（上游 6 个提交、32 改 56 增）：

| 上游变更 | 需要做的 | 实测 |
|---|---|---|
| 文档、网页 | 重放一遍即可 | 10 分钟 |
| 界面文案 | 重放，扫描器列出没有的词条再补 | 30 分钟 |
| 新增控件 / 目录 | 补词条，可能补图标 | 1–2 小时 |
| 改 Halide 阶段（`Sources/FotofilmHalide/Stages/*.h`） | 重新生成全部 AOT 核 | 机器时间 20 分钟 |
| 改引擎 C ABI | 改 Host 与 FFI | 半天起 |

## 最容易出事的三处

**① 键被翻译。** `c.sliders()` 的分组名、`grade$band$axis` 的色带与轴名、`palette.systemColors`
的颜色令牌都是引擎读回去的标识。1.14.0-w1 里 `grade_deck.dart` 的色带名被翻成中文，
参数键变成 `grade阴影暖度`，调色盘写入全部落空且不报错。现在 `port/i18n/check-zh.cjs`
在每次构建前断言这一点。

**② AOT 核没跟着重生成。** Halide 阶段的头文件一变，46 个变体全部作废；不重生成的话
Swift 用新常量、核里跑旧曲线，预览与导出不一致。`scripts/build.ps1` 会比较阶段头与
AOT 核的时间戳，旧了直接报错退出。

**③ 补丁漂移。** 上游改了我们也在改的文件时，`git apply` 会拒绝。这是必须付的成本，
但范围被压在 `port/patches` 里，看得见、改得动。处理办法见 [port/README.md](../port/README.md)。

## 版本号

上游的 `version.env` **不随发布更新**——v1.15 里它仍写着 `MARKETING_VERSION=1.14`。
所以版本一律从 tag 取，`upstream.lock` 记录当前携带的 tag 与 commit。
移植版本写作 `1.15.0-w1`：上游发布号 + `.0-w` + 移植修订号。
