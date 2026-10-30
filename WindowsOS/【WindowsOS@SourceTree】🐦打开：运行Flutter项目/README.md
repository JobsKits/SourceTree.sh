# 【WindowsOS@SourceTree】🐦打开：运行Flutter项目

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

> 选择 Android、Web 或 Windows 设备运行项目。适用于 [**Windows**](https://www.microsoft.com/windows/) [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1 或更高版本。

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
- 选择 Android、Web 或 Windows 设备运行项目。
- 失败返回非零退出码；日志位于 `%TEMP%/JobsSourceTree*`，Android 模拟器日志在 `%LOCALAPPDATA%/Jobs/WindowsExtension/extensions/flutter-run/logs`，实际完整位置由运行输出显示。

具体兼容差异、排除项与验证范围见 [Windows 总览](../README.md)。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、功能、选项与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 按目标 FVM 绑定或可用本机 SDK 执行 `flutter devices --machine`。
- 只列工程已有平台对应的 Android / Web / Windows 设备，排除 iOS 和 darwin。fzf 上下键选择、输入筛选，Enter 确认、Esc 取消；子层 `←` 返回。缺少 fzf 时停止并给出安装提示。
- 当前窗口执行 `flutter run -d <id>`，保留 Flutter 原生命令与热重载交互，Ctrl+C 结束。
- 没有设备时仍可重新加载或选择“Android 模拟器（启动已有 / 缺失时初始化）”。已有 AVD 可选并启动；缺失时确认后补齐官方工具、选择设备型号与稳定系统镜像，最终确认后下载 / 创建。SDK 许可证由本人确认，现有 AVD 不覆盖，取消不创建；工具准备结果保留。按所选 AVD 的 serial 等待 Flutter 识别，再继续当前窗口运行。不会替换项目 Flutter SDK、修改全局环境 / 代理或自动启用系统虚拟化。
- `-Target` 未给出时使用启动时当前目录；`-Option`、`-Value` 只在回退动作中有业务含义。需要完整携带 [公共模块](../Scripts/README.md)，不依赖已安装的 Finder 扩展。
- 本文按当前源码核对；没有在文档维护中运行真实部署、构建、Git 写入或桌面动作。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
