# 【WindowsOS@SourceTree】📦双击打包Flutter.ohos

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

> 使用已有鸿蒙适配 SDK 和 ohos 工程一次同时构建 HAP 安装包与 APP 发布包。适用于 [**Windows**](https://www.microsoft.com/windows/) [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1 或更高版本。

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
- 使用已有鸿蒙适配 SDK 和 ohos 工程，依次执行 `flutter pub get`、`flutter build hap --release`、`flutter build app --release`，两种非空产物均核验才完成。
- 失败返回非零退出码；日志位于 `%TEMP%/JobsSourceTree*`，复用功能日志在 `%TEMP%/JobsSourceTree/logs`。

具体兼容差异、排除项与验证范围见 [Windows 总览](../README.md)。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、功能、选项与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 此动作固定 HAP + APP，不弹类型菜单；`OHOS_BUILD_TARGET` 不改变双产物约定。目标须为含 Flutter 依赖声明、`lib/`、`ohos/` 和现有平台配置的根目录。
- 鸿蒙 SDK 可由 `FLUTTER_OHOS_SDK` 指定；`BUILD_MODE` 默认 release，支持 debug / profile；拒绝 FLAVOR。
- 检查 DevEco、Java、SDK 与适配 Flutter 能力，在当前进程临时设置环境，构建结束或异常时恢复。
- 先核验 SDK 同时支持 HAP / APP，任一构建失败或任一类没有非空产物时停止并返回非零；两种构建结束后再次核对已确认的两类文件仍存在且非空，APP 构建删掉 HAP 也判失败。已经生成的其它文件保留。扫描 `build/ohos/`、`ohos/build/` 和各模块 `build/outputs/`，跳过链接与中间缓存，明确标出未签名与现存缓存产物。
- 标准输出和错误输出写入会话日志；构建工具失败时保留可用的退出码。不创建或读取证书秘密，不发布应用；未签名 HAP 需先配置证书及目标设备授权才可安装。
- `-Target` 未给出时使用启动时当前目录；`-Option`、`-Value` 只在回退动作中有业务含义。需要完整携带 [公共模块](../Scripts/README.md)，不依赖已安装的 Finder 扩展。
- 本文按当前源码核对；没有在文档维护中运行真实部署、构建、Git 写入或桌面动作。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
