# `【MacOS】安装SourceTree自定义菜单.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、运行方式](#jobs-toc-heading-2)
- [二、发送脚本库](#jobs-toc-heading-3)
- [三、菜单安装和回收](#jobs-toc-heading-4)
- [四、同步和重载](#jobs-toc-heading-5)
- [五、依赖、风险与日志](#jobs-toc-heading-6)
- [六、验证边界](#jobs-toc-heading-7)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

先发送 `SourceTree.command` 脚本库，再维护 [**Sourcetree**](https://www.sourcetreeapp.com/) 的 `actions.plist`。安装时按稳定脚本路径合并动作，保留当前用户的标题、快捷键、显示设置及额外动作；所有覆盖都有可恢复备份。

安装只使用当前用户可写的目录和配置，不需要管理员身份。普通账户或访客账户应直接运行，不使用 `sudo`；目录被系统限制写入时会按实际失败原因停止。

两台 Mac 均使用不带 `1` 的当前主入口；同目录的 `【MacOS】安装SourceTree自定义菜单1.command` 保留为旧版对照。菜单路径按本次源库和目标目录重新解析，模板中另一位用户的旧路径会迁移；Flutter 运行入口的旧 ASCII 冒号路径也会迁移到现有全角冒号路径。

安装菜单时会补齐 [⏬只拉取远程代码（终端）](../【MacOS@SourceTree】⏬只拉取远程代码.command/README.md) 动作，适用于没有推送权限的上游仓库。它打开独立终端执行，拉取当前父仓后逐层按 gitlink 检出子模块，不提交、不推送；纯子仓 HEAD 漂移自动对齐。当前父仓本地内容须红字列明并精确输入 `YES` 才舍弃，子仓源码和暂存指针仍单独保护。目标平台缺少子提交时停止并显示仓库、来源及 SHA，不能用消费端提交或 push 解决。

安装菜单也会补齐 [📦打包生成HAP+APP文件（Flutter.ohos）](../【MacOS@SourceTree】📦双击打包Flutter.ohos.command/README.md)。[**Android**](https://developer.android.com) 打包产物为 APK / AAB，[**HarmonyOS**](https://developer.huawei.com/consumer/cn/harmonyos/) 入口同时生成 HAP 安装模块与 APP 发布包；该入口只处理已适配鸿蒙的 [**Flutter**](https://flutter.dev/) 工程，需要同时支持 `flutter build hap` 与 `flutter build app` 的 [适配 SDK](https://gitcode.com/CPF-Flutter/flutter_flutter) 和既有 `ohos/` 目录。安装菜单不会安装 SDK、迁移工程或生成签名配置。

| 子模块副本处理 | 原写法 | 当前写法与结果 |
| --- | --- | --- |
| 清除旧工作树路径 | `git -C 暂存目录 config --local --unset core.worktree`，可能先进入失效路径而失败 | `git config --file 配置文件 --unset-all core.worktree`，直接清理暂存 `.git/config` 与已有的 `.git/config.worktree` |
| 确认独立副本 | 只检查 [**Git**](https://git-scm.com/) 命令退出码，清理失败被忽略 | 核对工作树根目录就是暂存目录；配置写入异常立即停止，Git 校验失败显示原始诊断 |

典型子模块配置 `core.worktree=../../../SourceTree.command` 相对于原 Git 元数据目录解析；复制为独立 `.git` 后，这个相对位置已经改变。清理配置必须先于工作树校验，源库配置保持原样。路径解析规则见 [**Git**](https://git-scm.com/docs/git-config#Documentation/git-config.txt-coreworktree) 官方说明。

工作树和真实 Git 目录先由系统 `find` 生成 NUL 分隔的相对文件清单，按实际类型预排除 `fsmonitor--daemon.ipc` 等运行时 socket，再交给系统 `tar` 按清单复制。每个 socket 只显示清楚的中文跳过提示，避免归档器尝试读取其扩展属性。相同名字的普通文件仍会完整保留，文件内容、执行权限、符号链接、硬链接及扩展属性按归档恢复。不删除源 socket，不停止源监控器，不修改源 Git 配置。

复制诊断先同步收集，再逐行显示并写入日志；工具没有末尾换行时会补齐，不与后面的成功信息连行。真正的读取、归档、提取或清单生成错误继续显示并停止，不能用过滤错误文本的方式隐藏失败。正常输出示例：

```text
ℹ 跳过运行时 socket：<Git 元数据目录>/fsmonitor--daemon.ipc
✔ 已把 Git 元数据复制为目标库独立 .git。
ℹ 菜单运行库：<本次采用的运行库>
```

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```shell
/bin/zsh './【MacOS】安装SourceTree自定义菜单.command'
```

需要可交互终端。先显示内置自述并等待回车，`Ctrl+C` 取消；不使用 `sudo`。此安装器不作为无交互 Sourcetree 动作挂载。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、发送脚本库 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、输入或拖入目标父目录，回车默认当前用户家目录；输入同名 `SourceTree.command` 路径时作为最终目录。

2、目标已存在时回车保留并继续安装菜单；输入 `YES` 后才把旧目录移到同级 `SourceTree.command.bak.年月日_时分秒.PID` 并替换。

保留旧目标库时会校验全部菜单动作是否为普通、可执行脚本；若旧库缺失或不可用，且当前源库全部通过校验，菜单整组改用源库，同时保留旧目标目录并提示源库路径必须继续有效。源库也不健康时停止，不混用两个版本。明确选择替换的目标库校验失败时停止，不自动改用其它位置。

3、源目标相同则跳过复制；目标位于源目录内或为符号链接时停止。路径按已有祖先目录解析，防止通过软链接造成递归复制。

4、复制前显示工作树与 Git 元数据的本地来源、暂存目标。普通 `.git/` 与子模块 `.git` 指针两种源布局均支持，工作树和元数据中的运行时 socket 在生成清单时排除。子 Git 的真实元数据复制为目标独立 `.git`，直接通过配置文件路径去掉暂存 `.git/config` 和已有 `.git/config.worktree` 中的全部 `core.worktree`；未设置此键属于正常情况，其它清理失败会停止。随后核对工作树根目录、HEAD 对象及只读 Git 状态；本次校验命令临时禁用 fsmonitor，避免在暂存副本启动监控器，源与目标配置均不因此修改。共享对象的 linked worktree 或使用非空 `objects/info/alternates` 的仓库会停止发送，不替换目标；先建立完整独立克隆再部署。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、菜单安装和回收 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

脚本包没有 `actions.plist` 时从当前用户 Sourcetree 配置回收到所有等位包；两处都缺失则报错。已有配置时由 [**fzf**](https://formulae.brew.sh/formula/fzf) 选择：

| 方向 | 行为 |
| --- | --- |
| 脚本包 → Sourcetree | 按动作目标合并并归类排序，保留当前标题、快捷键、显示设置及额外动作，补齐包内新动作；鸿蒙旧默认标题迁移为双包名称 |
| Sourcetree → 脚本包 | 将当前用户配置完整回收到等位包 |
| 取消 / Esc | 不覆盖菜单文件 |

安装方向使用 macOS 原生 Foundation 解档与重新归档，合并失败、重复目标、受管脚本缺失或不可执行会停止；旧终端 Pod Install 路径转换为现有入口。同路径匹配后保留当前标题、快捷键和显示设置，仅将脚本目标、仓库参数及动作类型与脚本包对齐。默认指向家目录运行库；指定其它发送目录后指向实际目标库。

菜单按稳定脚本路径连续排列成以下七组，标题修改不影响归类；额外动作保留原有相对顺序，排在受管动作之后。不增加可点击的分类占位项。下载配置和运行授权保留为独立脚本，安装时按脚本名从旧模板及当前菜单中排除，不再挂载。

每个标题以 emoji 开头。已有图标和标题正文保留；缺少图标时 Android Studio 补 `🤖`、Trae 补 `🧠`、VSCode 补 `💻`，其它动作补 `🔧`。普通数字不算 emoji，现有 `3️⃣` 键帽图标仍保留；重复安装不叠加图标。

| 顺序 | 分类 | 组内顺序 |
| --- | --- | --- |
| 1 | 打开 | Typora → Xcode 递归 / 当前目录 → Android Studio 普通 / JDK → Trae 普通 / JDK → VSCode 普通 / JDK → 终端 → Flutter 运行 → 远程仓库网页 |
| 2 | Git 与地址 | 获取远程地址 → 获取目标绝对地址 → 只拉取 → 逐层提交推送 → 本地回退 |
| 3 | 修复 | Git Commit 修复 → Git Fetch 修复 → Flutter 中文路径修复 |
| 4 | Flutter 维护 | 项目体检 → 收集依赖 → 重新拉取依赖 → 自动化生产代码 |
| 5 | CocoaPods | Pod Install 终端 → Sourcetree |
| 6 | 打包 | APK（Flutter.Android）→ iPA（Flutter.iOS）→ HAP+APP（Flutter.ohos）→ iPA（iOS 原生） |
| 7 | 工具 | edgetunnel 升级 → 魔法简历 |

体检菜单显示为 `🏥Flutter项目体检`，去掉标题末尾的 `.`；脚本文件名不变。模板提供 32 个仓库动作，下载配置、运行授权和菜单安装器不作为仓库动作挂载。

`⏬只拉取远程代码（终端）` 同时登记在安装脚本与 `actions.plist` 模板中。即使旧模板尚未包含该动作，安装方向也会按稳定脚本路径补齐；目标为运行库中的同名可执行 `.command`，参数为 `$REPO`，仓库动作启用、文件动作关闭。默认不打开 Sourcetree 输出窗口，脚本负责启动独立 `Terminal.app` 承接交互；更新已有动作时仍保留用户的标题和窗口设置。终端启动失败或无法交互时停止，不能跳过 `YES` 门禁。

`📦打包生成HAP+APP文件（Flutter.ohos）` 同样同时登记在安装脚本与模板中，旧模板安装时按稳定脚本路径补齐并排入打包组。参数固定为 `$REPO --target all --mode release`，仓库动作启用、文件动作关闭，并启用独立输出窗口与完整输出；原默认标题 `📦双击打包Flutter.ohos` 自动改为双包名称，其它自取标题、快捷键和窗口设置继续保留。工具链与 HAP、APP 产物校验由打包入口负责。

[提交回退](<../【MacOS@SourceTree】♻️双击Git（识别子Git） 提交回退.command/README.md>) 保持仓库动作与 `$REPO` 参数，菜单不传选中的历史提交。当前分支的多远端快照不同时，脚本打开独立终端明确选择线路或历史提交，再执行 soft 回退；单线路仍以 upstream 为默认目标。更新同路径脚本后下次点击即读取新实现，菜单目标和用户标题沿用已有配置。

[🌐获取远程仓库地址](../【MacOS@SourceTree】🌐获取远程仓库地址.command/README.md) 与 [🌍打开远程仓库地址](../【MacOS@SourceTree】🌍打开远程仓库地址.command/README.md) 均使用 `$REPO` 仓库动作。打开动作同时登记在安装脚本与模板中，即使模板缺项也会补齐。单个去重 URL 直接复制 / 打开；多个 URL 由入口转交独立 Terminal 后使用 fzf 选择，Sourcetree 动作进程不等待输入。默认打开动作不另弹输出窗口、保留完整输出；更新已有项仍保留用户标题、快捷键和窗口设置，依赖自检由业务入口负责。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、同步和重载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

参与同步的等位包为当前库、当前用户家目录中的运行库、JobsGenesis 中的备份库，以及本次发送的目标库；仅同步实际存在的安装器目录。

写入用户配置前先静默预检菜单；失败时不退出 Sourcetree、不覆盖配置。预检通过后正常退出正在运行的 Sourcetree，等它保存最新配置，再重新合并并报告一次实际运行库及必要的整组回退说明；不强制终止。退出失败则不覆盖文件；退出后的最终合并失败会重新打开原应用并保留配置。安装成功后重新打开并检查进程运行。应用原本未运行时不主动启动。每个目标覆盖前生成 `actions.plist.bak.年月日_时分秒.PID`；内容一致为成功的无操作，复制失败会停止而不会继续报成功。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、依赖、风险与日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要系统 `find`、`tar`、健康 [**Git**](https://git-scm.com/)、`plutil`、`cmp`、`osascript`；只在选择同步方向时需要 fzf，不自动安装或升级全局工具。发送库会复制工作树，包括未提交内容；文件清单、tar 两端的读写或 Git 校验任一失败都会停止，清理本次临时目录并保留现有目标，不能将普通文件读取失败当作 socket 跳过。独立副本会复检 HEAD 和工作树状态；菜单安装可能正常重启 Sourcetree。不会创建提交、推送或切换用户仓库分支。

日志位于系统临时目录，文件名 `【MacOS】安装SourceTree自定义菜单.log`。缺少 fzf 时在终端准备工具；Sourcetree 未退出时先结束正在进行的操作，再运行安装器。

出现“目标临时库 Git 元数据校验失败”时，先查看同时显示的 Git 原始错误与日志。应检查复制后 `core.worktree` 的真实绑定及同名脚本包是否完整。若仍出现 `Permission denied` 或 `dubious ownership`，按实际目标目录权限或仓库所有者排查；不使用 `sudo`、不关闭全局 Git 所有权检查。

日志中的“跳过运行时 socket”表示通信端点未进入复制清单，后续仍须完成 Git 校验才能替换目标。普通文件的 `Permission denied`、归档读取或提取失败仍属于错误；这些真实诊断会完整显示，不因输出规整而隐藏。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">六、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

已通过 `zsh -n`、归档解档、菜单标题保留、重复目标拒绝和内容相同不误报失败的隔离验证。库发送与替换的失败路径在临时目录验证；未实际替换用户仓库或克隆目录。

[安装器复制回归](../Tests/InstallerGitCopy.Tests.rb) 使用临时 Unix socket 和真实临时 Git 仓库，覆盖独立 `.git/`、外置 gitdir 指针、同名普通文件、特殊字符路径、文件属性与链接保留、只读校验、成功替换前备份，以及普通文件不可读或提取失败时的失败传播和旧目标保护。测试不操作真实运行库或菜单。

[菜单跨机兼容回归](../Tests/InstallerMenuCompatibility.Tests.rb) 使用不同临时用户目录和假可执行脚本，验证模板路径迁移、旧运行库整组回退、无效源库拒绝、用户设置保留、重装幂等，以及应用运行 / 未运行时报告只出现一次。复制回归另验证 socket 提示无原始 tar 噪声、诊断末尾缺换行时输出仍分行、临时清单回收。另一台 Mac 的具体系统与文件权限仍需用当前主入口实机复测，本机夹具不代替异机验收。

本机含真实 fsmonitor socket 的源库也已在私有临时目录完成工作树和 Git 元数据复制；目标 HEAD 与源一致，独立工作树及只读状态可读取，源配置、索引、socket 和真实菜单未变。该检查没有整体替换实际运行库。

远程地址动作的临时库验证覆盖缺项补齐、用户标题 / 快捷键 / 窗口设置及额外动作保留、仓库参数与动作类型校正、重复安装语义幂等、重复目标和不可执行脚本拒绝。

仅拉取动作的菜单合并已在临时运行库验证：模板动作按字段保留，现有配置与首次安装均能补齐缺少的动作；用户标题、快捷键、窗口设置和额外动作保留，仓库参数和动作类型校正，重复目标及不可执行脚本会拒绝安装。

鸿蒙动作的临时库检查覆盖缺项补齐、首次安装、用户字段和额外动作保留、重复安装幂等、重复目标与不可执行脚本拒绝。检查未改写真实用户菜单或执行真实打包。

Git 副本回归通过 37 项检查，覆盖普通仓库、真实吸收元数据的子模块、旧相对路径失效或误指现存目录、绝对路径、`config.worktree`、重复键、无提交仓库、共享对象拒绝及配置锁失败；同时核对源库配置、HEAD、索引和工作区不变，以及暂存目录移到最终位置后 `fsck` 成功。完整发送流程另通过新建目标、备份替换、失败保留目标并清理暂存三类隔离检查。非管理员新电脑仍需按实际工具和权限进行实机验收。


鸿蒙 Flutter 动作按稳定脚本路径维护，仅迁移旧默认标题，保留其它自取标题；参数固定为 `$REPO --target all --mode release`，一次生成 HAP 与 APP。模板、安装器默认登记和当前用户动作同义；不因更新此动作覆盖其它动作。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
