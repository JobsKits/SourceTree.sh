# 【WindowsOS@SourceTree】📥修复Git无法Commit

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行](#jobs-toc-heading-2)
- [二、用途与结果](#jobs-toc-heading-3)
- [三、功能、选项与边界](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> 检查 Git 元数据、锁及 Markdown 目录过滤器，修复升级或迁移后失效的 Node 路径。适用于 [**Windows**](https://www.microsoft.com/windows/) [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1 或更高版本。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击本目录 `.cmd`，或从 PowerShell 显式传入目标：

```powershell
.\Run.ps1 -Target 'D:\Projects\My Project'
```

- 显示内置自述后回车继续；`Ctrl+C` 取消。危险操作精确输入 `YES`。
- 通过菜单安装器挂载时传 `-SourceTree -Target "$REPO"`，入口打开独立终端确认，结果和退出码保留在新窗口。
- 需要同时携带本仓完整 `WindowsOS` 目录；依赖随包 `../Scripts`，不依赖原电脑绝对路径。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、用途与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 校验明确的目标目录与所需工具，缺失时停止；目标及祖先目录为链接时拒绝。
- 检查 Git 元数据与锁，确认后归档残留锁；在读取状态或执行暂存预检前，先检查本仓目录过滤器。
- 失败返回非零退出码；日志位于 `%TEMP%/JobsSourceTree*`，复用功能日志在 `%TEMP%/JobsSourceTree/logs`。

具体兼容差异、排除项与验证范围见 [Windows 总览](../README.md)。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、功能、选项与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 解析真实 Git 目录，先执行 `git fsck --no-reflogs --connectivity-only` 检查对象连通性。
- 存在 index.lock 时，要求无 Git / SourceTree 进程且可排他打开锁；随后精确 `YES` 才移动为带时间戳的 backup。
- 锁处理后、读取状态前检查 `filter.jobs-markdown-toc`。无配置直接跳过，不自动接入或安装依赖；从 PATH、Program Files 等位置重新发现健康 Node，保留稳定入口路径。
- 仅处理 `.jobs-markdown-toc/MarkdownToc.mjs` 标准驱动，并要求本仓 `jobs-markdown-toc.json` 安装记录、local 配置与有效配置一致。`process` 冲突、外部改动、未知命令、链接或跨仓清单均停止，保留现场。
- 旧 Node 不可用或固化在 Homebrew Cellar 时，在真实 Git 元数据目录创建唯一 `jobs-filter-backup-*` 精确备份；只更新 `clean`、`smudge` 和安装记录，保留 `required=true`。不修改全局配置，不通过禁用过滤器绕过故障。
- 对清单全部文档执行真实 Git clean / smudge 双向探针，使用独立临时对象目录并在结束后清理；校验结果必须与本仓转换器及当前 `[toc]` 正文一致。失败回滚本轮字段，遇并发修改保留并提示备份位置；不自动 restore 文档。
- 检查 status、递归 submodule status 和 `git add --dry-run --all`，传播诊断错误。此次修复只解除过滤器及入口阻塞，不验证实际提交 hook 或签名。
- 不自动执行 commit、真实 add、不重建索引，不覆盖 gitlink；子仓路径错误仍需按诊断处理。
- `-Target` 未给出时使用启动时当前目录；`-Option`、`-Value` 只在回退动作中有业务含义。需要完整携带 [公共模块](../Scripts/README.md)，不依赖已安装的 Finder 扩展。
- 验证：PowerShell AST 与真实 Git 隔离回归覆盖失效路径修复、双向转换、幂等及失败保护；Windows 原生控制台与 Windows PowerShell 5.1 实机仍需另验。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> `.cmd`／`.bat` 入口内嵌完整会话守护：黑底白字及强调色保护就绪或明确降级后才开始业务，全部退出路径同步等待恢复回执；同时核对父进程身份。原 PowerShell／Python 启动命令和业务参数不经过再次解析，保护初始化后恢复进入时的延迟扩展模式，原业务自己的 `setlocal` 保留；嵌套 PowerShell 复用同一会话保护。守护脚本只写入本轮系统临时目录，成功恢复后清理控制文件。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
