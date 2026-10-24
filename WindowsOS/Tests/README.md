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

`SourceTree.Tests.ps1` 仅建立临时目录与本地 bare remote，不访问真实托管远端；需要 PowerShell 7 / Git，测试业务实现仍以 Windows PowerShell 5.1 兼容语法编写。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

见 [Windows 总览](../README.md) 的功能对照与运行命令。业务日志在系统临时目录；不直接运行内部模块作为用户入口。

```powershell
& ./SourceTree.Tests.ps1
& ./Safety.Tests.ps1
```

`SourceTree.Tests.ps1` 使用隔离 Git 配置与本地 file 传输，仅运行临时 bare 仓内的测试拒绝钩子，覆盖 19 项 Git、源码保留与失败续跑检查。`Safety.Tests.ps1` 覆盖 92 项危险确认、来源脱敏、命令退出码及全部 27 个 CMD 入口；在 Windows 额外用假命令实际验证带参数失败及时返回原退出码。macOS 上跳过原生 CMD 分支，不代表 Windows PowerShell 5.1 或桌面菜单已经实机验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
