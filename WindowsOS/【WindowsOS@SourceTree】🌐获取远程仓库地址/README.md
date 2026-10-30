# 【WindowsOS@SourceTree】🌐获取远程仓库地址

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

> 读取所有 remote 的全部 fetch / push 地址并按原始 URL 去重；单地址直接复制，多地址在独立终端用 [**fzf**](https://github.com/junegunn/fzf) 选择后复制。适用于 [**Windows**](https://www.microsoft.com/windows/) [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1 或更高版本。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击本目录 `.cmd`，或从 PowerShell 显式传入目标：

```powershell
.\Run.ps1 -Target 'D:\Projects\My Project'
```

- 终端独立运行显示内置自述后回车继续；`Ctrl+C` 取消。fzf 面板回车选择，`Esc` / `Ctrl+C` 取消；无匹配、空结果或失败均不复制。
- 通过菜单安装器挂载时传 `-SourceTree -Target "$REPO"`。只有一个去重地址时直接复制；多个地址或 Git 不可用时才打开独立 PowerShell 终端，先回车确认再选择/处理依赖。Sourcetree 输出窗口不等待输入；终端保留退出码。
- 需要同时携带本仓完整 `WindowsOS` 目录；依赖随包 `../Scripts`，不依赖原电脑绝对路径。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、用途与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 从目标普通目录或文件定位最近 Git 工作树；目标及祖先目录为链接时拒绝。隔离继承的 Git 仓库寻址变量，结束后恢复调用环境，避免误取其他仓库。
- 枚举每个 remote 的 `git remote get-url --all` 与 `--push --all`；相同原始 URL 合并为一行并保留来源标签。没有远程地址时停止，不默认选 `origin`。
- 失败返回非零退出码；日志位于 `%TEMP%/JobsSourceTree*`，复用功能日志在 `%TEMP%/JobsSourceTree/logs`。

具体兼容差异、排除项与验证范围见 [Windows 总览](../README.md)。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、功能、选项与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 一个 remote 配多条 URL、多个 remote 及单独的 push URL 都参与选择；隐式 push 与 fetch 相同只显示一次。SSH 与 HTTPS 即使指向同一个仓库，也按不同原始 URL 分别保留。
- 状态、日志和 fzf 对所有协议的认证信息、查询参数和片段脱敏；剪贴板保留选中原始 URL，不使用显示文本反推地址。本动作只复制，不修改 remote；打开网页使用配对的[打开远程仓库动作](../【WindowsOS@SourceTree】🌍打开远程仓库地址/README.md)。
- `-Target` 未给出时，终端使用启动时当前目录；Sourcetree 必须传目标，缺失即停止。`-Option`、`-Value` 为兼容保留，本动作不使用。需要完整携带 [公共模块](../Scripts/README.md)，不依赖已安装的 Finder 扩展。
- Git 每次检查可执行路径与 `--version`；只在多地址选择时检查 fzf 版本、帮助和实际所需参数。健康工具直接复用，不要求 WinGet。
- 缺失或损坏时只在终端检查 [**WinGet**](https://learn.microsoft.com/windows/package-manager/winget/) 的 `--version` / `--info`；回车允许从官方 `winget` 源以 `--scope user` 安装/修复 `Git.Git` 或 `junegunn.fzf` 一次，任意字符取消。随后合并当前进程 PATH 并复检；失败停止，不递归重试、不降级为手输编号。
- WinGet / App Installer 不可用时停止并给出官方修复入口，不自动安装包管理器、不主动提权、不执行全局升级。工具安装可能更新当前用户工具与 PATH；脚本自身不持久改写环境。
- fzf 运行期间暂时隔离 `FZF_DEFAULT_OPTS` 等默认项，防止额外多选/执行绑定干扰，结束后恢复。当前回归只使用临时 Git 与模拟选择/安装器；Windows 实机菜单、剪贴板、浏览器和真实依赖安装另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
