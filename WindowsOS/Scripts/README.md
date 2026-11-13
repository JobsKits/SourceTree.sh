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

**Flutter SDK网络预检：** 下载／首次Dart自举／precache前，随包网络模块以真实小Range验证来源、TLS、字节和吞吐并择优；显式storage、Pub和代理（含空值）保留，AUTO仅核验官方／CFUG同对象及当前已配置代理，不猜端口、不改系统代理或Git。当前任务短期复用；真实获取失败会降权坏路线、轮换其它已验证候选并持续重试。FVM按实际api context来源处理，能力允许时Git与Dart制品分阶段；用户fork不改源。原生BITS按真实WinINET通道衡量，PAC未能有界解析时保留既有通道并明确未测速。详细边界见[随包选路模块](./SdkDownloadRoute.ps1/README.md)。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

[JobsGitPushRepair](./Features/JobsGitPushRepair/Scripts/README.md) 是独立的 Push 诊断与修复模块，由 `push-repair` 调度；只处理当前仓库选定线路，保护本地内容并在普通推送后核验服务端提交号。
