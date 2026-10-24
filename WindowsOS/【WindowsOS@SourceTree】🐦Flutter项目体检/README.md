# 【WindowsOS@SourceTree】🐦Flutter项目体检

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

> 检查工程同源 Flutter/Dart SDK 并执行 doctor。适用于 [**Windows**](https://www.microsoft.com/windows/) [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1 或更高版本。

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
- 检查工程同源 Flutter/Dart SDK 并执行 doctor。
- 失败返回非零退出码；日志位于 `%TEMP%/JobsSourceTree*`，复用功能日志在 `%TEMP%/JobsSourceTree/logs`。

具体兼容差异、排除项与验证范围见 [Windows 总览](../README.md)。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、功能、选项与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 精确校验目标根目录的 pubspec.yaml 声明 Flutter SDK 依赖；拒绝链接路径，不递归猜测项目。
- 使用目标项目绑定 SDK，核对同源 Flutter / Dart，依次执行版本检查及 `flutter doctor -v`，doctor 上限 600 秒。
- doctor 即使退出码为 0，只要输出含警告 / 失败检查也返回失败；不自动安装、clean 或 pub get，Flutter 自身可检查网络及缓存。
- `-Target` 未给出时使用启动时当前目录；`-Option`、`-Value` 只在回退动作中有业务含义。需要完整携带 [公共模块](../Scripts/README.md)，不依赖已安装的 Finder 扩展。
- 本文按当前源码核对；没有在文档维护中运行真实部署、构建、Git 写入或桌面动作。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
