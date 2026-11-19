# 【WindowsOS@SourceTree】📥修复Git无法Push

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与参数](#jobs-toc-heading-2)
- [二、处理流程与影响](#jobs-toc-heading-3)
- [三、场景与处置](#jobs-toc-heading-4)
- [四、日志、恢复与验证](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> 对当前仓库的一条明确线路排障，整合双方提交后普通推送，并读回服务端提交号核验。适用 [**Windows**](https://www.microsoft.com/windows/) [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1+ 和 [**Git**](https://git-scm.com/)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与参数 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```powershell
# 从本目录运行：明确选择 remote 和目标分支。
& '.\【WindowsOS@SourceTree】📥修复Git无法Push.ps1' -Target 'D:\Projects\My Project' -Remote Github -Branch main

# 仅诊断：检查本地状态、选定端点和服务端分支，不写仓库。
& '.\【WindowsOS@SourceTree】📥修复Git无法Push.ps1' -Target 'D:\Projects\My Project' -Remote Github -Branch main -Diagnose
```

- 双击同目录 `.cmd` 也可运行；`-Target` 缺省时使用调用目录。运行先显示内置自述，回车确认，`Ctrl+C` 取消。
- `-Remote` 是 `-Option` 的别名，接受已有远端名称；`-Branch` 是 `-Value` 的别名，接受目标分支短名，例如 `main`。显式分支可授权首次创建该远端分支。
- 未显式指定线路时，依次读取本地分支的 `pushRemote`、`remote.pushDefault`、上游远端；仅一个远端时直接复用，多候选用 [**fzf**](https://github.com/junegunn/fzf) 选择，默认取消。缺少选择器时停止，可显式传参；不自动安装依赖。
- 目标分支优先显式参数，再读当前仓库 local 的 `remote.<名称>.jobsPushBranch`、当前分支适用的精确 push refspec、上游分支，最后使用当前本地分支名。无法唯一解释的配置停止；没有显式 `-Branch` 时不创建不存在的目标分支。
- [**Sourcetree**](https://www.sourcetreeapp.com/) 安装清单的动作 ID 为 `push-repair`，传 `-SourceTree -Target "$REPO"`；窗口只负责启动独立终端，不等待交互，结果和退出码留在终端。
- 需携带完整 `WindowsOS` 目录。入口通过相对路径加载 [公共调度](../Scripts/SourceTree.psm1) 和 [独立修复模块](../Scripts/Features/JobsGitPushRepair/Scripts/README.md)，不依赖原电脑目录。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、处理流程与影响 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 检查已有本地分支、已提交 HEAD、工作树和暂存区、未完成事务与精确锁。任何已有改动、冲突或锁保留，报告原因后退出。索引存在 assume-unchanged / skip-worktree 时停止，避免隐藏本地数据；sparse checkout 交专用流程。
- 显示仓库、当前分支、remote、脱敏完整推送地址和目标 `refs/heads/…`。fetch URL 与 push URL 不同时，从选定推送端取得历史；不会把只读上游的无关历史混入推送目标。
- 精确获取目标分支到临时 `refs/jobs-push-repair/…` 引用，不更新其它本地分支、标签或工作树；原分支保持不切换。
- 整合前显式检查远端新增路径及其父路径，防止覆盖本地忽略文件/目录。`--no-overwrite-ignore` 不能单独保证所有合并策略都保留此类数据。
- 本地领先时保留当前提交；远端领先时快进；双方分叉且有共同祖先时执行保留双方提交的 merge。可能产生一条合并提交，需要真实作者身份；签名和 hook 要求继续生效。
- 以冻结提交号和明确 refspec 普通推送，只更新指定远端分支，不推标签和其它子模块/父仓。无关历史、浅克隆缺少祖先或独立快照停止。
- 推送失败也先读回服务端，处理“服务端已接受，但连接在确认前断开”；提交号相同才认定成功。网络或并发非快进最多进行三轮抓取、整合和普通推送；鉴权、权限、规则拒绝直接停止。
- 推送成功后再次确认本地分支、HEAD、工作树与服务端 OID；任何不匹配均失败，不用 `push` 的表面成功代替验收。
- 并发拒绝同时识别 `incorrect old value provided` 和 `is at … but expected …`，重新获取整合后有限重试。核验成功且 fetch/push 为同一地址、默认或精确 fetch refspec 可证明映射时，以旧 OID 作比较更新本次远端跟踪引用，让 Sourcetree 图及时反映结果；负向映射、符号引用或异端点保留，CAS 失败保留并发值并提示正常 Fetch。
- 只处理当前仓库及选定线路，不递归父子仓，不加入/提交用户未提交改动，不 stash，不重写提交，不强推，不删除已有锁或引用，不禁用安全校验或 hook。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、场景与处置 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 故障现象 | 主要原因 | 本入口处理与解锁判据 |
| --- | --- | --- |
| `non-fast-forward` / `fetch first` | 推送端领先或双方分叉 | 精确抓取，快进/merge，普通推送后 OID 一致 |
| 没有 upstream | 新分支或未配置跟踪 | 按显式参数和现有映射解析；不擅自写 upstream 配置 |
| 多 remote / 多 URL / 通配 refspec | 推送目标不唯一 | 多 remote 选择；多 URL 或不明确映射停止，显式参数可澄清分支 |
| fetch 与 push 地址不同 | 只读上游与发布端分离 | 从 push 端查询并整合，只写 push 端 |
| 工作区、暂存区、子模块有改动 | 尚未审查的本地工作 | 保留并停止，用户正常处理后重跑 |
| merge/rebase/cherry-pick/bisect 未完成 | 原事务尚未结束 | 报具体标记，保留现场，不代为 abort 或重置 |
| `index.lock` / `cannot lock ref` | 活跃进程、残留锁或引用路径问题 | 不自动删除；先核查原进程，必要时使用专用 Commit/Fetch 修复动作 |
| 实际合并冲突 | 两边改动重叠 | 保留冲突与 `MERGE_HEAD`，完成正常冲突处理后重跑 |
| 游离、未初始化、bare、无关历史 | 无明确工作分支或根历史不兼容 | 停止；先明确已有工作分支/正确发布目标 |
| 浅克隆缺共同祖先 | 必要历史未取得 | 停止，另行确认后补全历史；不误认无关根后强行合并 |
| OC `byPods` → Gitee / `Gitee@snapshot` | Gitee 独立快照发布链 | 先于联网阻断，继续使用专用快照工具 |
| SSH/HTTPS 鉴权失败 | key、agent、凭据或账户不一致 | 报 `authentication`，核对对应主机和账户；不清空凭据 |
| 403 / 404 / repository not found | 地址错误、私仓无访问或写权限不足 | 报 `permission`，核对地址、写权限、组织 SSO 与令牌范围 |
| 主机指纹 / TLS 失败 | 信任链、证书或时间异常 | 报 `trust`，核对真实指纹和证书；不关闭校验 |
| 保护分支 / 仓库规则 / secret scanning | 平台策略不允许直接发布 | 报 `policy` / `secret`，按平台 PR、检查或秘密清理流程处理 |
| 大文件 / pack / LFS / quota | 对象超限、对象缺失或额度不足 | 分别报 `size` / `lfs` / `quota`，指向真实服务端输出；不伪装成本地缓冲问题 |
| 作者 / 签名失败 | 身份配置、签名工具或 agent 不可用 | 报 `identity` / `signature`，由用户恢复真实身份和签名环境 |
| hook 拒绝 | 项目本地或服务端规则 | 保留具体输出，报 `hook`；不跳过 hook |
| 磁盘 / 权限 / 对象损坏 | 本地存储或对象数据库异常 | 报 `filesystem` / `objects`，先备份定位；不删除对象或批量改权限 |
| 短暂连接错误 / 限流 / 服务端错误 | DNS、传输链路或服务异常 | 报 `network`，有限重试并先核对服务端是否已接受，不修改代理 |
| 未知厂商错误 | 无法可靠分类 | 报 `unknown`，保留原错误和非零状态，提供日志继续排查 |

本入口提供统一检查、恢复和诊断路径，不能由本地脚本解除服务端权限、保护规则或容量限制。只诊断成功表示完成了检查与远端读取，不证明用户具有写权限，也不执行 hook。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、日志、恢复与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 公开入口日志为 `%TEMP%/JobsSourceTree-push-repair-<时间>-<唯一值>.log`，URL 中的凭据、查询和片段在展示及落盘时脱敏。
- 实际修复前记录原 HEAD、分支、remote、目标分支到 Git 实际管理目录的 `jobs-push-repair/<时间>-<唯一值>.txt`，每轮追加计划提交及最终核验提交。原提交也在正常分支 reflog 中；不新建本地备份分支。
- 自身互斥文件为 Git 管理目录的 `jobs-push-repair.lock`，正常退出/异常结束释放；进程被强制杀死后可能留下该文件，应先确认原进程已结束再备份处理。不会删除别人的锁。
- 临时获取引用在退出时用 Git 原生命令按预期 OID 清理；记录、合并提交和冲突现场保留。脚本不自动回退合并，避免破坏已发布内容。
- 成功返回 `0`，任何拒绝、冲突或核验失败返回非零；取消未执行业务。完整测试入口见 [隔离回归说明](../Tests/PushRepair.Tests.ps1/README.md)。
- 可在 MacOS 的 `pwsh` 验证模块和本地 bare remote 流程；这不代表 Windows 原生 `.cmd`、凭据管理和 Sourcetree 菜单已完成实机验收。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> `.cmd`／`.bat` 入口内嵌完整会话守护：黑底白字及强调色保护就绪或明确降级后才开始业务，全部退出路径同步等待恢复回执；同时核对父进程身份。原 PowerShell／Python 启动命令和业务参数不经过再次解析，保护初始化后恢复进入时的延迟扩展模式，原业务自己的 `setlocal` 保留；嵌套 PowerShell 复用同一会话保护。守护脚本只写入本轮系统临时目录，成功恢复后清理控制文件。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
