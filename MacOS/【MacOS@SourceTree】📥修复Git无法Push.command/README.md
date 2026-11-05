# 📥 修复 Git 无法 Push

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

针对当前仓库的一条推送线路，先检查状态和目标，精确获取真实推送端的分支，安全快进或合并，普通推送后读取服务端提交号核验。适用于 [**Sourcetree**](https://www.sourcetreeapp.com/) 原生 Push 的 `non-fast-forward`、`fetch first`、上游缺失等问题；不调用会递归暂存／提交父子仓的逐层推送入口。

“通用”表示统一识别、安全恢复和明确分流，不承诺绕过服务器权限或自动决定冲突内容。[**Git**](https://git-scm.com/docs/git-push) 的普通推送保护双方历史；[官方非快进处理](https://docs.github.com/en/get-started/using-git/dealing-with-non-fast-forward-errors)需要先获取并整合远端提交。

## 一、运行与确认

从本包目录运行：

```shell
/bin/zsh './【MacOS@SourceTree】📥修复Git无法Push.command' '/path/to/repository'
/bin/zsh './【MacOS@SourceTree】📥修复Git无法Push.command' '/path/to/repository' Github main --diagnose
/bin/zsh './【MacOS@SourceTree】📥修复Git无法Push.command' '/path/to/repository' Github main --yes
```

| 参数 | 行为 |
| --- | --- |
| 仓库路径 | 可省略，使用启动目录；给文件路径时定位所属工作树 |
| remote / 远端分支 | 可省略；优先明确参数，其次已有 pushRemote、pushDefault、上游、精确 push refspec；唯一候选自动复用，歧义由菜单选择或停止 |
| `--diagnose` | 只读预检与远端查询，不 fetch、不合并、不推送、不设置上游 |
| `--yes` | 调用者明确授权已显示的安全整合与普通推送，可用于自动化；不能代替多候选选择或绕过保护 |
| `--terminal-session` | Sourcetree 转交终端的内部标记，不授予执行权限 |
| `--help` | 显示用法 |

- Sourcetree 动作传入 `$REPO` 并打开独立 Terminal；动作输出窗口不等待输入。
- 终端先显示内置自述，回车进入检查，再在计划菜单中选择“执行安全整合并推送”；默认取消，方向键／Tab 移动、回车选择，Ctrl+C 中断。缺少交互终端时必须显式指定 `--yes` 或 `--diagnose`。
- 菜单依赖可用的 [**fzf**](https://github.com/junegunn/fzf)。已明确传目标并使用 `--yes` 或 `--diagnose` 时不依赖 fzf；缺失不会自动安装工具。
- 只处理选定仓库、已有本地分支与一条线路；不会扩到父仓、子仓、其它 remote 或标签。多 URL、mirror、无法明确的 refspec 停止；明确指定分支可避开隐式映射歧义。
- `pushurl` 与 fetch URL 不同时，以真正的 push URL 查询和获取，不把 fetch 端的另一条历史误合入；URL 重写必须稳定，不能对已展开地址二次改写。

## 二、场景与解锁判据

| 场景 | 原因／故障现象 | 独立处理与解锁判据 |
| --- | --- | --- |
| P01–P03 工作树／分支／提交 | 非仓库、bare、游离 HEAD、尚无提交 | 停止并指出缺项；回到明确的已有分支并正常提交后再运行，不自动建分支 |
| P04 未完成操作 | merge、rebase、cherry-pick、revert、bisect、sequencer 现场 | 保留原操作，按 `git status` 完成或由用户明确取消，再重跑 |
| P05 锁与并发 | index／HEAD／FETCH_HEAD／packed-refs／config 锁、另一修复会话 | 保留锁，检查持锁进程与归属；不以年龄判定失效，不自动删除锁 |
| P06 未提交内容 | 已暂存、未暂存、未跟踪或子模块改动 | 停止；在 Sourcetree 审查并提交或自行妥善保存，不自动 `add -A`、stash 或清理 |
| P07 浅克隆 | 缺少可靠祖先历史 | 确认来源后显式补全，再判定；不自动大规模下载 |
| P08 目标映射 | 缺 remote／上游、多个 remote、异名目标、pushurl、refspec | 明确单线路映射，缺上游也能显式推送；不顺手更改配置。OC main／byPods 不交叉，Gitee 独立快照转专用入口 |
| P09 历史关系 | 仅领先、仅落后、双方分叉、远端分支不存在 | 精确 fetch 到 FETCH_HEAD，避开旧跟踪引用路径冲突；领先直接推，落后 `--ff-only`，分叉保留双方祖先合并；空端必须明确确认分支 |
| P10 并发非快进 | 预检后服务端又有提交 | 重新查询、获取、整合，最多三轮；不强推 |
| P11 鉴权 | SSH publickey、凭据无效、SSO | 输出认证方向；用户通过可信账号工具修复后重跑，不删凭据、不采集密钥 |
| P12 地址／写权限 | 404、403、账号无写权限、仓库不存在 | 确认真实地址、当前账号和平台授权；SSH 连通不能替代写权限 |
| P13 保护与签名 | GH006／GH013、规则、要求 PR／签名 | 按平台原始提示通过 PR、签名、审批；不绕过规则 |
| P14 敏感内容 | push protection、secret scanning | 按平台定位、撤销泄露凭据；历史清理另行评审 |
| P15 大文件／LFS／配额 | 大对象、LFS 缺失或上传拒绝、仓库超限 | 区分原始服务端原因；检查对象、LFS 与容量，不改历史或盲增缓冲区 |
| P16 hook | pre-push／pre-receive／remote rejected | 保留 hook 与失败码，按错误修复；不使用 `--no-verify` |
| P17 引用／文件系统 | cannot lock ref、无法创建文件 | 精确 fetch 避开跟踪引用冲突；仍失败时引导现有 Fetch 修复或锁／磁盘排查，不删除元数据 |
| P18 信任 | TLS 证书、SSH 主机指纹 | 核对来源、系统时间及可信指纹；不关闭验证 |
| P19 网络 | 超时、断线、502／503／504 | 明确短暂错误最多三次读取重试；push 失败先查远端是否已接收，避免把已成功误判失败；不改代理 |
| P20 对象库 | corrupt、bad object、unpacker error | 保留现场，按 `git fsck --full` 定位；可信来源补对象或隔离重克隆，不自动删对象 |
| P21 身份／签名 | 合并时缺邮箱、签名失败 | 以本仓正确身份或已有签名资产完成；不伪造身份、不关闭签名 |
| P22 存储 | 空间不足、只读文件系统 | 检查相关卷与目录权限，不清理用户内容或递归改权限 |
| P23 无共同祖先 | 独立快照、远端重建、错误仓库 | 停止，不自动 `--allow-unrelated-histories` |
| P24 合并冲突 | 文本／二进制／子模块内容无法自动决定 | 列出冲突，保留 merge 现场；正常解决并提交后重跑，不自动选 ours／theirs |
| P25 结果核验 | push 返回 0 或传输断线后结果不明 | 仅服务端目标 OID 与冻结的本地 HEAD 完全相同才成功；本地并发变化也报未达到一致 |
| P99 未知 | 未识别的平台／Git 错误 | 脱敏保留原始诊断与失败码，明确未完成，供后续按证据扩展 |

## 三、日志、恢复与边界

- 每轮使用临时目录 `jobs-push-repair.XXXXXX/run.log`，文件权限由 `umask 077` 限制。终端与日志统一脱敏 URL 认证信息、查询参数与常见敏感字段，不转储环境或完整 Git 配置。
- 写操作前在实际工作树 gitdir 取得 `jobs-push-repair.lock`，正常退出和可捕获中断释放本进程锁。强制结束可能留锁，核对目录内 PID 与进程归属后人工处理；不自动移除未知锁。
- 合并前的 HEAD、目标与共同祖先写入日志；历史仍通过祖先链和 reflog 可查。不创建备份分支、不强推、不删除分支或标签。服务端恢复需按实际历史另行评审，不提供自动破坏性回滚。
- 冲突保留 `MERGE_HEAD` 与索引；正常审查并完成提交后再运行。中断后先检查 `git status`，新运行不会跳过未完成操作。
- 不更改鉴权、主机信任、Git 全局配置、代理、hook 或平台规则；不会自动迁移大文件历史、生成快照、创建 PR。服务端限制与冲突语义需要相应权限或人工决定。

## 四、验证入口

从仓库根运行：

```shell
/bin/zsh './MacOS/Tests/PushRepair.Tests.zsh/PushRepair.Tests.zsh'
```

测试使用隔离 Git 配置、临时工作树与本地 bare 远端，不对真实平台推送。真实用户仓库的运行结果另记，不能用隔离通过代替平台权限、网络、规则或 Windows 原生菜单验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
