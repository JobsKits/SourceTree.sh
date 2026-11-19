# Push 修复隔离回归

> 使用临时工作树和本地 bare 远端调用真实生产入口；禁止 SSH／HTTP 传输，不操作用户仓库。

- 入口：[PushRepair.Tests.zsh](【MacOS】PushRepair.Tests.zsh)。依赖 MacOS 自带 zsh、Git、Perl、shasum 与基础命令。
- 从本目录执行 `zsh 【MacOS】PushRepair.Tests.zsh`；可传入另一份待测生产脚本的绝对路径。
- 32 个独立场景覆盖领先、落后、分叉、本地文件迁入同名目录与远端无关修改合并、冲突、未提交内容、游离与未出生分支、无共同历史、空远端、多 remote、上游缺失、pushurl 分离、只读诊断、锁、保护规则、快进与 ort 分叉合并中的被忽略文件碰撞、新增路径祖先文件／软链、隐藏子模块改动、assume-unchanged／skip-worktree 隐藏索引、并发远端更新、应答丢失、损坏索引、未完成操作、bare 仓库、多推送 URL、mirror、强制 refspec、额外标签控制与脱敏。
- 并发场景在本地 `pre-push` 时由另一工作树真实推送，验证旧 OID 被拒后重新获取并合并；应答丢失场景由受控 Git 包装器在真实推送已成功后报告断连，验证先核对服务端而不重复推送。
- 只读场景逐项比较原始索引、配置和引用，确认不创建 `FETCH_HEAD` 或修复锁；冲突与 ignored 文件碰撞分别核对现场和正文，不能只以退出码判断保护成功。
- 成功场景核对本地和服务端精确 OID、工作区状态；默认 fetch／push 来源一致时额外确认 `origin/main` 已刷新到 HEAD，来源分离时保持原跟踪语义。
- 测试只在 `/tmp/jobs-push-repair-tests.*` 新建夹具，隔离用户与系统 Git 配置，并限制 `file` 协议；所有提交、强制构造无关历史和 hook 均仅用于本次夹具。
- 运行后保留逐例 `result.log`、`subject.log` 和仓库用于排障；任何失败返回非零。隔离通过不代表真实平台、Terminal 菜单或 WindowsOS 原生验收。
