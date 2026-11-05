# `JobsFlutterDoctor Sourcetree 核心`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与能力](#jobs-toc-heading-2)
- [二、输入、输出与影响](#jobs-toc-heading-3)
- [三、运行和验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录实现“工程 SDK 体检”，由 [SourceTree 公共调度](../../../README.md) 加载；无需安装 Windows 右键扩展，须携带整个 WindowsOS 脚本目录。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与能力 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 执行项目同源 Flutter / Dart 版本与 doctor -v，警告或错误保持失败；不安装依赖或 clean。 |
| [Common.psm1](./Common.psm1) | 随包路径、工具执行与日志基础函数。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、输入、输出与影响 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

调用使用明确的目标工程路径，先检查工程身份与已有项目 SDK；FVM 锁定但 SDK 不全时停止，不换全局工具。具体输入、默认、可选动作与产物见 [Windows 功能总览](../../../../README.md) 与各 Run.ps1 包说明。模块供调度导入，不作为双击入口，不从另一台电脑的绝对路径加载。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、运行和验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要 Windows PowerShell 5.1+ 及该动作要求的项目工具。体检只读；生成、pub get 与构建会改写对应项目产物，依赖提取只写选择的输出目录；网络与签名边界按动作声明。复用核心日志在系统临时目录的 JobsSourceTree/logs，由实际运行输出位置。本文仅静态核对，未执行构建、下载或源码生成。

**Flutter SDK网络预检：** 下载／首次Dart自举／precache前，随包网络模块以真实小Range验证来源、TLS、字节和吞吐并择优；显式storage、Pub和代理（含空值）保留，AUTO仅核验官方／CFUG同对象及当前已配置代理，不猜端口、不改系统代理或Git。当前任务短期复用；真实获取失败会降权坏路线、轮换其它已验证候选并持续重试。FVM按实际api context来源处理，能力允许时Git与Dart制品分阶段；用户fork不改源。原生BITS按真实WinINET通道衡量，PAC未能有界解析时保留既有通道并明确未测速。详细边界见[随包选路模块](./SdkDownloadRoute.ps1/README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
