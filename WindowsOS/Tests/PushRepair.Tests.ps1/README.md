# PushRepair 隔离回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与范围](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> [PushRepair.Tests.ps1](./PushRepair.Tests.ps1) 使用真实的临时 [**Git**](https://git-scm.com/) 工作树和本地 bare remote，验证独立 Push 修复模块；不操作用户项目或托管服务。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从仓库根运行，需要 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1+ 或 `pwsh`，以及已安装 Git：

```powershell
pwsh -NoProfile -File ./WindowsOS/Tests/PushRepair.Tests.ps1/PushRepair.Tests.ps1
```

- 在系统临时目录下建立 `jobs-push-repair-tests-<唯一值>`，仅允许 `file` 协议，隔离系统/全局 Git 配置，结束后恢复原进程环境。
- 验证只诊断、当前/远端领先、双方分叉、真实冲突保留、dirty、锁、游离、bare、无关历史、OC 快照、多线路歧义、显式线路、上游和目标异名、pushurl 分离、多 URL 拒绝、首次发布、标签范围及故障分类。
- 另覆盖真实 pre-push 窗口的远端旧值竞争、默认/精确跟踪映射刷新、负向映射/符号跟踪引用/异端点保留，以及 CAS 失败不覆盖并发 fetch 值。
- 正常修复检查精确 OID 一致，没有额外本地分支，并清理自身临时引用/互斥文件；拒绝场景检查已知改动和服务端保留。
- `Ctrl+C` 可中断；测试目录保留便于查证，路径在成功行打印。失败抛异常并返回非零。
- 模块回归不等于 Windows `.cmd`、GUI 菜单、真实账户权限或实际托管平台策略验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
