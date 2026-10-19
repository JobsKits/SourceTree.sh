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

安装菜单时会补齐 [⏬只拉取远程代码（终端）](../【MacOS@SourceTree】⏬只拉取远程代码.command/README.md) 动作，适用于没有推送权限的上游仓库。它打开独立终端执行，拉取当前父仓后逐层按 gitlink 检出子模块，不提交、不推送；纯子仓 HEAD 漂移自动对齐。当前父仓本地内容须红字列明并精确输入 `YES` 才舍弃，子仓源码和暂存指针仍单独保护。目标平台缺少子提交时停止并显示仓库、来源及 SHA，不能用消费端提交或 push 解决。

| 子模块副本处理 | 原写法 | 当前写法与结果 |
| --- | --- | --- |
| 清除旧工作树路径 | `git -C 暂存目录 config --local --unset core.worktree`，可能先进入失效路径而失败 | `git config --file 配置文件 --unset-all core.worktree`，直接清理暂存 `.git/config` 与已有的 `.git/config.worktree` |
| 确认独立副本 | 只检查 [**Git**](https://git-scm.com/) 命令退出码，清理失败被忽略 | 核对工作树根目录就是暂存目录；配置写入异常立即停止，Git 校验失败显示原始诊断 |

典型子模块配置 `core.worktree=../../../SourceTree.command` 相对于原 Git 元数据目录解析；复制为独立 `.git` 后，这个相对位置已经改变。清理配置必须先于工作树校验，源库配置保持原样。路径解析规则见 [**Git**](https://git-scm.com/docs/git-config#Documentation/git-config.txt-coreworktree) 官方说明。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```shell
/bin/zsh './【MacOS】安装SourceTree自定义菜单.command'
```

需要可交互终端。先显示内置自述并等待回车，`Ctrl+C` 取消；不使用 `sudo`。此安装器不作为无交互 Sourcetree 动作挂载。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、发送脚本库 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、输入或拖入目标父目录，回车默认当前用户家目录；输入同名 `SourceTree.command` 路径时作为最终目录。

2、目标已存在时回车保留并继续安装菜单；输入 `YES` 后才把旧目录移到同级 `SourceTree.command.bak.年月日_时分秒.PID` 并替换。

3、源目标相同则跳过复制；目标位于源目录内或为符号链接时停止。路径按已有祖先目录解析，防止通过软链接造成递归复制。

4、复制前显示工作树与 Git 元数据的本地来源、暂存目标。子 Git 的真实元数据复制为目标独立 `.git`，直接通过配置文件路径去掉暂存 `.git/config` 和已有 `.git/config.worktree` 中的全部 `core.worktree`；未设置此键属于正常情况，其它清理失败会停止。随后核对工作树根目录、HEAD 对象及只读 Git 状态。共享对象的 linked worktree 或使用非空 `objects/info/alternates` 的仓库会停止发送，不替换目标；先建立完整独立克隆再部署。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、菜单安装和回收 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

脚本包没有 `actions.plist` 时从当前用户 Sourcetree 配置回收到所有等位包；两处都缺失则报错。已有配置时由 [**fzf**](https://formulae.brew.sh/formula/fzf) 选择：

| 方向 | 行为 |
| --- | --- |
| 脚本包 → Sourcetree | 按动作目标合并，保留当前标题、快捷键、显示设置及额外动作，补齐包内新动作 |
| Sourcetree → 脚本包 | 将当前用户配置完整回收到等位包 |
| 取消 / Esc | 不覆盖菜单文件 |

安装方向使用 macOS 原生 Foundation 解档与重新归档，合并失败、重复目标、受管脚本缺失或不可执行会停止；旧终端 Pod Install 路径转换为现有入口。同路径匹配后保留当前标题、快捷键和显示设置，仅将脚本目标、仓库参数及动作类型与脚本包对齐。默认指向家目录运行库；指定其它发送目录后指向实际目标库。

`⏬只拉取远程代码（终端）` 同时登记在安装脚本与 `actions.plist` 模板中。即使旧模板尚未包含该动作，安装方向也会按稳定脚本路径补齐；目标为运行库中的同名可执行 `.command`，参数为 `$REPO`，仓库动作启用、文件动作关闭。默认不打开 Sourcetree 输出窗口，脚本负责启动独立 `Terminal.app` 承接交互；更新已有动作时仍保留用户的标题和窗口设置。终端启动失败或无法交互时停止，不能跳过 `YES` 门禁。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、同步和重载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

参与同步的等位包为当前库、当前用户家目录中的运行库、JobsGenesis 中的备份库，以及本次发送的目标库；仅同步实际存在的安装器目录。

写入用户配置前先正常退出正在运行的 Sourcetree，等它保存当前配置后再合并；不强制终止。退出失败则不覆盖文件。安装成功后重新打开并检查进程运行。应用原本未运行时不主动启动。每个目标覆盖前生成 `actions.plist.bak.年月日_时分秒.PID`；内容一致为成功的无操作，复制失败会停止而不会继续报成功。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、依赖、风险与日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要系统 `ditto`、健康 [**Git**](https://git-scm.com/)、`plutil`、`cmp`、`osascript`；只在选择同步方向时需要 fzf，不自动安装或升级全局工具。发送库会复制工作树，包括未提交内容；暂存复制或 Git 校验失败会清理本次临时目录并保留现有目标，独立副本会复检 HEAD 和工作树状态；菜单安装可能正常重启 Sourcetree。不会创建提交、推送或切换用户仓库分支。

日志位于系统临时目录，文件名 `【MacOS】安装SourceTree自定义菜单.log`。缺少 fzf 时在终端准备工具；Sourcetree 未退出时先结束正在进行的操作，再运行安装器。

出现“目标临时库 Git 元数据校验失败”时，先查看同时显示的 Git 原始错误与日志。旧版安装器在子模块复制后可能因 `core.worktree` 失效触发此错，使用完整更新后的同名脚本包重新运行。若仍出现 `Permission denied` 或 `dubious ownership`，按实际目标目录权限或仓库所有者排查；不使用 `sudo`、不关闭全局 Git 所有权检查。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">六、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

已通过 `zsh -n`、归档解档、菜单标题保留、重复目标拒绝和内容相同不误报失败的隔离验证。库发送与替换的失败路径在临时目录验证；未实际替换用户仓库或克隆目录。

仅拉取动作的菜单合并已在临时运行库验证：31 个原模板动作保持原值，旧模板与首次安装均能补齐唯一新动作；用户标题、快捷键、窗口设置和额外动作保留，仓库参数和动作类型校正，重复目标及不可执行脚本会拒绝安装。

Git 副本回归通过 37 项检查，覆盖普通仓库、真实吸收元数据的子模块、旧相对路径失效或误指现存目录、绝对路径、`config.worktree`、重复键、无提交仓库、共享对象拒绝及配置锁失败；同时核对源库配置、HEAD、索引和工作区不变，以及暂存目录移到最终位置后 `fsck` 成功。完整发送流程另通过新建目标、备份替换、失败保留目标并清理暂存三类隔离检查。非管理员新电脑仍需使用更新后的脚本实机重跑。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
