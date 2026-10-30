# Windows 动作内部实现

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

`SourceTree.psm1` 分发 28 项业务（按 `../actions.json` 登记计，2026-10-28）；`Features/` 携带五套 Windows Flutter 模块（体检、生成、依赖收集、打包和运行设备选择），由本仓独立日志适配。原模块来源为本工作区 `OS@Extension/WindowsOS@Extension`，只复制 Jobs 自维护源码，后续在此独立携带。

远程复制与打开共用全部 fetch/push 地址的原值去重、脱敏展示、单地址直达和多地址独立终端 fzf。只在缺失分支检查 WinGet、确认后用户范围安装/修复一次并复检；不在 Sourcetree 动作进程内等待输入。远程动作隔离继承的 Git 仓库寻址变量并恢复，防止读取其他仓库；浏览器只接收安全转换后的 HTTP(S) 地址。功能说明见[复制](../【WindowsOS@SourceTree】🌐获取远程仓库地址/README.md)与[打开](../【WindowsOS@SourceTree】🌍打开远程仓库地址/README.md)。

原生命令执行期间使用 UTF-8，避免系统 OEM 代码页损坏中文 Git 路径；命令成功或失败后恢复调用前的终端与管道编码，不持久修改控制台配置。对应夹具见[测试说明](../Tests/README.md)。

鸿蒙动作 `ohos` 固定转交打包模块 `Invoke-JobsPackagerHarmonyBuild -Type all`，一次同时构建并检查 HAP + APP，不受 `OHOS_BUILD_TARGET` 缩减；模式沿用 `BUILD_MODE`，默认 release。公共调度把会话日志路径传给构建模块，包含工具链与两类构建输出，失败停止且恢复临时环境。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

见 [Windows 总览](../README.md) 的功能对照与运行命令。业务日志在系统临时目录；不直接运行内部模块作为用户入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
