# SourceTree Flutter 运行设备与 Android 初始化

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与边界](#runtime)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录随包复用 [**Flutter**](https://flutter.dev/) 运行器的设备选择和 Android 初始化，无需安装系统右键扩展。用户从[运行动作](../../../../【WindowsOS@SourceTree】🐦打开：运行Flutter项目/README.md)进入，内部调用由[公共调度](../../../README.md)负责。

## 一、<span id="runtime">文件与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

`Action.psm1` 负责 FVM 边界、工程平台过滤、fzf 设备选择、已有 AVD 启动和缺失时初始化；`AndroidRuntime.ps1` 提供工具链自检、官方来源下载校验、AVD 创建与按名称核对启动状态；`Common.psm1` 提供参数、进程和日志工具。父目录 `Extension.json` 仅用于解析当前用户日志位置，不执行菜单注册。

SDK / Java 工具准备、镜像下载及 AVD 创建分别显示影响与确认；只用所选宿主 ABI 的稳定镜像，不覆盖既有 AVD。型号 / 镜像层可按 `←` 返回，Esc、非空确认与 EOF 不创建；已完成工具准备保留。设备启动后按 AVD 对应 serial 等待 Flutter 识别，超时保留设备与日志。

SourceTree 仅调用设备选择，之后在当前独立终端执行 `flutter run -d <id>`，保持原生热重载与 Ctrl+C 结束方式；不调用本模块保留的后台会话函数，也不需要 RunnerHost.exe。整套资源从当前目录相对解析，不绑定原电脑路径。Android Emulator 初始化要求 Windows x64；其它架构可使用受支持真机 / Web / Windows 目标。日志位置由运行输出显示。

**设备发现前通用缓存：** 设备枚举前先执行 `flutter precache --universal`，准备 `sky_engine`、patched SDK 等通用资源，再进入短时设备查询。只准备通用制品，不强制下载全部平台；保留项目绑定 SDK，复用健康缓存。缺失制品沿随包网络选路实时显示真实下载进度，失败持续自动重试，Ctrl+C／停止结束；准备失败不会被误报为“无设备”，也不启动应用。

**Flutter SDK网络预检：** 下载／首次Dart自举／precache前，随包网络模块以真实小Range验证来源、TLS、字节和吞吐并择优；显式storage、Pub和代理（含空值）保留，AUTO仅核验官方／CFUG同对象及当前已配置代理，不猜端口、不改系统代理或Git。当前任务短期复用；真实获取失败会降权坏路线、轮换其它已验证候选并持续重试。FVM按实际api context来源处理，能力允许时Git与Dart制品分阶段；用户fork不改源。原生BITS按真实WinINET通道衡量，PAC未能有界解析时保留既有通道并明确未测速。详细边界见[随包选路模块](./SdkDownloadRoute.ps1/README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
