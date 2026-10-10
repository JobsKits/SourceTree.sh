# `【MacOS】安装SourceTree自定义菜单.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

先发送 `SourceTree.command` 脚本库，再维护 [**Sourcetree**](https://www.sourcetreeapp.com/) 的 `actions.plist`。安装时按稳定脚本路径合并动作，保留当前用户的标题、快捷键、显示设置及额外动作；所有覆盖都有可恢复备份。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh './【MacOS】安装SourceTree自定义菜单.command'
```

需要可交互终端。先显示内置自述并等待回车，`Ctrl+C` 取消；不使用 `sudo`。此安装器不作为无交互 Sourcetree 动作挂载。

## 二、发送脚本库 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、输入或拖入目标父目录，回车默认当前用户家目录；输入同名 `SourceTree.command` 路径时作为最终目录。

2、目标已存在时回车保留并继续安装菜单；输入 `YES` 后才把旧目录移到同级 `SourceTree.command.bak.年月日_时分秒.PID` 并替换。

3、源目标相同则跳过复制；目标位于源目录内或为符号链接时停止。路径按已有祖先目录解析，防止通过软链接造成递归复制。

4、子 Git 的真实元数据复制为目标独立 `.git`，只在暂存副本中去掉 `core.worktree` 并校验。共享对象的 linked worktree 或使用非空 `objects/info/alternates` 的仓库会停止发送，不替换目标；先建立完整独立克隆再部署。副本会验证 HEAD 对象及只读 Git 状态。

## 三、菜单安装和回收 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

脚本包没有 `actions.plist` 时从当前用户 Sourcetree 配置回收到所有等位包；两处都缺失则报错。已有配置时由 [**fzf**](https://formulae.brew.sh/formula/fzf) 选择：

| 方向 | 行为 |
| --- | --- |
| 脚本包 → Sourcetree | 按动作目标合并，保留当前标题、快捷键、显示设置及额外动作，补齐包内新动作 |
| Sourcetree → 脚本包 | 将当前用户配置完整回收到等位包 |
| 取消 / Esc | 不覆盖菜单文件 |

安装方向使用 macOS 原生 Foundation 解档与重新归档，合并失败、重复目标、受管脚本缺失或不可执行会停止；旧终端 Pod Install 路径转换为现有入口。同路径匹配后保留当前标题、快捷键和显示设置，仅将脚本目标、仓库参数及动作类型与脚本包对齐。默认指向家目录运行库；指定其它发送目录后指向实际目标库。

## 四、同步和重载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

参与同步的等位包为当前库、当前用户家目录中的运行库、JobsGenesis 中的备份库，以及本次发送的目标库；仅同步实际存在的安装器目录。

写入用户配置前先正常退出正在运行的 Sourcetree，等它保存当前配置后再合并；不强制终止。退出失败则不覆盖文件。安装成功后重新打开并检查进程运行。应用原本未运行时不主动启动。每个目标覆盖前生成 `actions.plist.bak.年月日_时分秒.PID`；内容一致为成功的无操作，复制失败会停止而不会继续报成功。

## 五、依赖、风险与日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需要系统 `ditto`、健康 [**Git**](https://git-scm.com/)、`plutil`、`cmp`、`osascript`；只在选择同步方向时需要 fzf，不自动安装或升级全局工具。发送库会复制工作树，包括未提交内容；暂存复制或 Git 校验失败会清理本次临时目录并保留现有目标，独立副本会复检 HEAD 和工作树状态；菜单安装可能正常重启 Sourcetree。不会创建提交、推送或切换用户仓库分支。

日志位于系统临时目录，文件名 `【MacOS】安装SourceTree自定义菜单.log`。缺少 fzf 时在终端准备工具；Sourcetree 未退出时先结束正在进行的操作，再运行安装器。

## 六、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

已通过 `zsh -n`、归档解档、菜单标题保留、重复目标拒绝和内容相同不误报失败的隔离验证。库发送与替换的失败路径在临时目录验证；未实际替换用户仓库或克隆目录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
