# `【MacOS@SourceTree】⏬只拉取远程代码.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

适用于本地收藏、只能拉取、无推送权限的 [**Git**](https://git-scm.com/) 仓库。从 [**Sourcetree**](https://www.sourcetreeapp.com/) 菜单打开独立终端，将当前分支同步到已配置的远程上游。脚本不提交、不推送、不合并本地独有历史，不创建分支。

| 检查结果 | 实际行为 |
| --- | --- |
| 本地干净且落后 | 获取远程成功后快进 |
| 本地干净且相同 | 核验提交号后结束 |
| 有暂存、未暂存、未跟踪内容 | 红字列出路径，精确输入大写 `YES` 后舍弃并同步 |
| 有本地独有提交，含领先、分叉和远程改写历史 | 红字列出提交，精确输入 `YES` 后舍弃并同步 |
| 回车、`yes`、`NO`、其它输入或 `Ctrl+C` | 取消，不舍弃本地内容 |
| 获取失败、上游不明确、游离态或未完成操作 | 停止，不清理工作区 |
| 子模块改动、嵌套仓库、忽略内容可能被覆盖 | 停止，要求单独处理 |

危险确认不创建 stash 或内容备份；未提交内容与未跟踪文件被舍弃后不能依赖 Git 恢复。确认前须自行保存需要保留的内容。

## 一、<span id="usage">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

SourceTree 仓库动作目标是本目录内的同名可执行脚本，参数为 `$REPO`。动作只负责打开 Terminal.app，不在 SourceTree 输出窗口等待输入。菜单由 [安装器](../【MacOS】安装SourceTree自定义菜单.command/README.md) 登记和更新。

终端手动运行时，在当前目录使用：

```shell
/bin/zsh \
  './【MacOS@SourceTree】⏬只拉取远程代码.command' \
  '../需要拉取的仓库'
```

不传目录时使用当前工作目录；目标内部目录会解析到所属工作树根目录。先显示内置自述并等待回车，任何非空输入取消。`--terminal-run` 供启动器传递，仍必须连接真实终端，不能用来绕过回车或 `YES`。双击脚本不会扫描其它仓库，目标不是 Git 工作树时停止。

只依赖系统 `/bin/zsh`、Git、Perl 和系统命令；SourceTree 转交终端还需要 `osascript`。检查工具真实可用性，不自动安装或升级依赖。

## 二、<span id="flow">执行流程与来源</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、终端回车确认后创建私有日志与单仓库动作锁。

2、拒绝 merge、rebase、cherry-pick、revert、bisect 等未完成现场及索引锁；拒绝稀疏检出、`skip-worktree` 和 `assume-unchanged`，防止隐藏改动。

3、读取当前分支的唯一 `branch.<分支>.remote` / `merge` 及远程跟踪映射。不猜测 `origin`、`main` 或默认分支，不切换分支；本地上游 `remote=.` 不适用。

4、先展示配置来源、当前 Git 配置展开后的拉取地址、仓库路径和分支，再 fetch 该远程分支。只更新对应远程跟踪引用，不递归子模块，不获取标签。远程分支被删除时获取失败，不沿用旧缓存执行重置。

5、固定获取到的目标提交，检查子仓和忽略文件风险；检查工作区及目标之外的本地独有提交。危险情况列明仓库完整路径、分支、提交号、文件状态与清理预览，要求精确输入 `YES`。

6、确认后重新核对分支、HEAD、上游、工作区与保护边界；暂存、未暂存及未跟踪内容以摘要再次核对，同一已修改文件继续编辑也会使确认失效。有变化时停止，重新运行并重新确认。

7、干净落后分支执行 `merge --ff-only --no-autostash`。有 `YES` 授权时执行 `reset --hard --no-recurse-submodules <固定目标>` 与 `clean -fd`，舍弃当前工作树的本地改动和非忽略未跟踪内容。最后核验 HEAD 等于固定目标、工作区干净。

8、输出最终来源、目标提交与日志位置。SourceTree 打开的终端显示最终退出码；手动运行以进程退出状态为准。SourceTree 启动成功仅表示终端已打开，实际结果以新终端为准。

来源输出结构如下，示例地址仅用于说明，未部署：

```text
━━━━━━━━━━ 来源｜只拉取 ━━━━━━━━━━
对象：main → upstream/main
配置来源：https://git.example.org/team/project.git
拉取地址（本地 Git 配置展开）：https://git.example.org/team/project.git
目标位置：<当前仓库完整路径>
本次固定目标：<成功获取的完整提交号>
```

URL 的配置展开不代表已验证网络重定向终点或代理出口。输出过滤地址认证信息和查询参数；日志不保存文件 diff。脚本不变更网络代理或远程配置，沿用 Git 本身的访问配置，禁用本次命令的本地 Git hooks，避免附带运行其它业务。

## 三、<span id="boundaries">清理边界与失败处理</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 仅处理指定工作树，不向上处理父仓，也不递归同步子模块。子模块脏状态、暂存指针变化、检出提交不符或远程涉及子模块指针 / 路径变化时停止。
- 保留忽略文件。`reset --hard` 可能覆盖挡路的忽略内容，因此对当前树和目标树进行路径碰撞检查，并保守按 Unicode 规范化及大小写折叠比较，兼容 Mac 常见卷；碰撞时整次清理停止，不能只依赖 `clean -fd` 不带 `-x`。
- 嵌套独立仓库、worktree 的 `.git` 文件和裸仓库单独保护，不使用 `clean -ff`。不批量处理依赖或构建目录源码，但清理候选目录中的 Git 元数据必须核对，即使目录名为 `node_modules`、`Pods`、`.dart_tool`、`build`、`DerivedData` 也不省略这项检查；非忽略的普通内容仍属于 `clean -fd` 的确认范围，发现嵌套库则在任何舍弃前停止。
- fetch 可能更新远程跟踪引用，但任何 fetch 失败都不会触发本地舍弃。取消危险确认同样不回滚已经成功获取的远程跟踪引用。
- 已开始舍弃后发生磁盘、权限或进程中断，可能留下部分完成状态，脚本不会声称事务回滚。按日志与工作区检查结果处理后再运行。
- 动作锁只能防止本脚本并行运行；执行期间避免从其它窗口编辑、切换分支或启动其它 Git 写操作。异常强杀后如锁目录仍在，确认没有运行中的任务，再手工处理日志中点名的锁。

## 四、<span id="logs">日志和常见问题</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

每次终端确认后生成独立日志，位于系统临时目录，文件名为 `【MacOS@SourceTree】⏬只拉取远程代码.年月日-时分秒.进程号.log`。运行输出给出实际完整路径，日志为纯文本并采用私有权限。正常彩色终端中的危险提示为红色；SourceTree、`NO_COLOR`、`TERM=dumb` 使用纯文本，但不放宽确认要求。

- 没有上游：先在 SourceTree 为当前已有分支配置正确的远程跟踪分支。
- 游离 HEAD：先切换到明确的已有跟踪分支；脚本不猜目标、不创建分支。
- 子模块风险：先单独处理子仓，或使用专用子模块更新流程，不能用父仓 `YES` 代替子仓授权。
- 终端未打开：检查系统自动化权限，或直接在 Terminal 用完整脚本路径和仓库目录运行。
- 保留本地改动：在 `YES` 提示处取消，手动复制或保存后再运行。

## 五、<span id="validation">验证范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

两处脚本已通过 `zsh -n` 与内容一致性检查；40 项临时真实 Git / PTY 交互测试全部通过，包括严格 `YES`、取消保留、获取失败、领先与分叉、子模块、嵌套仓库、忽略文件的大小写 / Unicode 冲突、确认期间内容变化、目录检查失败、重复运行和锁清理。测试只使用本机临时裸远程，不用实际收藏仓库测试舍弃，不向业务远程推送。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
