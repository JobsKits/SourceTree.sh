# Windows Sourcetree 脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与安装](#jobs-toc-heading-2)
- [二、功能对照](#jobs-toc-heading-3)
- [三、平台排除与差异](#jobs-toc-heading-4)
- [四、验证](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> 27 个原生 Windows 动作和一个菜单安装入口，使用 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1+。可双击各包 `.cmd` 或显式传入工程路径。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与安装 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 双击 `Install-Menu.cmd` 安装 [**Sourcetree**](https://www.sourcetreeapp.com/) 当前用户菜单。先退出 Sourcetree；安装保留已有标题和未知动作，写前保存精确备份，`-Mode Restore` 检测配置未变化后恢复。配置位置以 [Atlassian 官方说明](https://support.atlassian.com/sourcetree/kb/edit-sourcetree-configurations-without-opening-the-application-windows/) 为准。
- 菜单传入 `-SourceTree -Target "$REPO"`。动作进程转交独立 PowerShell，终端内打印自述并回车确认；危险操作精确输入 `YES`。进程级 `-ExecutionPolicy Bypass` 不修改系统策略。
- 请完整携带 `WindowsOS/`；公共实现与四套复用业务核心均在本目录，不要求原电脑的右键扩展或路径。
- 日志在 `%TEMP%/JobsSourceTree-动作-时间-运行编号.log`，复用模块日志在 `%TEMP%/JobsSourceTree/logs/`；不会把日志放进项目。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、功能对照 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 原功能 | Windows 入口 | 用途 |
| --- | --- | --- |
| ⏬双击下载SourceTree效率脚本 | [Run.ps1](<./【WindowsOS%40SourceTree】⏬双击下载SourceTree效率脚本/Run.ps1>) | 克隆效率脚本到新目录，保留已有库 |
| ⏬只拉取远程代码 | [Run.ps1](<./【WindowsOS%40SourceTree】⏬只拉取远程代码/Run.ps1>) | 同步明确 upstream，再按父仓 gitlink 更新子模块 |
| ♻️修复Flutter项目中文路径 | [Run.ps1](<./【WindowsOS%40SourceTree】♻️修复Flutter项目中文路径/Run.ps1>) | 备份并修复自有 Dart package 指令中的 Unicode 编码 |
| ♻️双击Git（识别子Git） 提交回退 | [Run.ps1](<./【WindowsOS%40SourceTree】♻️双击Git（识别子Git） 提交回退/Run.ps1>) | soft 撤回未推送提交；hard 固定目标并确认 |
| ⚙️收集当前Flutter工程的依赖 | [Run.ps1](<./【WindowsOS%40SourceTree】⚙️收集当前Flutter工程的依赖/Run.ps1>) | 按已解析依赖复制源码并输出独立归档 |
| ⚙️运行授权 | [Run.ps1](<./【WindowsOS%40SourceTree】⚙️运行授权/Run.ps1>) | 仅对可信 Windows 脚本移除下载来源标记 |
| 同步edgetunnel代码后手动升级 | [Run.ps1](<./【WindowsOS%40SourceTree】同步edgetunnel代码后手动升级/Run.ps1>) | 按现有 Wrangler 配置检查身份并确认部署 |
| 用Android Studio打开 | [Run.ps1](<./【WindowsOS%40SourceTree】用Android Studio打开/Run.ps1>) | 使用 Windows Android Studio 打开所选目录 |
| 用Android Studio打开openjdk64-17.0.16 | [Run.ps1](<./【WindowsOS%40SourceTree】用Android Studio打开openjdk64-17.0.16/Run.ps1>) | 仅给新 Android Studio 进程设置已安装 Java17 |
| 用Trae打开@openjdk64-17.0.16 | [Run.ps1](<./【WindowsOS%40SourceTree】用Trae打开%40openjdk64-17.0.16/Run.ps1>) | 仅给新 Trae 进程设置已安装 Java17 |
| 用Trea打开 | [Run.ps1](<./【WindowsOS%40SourceTree】用Trea打开/Run.ps1>) | 使用 Windows Trae 打开所选目录 |
| 用VSCode打开 | [Run.ps1](<./【WindowsOS%40SourceTree】用VSCode打开/Run.ps1>) | 使用 Windows VS Code 打开所选目录 |
| 用VSCode打开@openjdk64-17.0.16 | [Run.ps1](<./【WindowsOS%40SourceTree】用VSCode打开%40openjdk64-17.0.16/Run.ps1>) | 仅给新 VS Code 进程设置已安装 Java17 |
| 用终端打开 | [Run.ps1](<./【WindowsOS%40SourceTree】用终端打开/Run.ps1>) | 在所选目录打开 PowerShell |
| 获取目标绝对地址 | [Run.ps1](<./【WindowsOS%40SourceTree】获取目标绝对地址/Run.ps1>) | 输出并复制目标绝对地址 |
| 🌐获取远程仓库地址 | [Run.ps1](<./【WindowsOS%40SourceTree】🌐获取远程仓库地址/Run.ps1>) | 读取当前 Git 仓库的全部 remote 地址 |
| 🐦Flutter自动化生产代码 | [Run.ps1](<./【WindowsOS%40SourceTree】🐦Flutter自动化生产代码/Run.ps1>) | 按工程配置执行 Flutter 代码生成 |
| 🐦Flutter重新拉取第三方依赖 | [Run.ps1](<./【WindowsOS%40SourceTree】🐦Flutter重新拉取第三方依赖/Run.ps1>) | 使用工程 SDK 执行 flutter pub get |
| 🐦Flutter项目体检 | [Run.ps1](<./【WindowsOS%40SourceTree】🐦Flutter项目体检/Run.ps1>) | 检查工程同源 Flutter/Dart SDK 并执行 doctor |
| 🐦打开：运行Flutter项目 | [Run.ps1](<./【WindowsOS%40SourceTree】🐦打开：运行Flutter项目/Run.ps1>) | 选择 Android、Web 或 Windows 设备运行项目 |
| 📘用Typora打开蓝皮书 | [Run.ps1](<./【WindowsOS%40SourceTree】📘用Typora打开蓝皮书/Run.ps1>) | 使用 Windows Typora 打开项目 README |
| 📥修复Git无法Commit | [Run.ps1](<./【WindowsOS%40SourceTree】📥修复Git无法Commit/Run.ps1>) | 检查 Git 元数据与锁，确认后归档残留锁 |
| 📥修复Git无法Fetch | [Run.ps1](<./【WindowsOS%40SourceTree】📥修复Git无法Fetch/Run.ps1>) | 分阶段 fetch、prune、pack-refs 并传播错误 |
| 📦双击打包Flutter.android | [Run.ps1](<./【WindowsOS%40SourceTree】📦双击打包Flutter.android/Run.ps1>) | 使用工程 SDK 构建 Android APK 和 AAB |
| 📦双击打包Flutter.ohos | [Run.ps1](<./【WindowsOS%40SourceTree】📦双击打包Flutter.ohos/Run.ps1>) | 使用已有鸿蒙适配 SDK 和 ohos 工程构建 HAP |
| 🚀逐层空白提交并Push | [Run.ps1](<./【WindowsOS%40SourceTree】🚀逐层空白提交并Push/Run.ps1>) | 子仓先于父仓，以已有本地分支同步明确远端分支 |
| 🪄配置并运行Magic Resume | [Run.ps1](<./【WindowsOS%40SourceTree】🪄配置并运行Magic Resume/Run.ps1>) | 复用或克隆官方仓库并在当前窗口运行开发服务 |

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、平台排除与差异 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 不创建 iOS 模拟器、Xcode 打开、Flutter iOS / IPA 打包、两类 Pod Install 的 Windows 入口。[Flutter 官方平台要求](https://docs.flutter.dev/platform-integration)明确 iOS 开发限 macOS。对应 6 个 Mac 动作仍在 `../MacOS/`。
- 运行授权使用 `Unblock-File` 去除选定可信脚本下载标记，不执行 chmod、不全局修改执行策略。
- Magic Resume 复用官方同级仓或安全新克隆，检查 Node/pnpm，在当前终端运行 3000 端口开发服务，`Ctrl+C` 停止；端口已占用时停止，不终止现有进程。Windows 入口不接管 macOS 后台 PID。
- edgetunnel 使用工程现有 Wrangler 配置；先校验登录，部署需 `YES`，不自动创建账户或 KV。请先在工程配置实际绑定。
- Git Commit 修复检查对象连通性、残留锁、子模块状态与暂存预检；仅在无在途 Git/Sourcetree 进程、排他打开锁成功且 `YES` 后归档锁。工作树绑定、gitlink 形态冲突保留现场并提示处理。Fetch 先 fetch/prune，仍有引用冲突经确认再 pack-refs；不清空引用目录或凭据。
- SourceTree 的只拉取动作保留其固定 gitlink 策略，子模块可能为 detached HEAD；这与 Gits 下载配置脚本的分支最新策略不同。已有子仓独有提交或源码修改停止；本仓 tracked 修改可逐项展示后 YES 舍弃，未跟踪和忽略文件不删除。更新并非跨仓事务，后层失败保留已经成功更新的父层供审阅。
- 逐层 Push 只用已有本地分支，各仓显式映射远端目标（`remote.<name>.jobsPushBranch` 本仓覆盖；Gitee 默认 `gitee`），先 fetch 全部线路，再暂存/提交/整合/推送同一最终 HEAD。检查点存实际 Git 目录，失败后选择续跑或从头，续跑核对原分支、HEAD、配置指纹与已完成仓远端真值，中途失败复用当前仓已生成的提交。不同或多个 `pushurl` 在提交前停止，避免验证错线路。不创建额外本地分支、不强推；OC 独立快照仓停止。
- Flutter 使用工程 `.fvm/flutter_sdk`；已锁版本却缺 SDK 时停止，不静默换成全局工具。鸿蒙必须有适配 SDK 和 `ohos/`。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

PowerShell Parser 检查全部入口和模块；隔离测试使用临时 Git 工作树和本地 bare remote，检查 Unicode 路径、import 备份、soft 回退、双远端同 HEAD 与本地分支集合。

```powershell
pwsh -NoProfile -File .\Tests\SourceTree.Tests.ps1
```

当前作者环境为 macOS：未在 Windows 实机验收双击、菜单界面、IDE/浏览器启动和 SDK 构建；未对真实项目执行构建、部署、提交或推送。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
