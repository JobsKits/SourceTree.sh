# Windows 动作隔离验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

`SourceTree.Tests.ps1` 仅建立临时目录与本地 bare remote，不访问真实托管远端；使用 Windows PowerShell 5.1 或 PowerShell 7 与 Git。测试断言在各自模块上下文定义，Git 提示性 stderr 不替代真实退出码判断。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

见 [Windows 总览](../README.md) 的功能对照与运行命令。业务日志在系统临时目录；不直接运行内部模块作为用户入口。

```powershell
& ./SourceTree.Tests.ps1
& ./Safety.Tests.ps1
```

`SourceTree.Tests.ps1` 使用隔离 Git 配置与本地 file 传输，覆盖 CP437 / CP936 终端下的中文 Git 根目录、成功与失败后的编码恢复、源码保留与失败续跑；临时 bare 仓的拒绝钩子仅在 Unix 分支运行。macOS 完整分支为 29 项检查，Windows 跳过 Unix 钩子分支，以终端实际检查数为准。`Safety.Tests.ps1` 覆盖 92 项危险确认、来源脱敏、命令退出码及全部 27 个 CMD 入口；在 Windows 额外用假命令实际验证带参数失败及时返回原退出码。2026-10-26 在 Windows 11 ARM64 / Windows PowerShell 5.1.26100.9711 完成原生隔离回归：SourceTree 25 项、Safety 93 项通过；包含 CP437 / CP936 编码和真实 CMD 失败退出分支。该结果不包含真实 Sourcetree 菜单安装、业务远端或 x64 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
