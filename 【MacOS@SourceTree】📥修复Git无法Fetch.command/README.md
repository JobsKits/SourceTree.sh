# `【MacOS@SourceTree】📥修复Git无法Fetch.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

> 这是一个挂载到 [**Sourcetree**](https://www.sourcetreeapp.com/) 的 Git Fetch 修复动作。它专门处理远端分支在 `foo` 与 `foo/bar` 之间迁移后，本地远端跟踪引用的文件/目录冲突。

## 一、问题性质 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

这是 Git 远端跟踪引用的经典“D/F conflict（目录/文件冲突）”。它不是每天都会遇到的高频错误，但在上游经常整理分支命名的大型仓库中会稳定重现，属于适合脚本化的典型故障。

即使使用者从不修改业务代码，`git fetch` 也会持续写入 `.git/refs/remotes` 和 `.git/logs/refs/remotes`。因此，“只拉取”不等于“本地没有状态变化”。

常见成因有两类：

- 分支层级迁移：远端在 `saas` 与 `saas/retire-flyway` 之间切换，旧引用文件挡住新目录。
- 大小写映射碰撞：远端 Linux 文件系统可以同时保留 `SaaS` 和 `saas/retire-flyway`，但 MacOS 默认文件系统会把 `SaaS` 与 `saas` 视为同一路径。

分支层级迁移的典型过程：

1. 远端原来存在分支 `saas`。
2. 本地 Fetch 后生成 `origin/saas` 和对应 reflog 文件。
3. 上游删除 `saas`，改为 `saas/retire-flyway`。
4. 本地旧 reflog 文件没有完全清理，但新分支要求 `saas` 是目录。
5. Fetch 因 `Not a directory` 或 `exists; cannot create` 失败。

## 二、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- Fetch 报错包含 `refs/remotes/...`、`logs/refs/remotes/...` 和 `Not a directory`。
- Fetch 报错包含 `cannot lock ref`、`exists; cannot create`。
- 上游把单层分支改成同名前缀的分层分支，例如 `release` 改为 `release/v2`。
- 上游反向把分层分支改成单层分支，例如 `release/v2` 改为 `release`。
- 远端同时存在只有大小写差异的同名前缀，例如 `SaaS` 与 `saas/retire-flyway`。
- 工作区完全没有修改，但 Sourcetree Fetch 仍无法刷新远端分支。

脚本不处理以下问题：

- 网络中断、DNS、代理、SSL 或 SSH 认证失败。
- 密码、Token、权限或远端仓库不存在。
- 真实的 `.lock` 并发进程占用、磁盘空间不足或文件系统损坏。
- Pull 合并冲突、本地分支分叉或工作区内容冲突。

## 三、执行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1. 识别 Sourcetree 传入的仓库路径。
2. 优先选择 `origin`；终端模式可作为第二个参数传入其它远端名。
3. 先执行一次正常的 `git fetch --prune`。
4. Fetch 成功时立即结束，不扫描、不备份、不修改额外 Git 元数据。
5. Fetch 失败且命中引用文件/目录冲突时，通过 `git ls-remote --heads` 读取远端真实分支。
6. 执行 `git remote prune`，让 Git 先清理远端已删除的跟踪引用。
7. 从原始错误中提取真正更新失败的分支，只扫描这些分支对应的路径。
8. 仅将仍阻塞目标分支的 loose ref/reflog 文件或目录移入备份区。
9. 再次执行 `git fetch --prune`，并以 Git 退出码判断修复是否成功。

备份目录位于目标仓库的 Git 元数据内：

```text
.git/jobs-ref-conflict-backups/YYYYMMDD-HHMMSS-PID/
├── refs/remotes/...
└── logs/refs/remotes/...
```

## 四、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 4.1、Sourcetree 自定义动作

1. 在 Sourcetree 中选中目标仓库。
2. 运行自定义动作 `📥修复Git无法Fetch`。
3. 脚本使用 `$REPO` 识别仓库，默认处理 `origin`。
4. Sourcetree 模式不等待回车，输出窗口会显示诊断、备份路径和最终结果。

### 4.2、终端独立运行

默认使用仓库的 `origin`：

```shell
'./【MacOS@SourceTree】📥修复Git无法Fetch.command' '/path/to/repository'
```

显式指定其它远端：

```shell
'./【MacOS@SourceTree】📥修复Git无法Fetch.command' '/path/to/repository' 'upstream'
```

终端模式会先打印脚本内置自述，按回车后才执行 Fetch。

## 五、安全边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 脚本会更新远端跟踪引用，这是 Fetch 本身的正常行为。
- 脚本不执行 `git pull`，不会把远端提交合并到当前分支。
- 脚本不执行 `git add`、`git commit`、`git push`、`git reset` 或 `git checkout`。
- 脚本不修改工作区文件、Git 索引、本地分支指向或提交历史。
- 冲突元数据不直接删除，而是移入 `.git/jobs-ref-conflict-backups` 便于人工追溯。
- 脚本只在 Fetch 输出明确命中远端跟踪引用的文件/目录冲突时自动修复；其它错误保持原样并返回失败。
- 大小写碰撞时，被备份的 reflog 可能仍对应有效远端跟踪分支；脚本不将其删除，只为当前 Fetch 移开路径阻塞。

## 六、日志文件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

运行日志写入系统临时目录中的：

```text
【MacOS@SourceTree】📥修复Git无法Fetch.log
```

日志保留两次 Fetch 输出、远端选择、备份路径、阻塞项数量和最终退出结果。

## 七、常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 7.1、没有冲突时运行会怎样？

脚本就是执行一次正常的 `git fetch --prune`。Fetch 成功后直接结束，不会创建元数据备份目录。

### 7.2、脚本会自动恢复备份吗？

不会。被移开的对象都是当前正在阻塞目标分支的远端跟踪元数据；分支层级迁移时它通常已失效，大小写碰撞时它也可能仍对应有效分支。Fetch 成功后旧内容继续保留在备份区，需要时再人工核对。

### 7.3、为什么不把这个逻辑塞进 Commit 修复脚本？

Commit 修复脚本负责工作区、索引和子模块预检；本脚本负责远端跟踪引用和 Fetch 元数据。两者影响边界不同，拆成独立 Sourcetree 动作更安全、更容易排查。

### 7.4、大小写碰撞修复后还可能再出现吗？

可能。远端同时保留 `SaaS` 和 `saas/...` 本身就与 MacOS 默认的大小写不敏感文件系统存在映射冲突。脚本能备份当前阻塞并完成 Fetch，但上游再次更新另一个大小写分支时仍可能触发；彻底解决需要上游统一分支大小写命名。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
