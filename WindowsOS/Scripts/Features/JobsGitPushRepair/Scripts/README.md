# JobsGitPushRepair 模块

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、结构与调用](#jobs-toc-heading-2)
- [二、验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> [Action.psm1](./Action.psm1) 提供当前仓库单条线路的 Push 预检、目标解析、历史整合、普通推送和提交号核验，由 [公共调度](../../../SourceTree.psm1) 的 `push-repair` 动作调用。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、结构与调用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 独立 [**PowerShell**](https://learn.microsoft.com/powershell/) 模块；导出 `Repair-JobsPush` 和只读的错误分类 `Get-JobsPushFailure` |
| [README.md](./README.md) | 模块结构、依赖、调用边界和验证入口 |

```powershell
Import-Module './Action.psm1' -Force -DisableNameChecking
Repair-JobsPush -Repository 'D:\Projects\My Project' -Remote Github -Branch main -Diagnose
```

- 模块不单独弹菜单或展示初始确认；用户应通过 [公开动作入口](../../../../【WindowsOS@SourceTree】📥修复Git无法Push/README.md) 确认后调用，自动化调用方必须自行保证同等授权。
- 仅依赖 PowerShell 5.1+ 与可用 [**Git**](https://git-scm.com/)。多个远端且缺少参数时需要 [**fzf**](https://github.com/junegunn/fzf) 和可交互终端；不安装任何工具。
- `-Diagnose` 只本地检查和查询远端，不写仓库。真实修复只更新明确目标；原 HEAD 审计位于 Git 管理目录 `jobs-push-repair/`，完整行为和故障表以公开入口 README 为准。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从仓库根运行：

```powershell
pwsh -NoProfile -File ./WindowsOS/Tests/PushRepair.Tests.ps1/PushRepair.Tests.ps1
```

测试只创建系统临时目录和本地 bare remote，保留测试证据；不访问托管服务或用户业务仓库。跨平台模块回归与 Windows 原生入口/菜单验证分别记录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
