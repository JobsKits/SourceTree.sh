# `JobsFlutterDependencyExtractor Sourcetree 核心`

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

本目录实现“提取解析后的 Pub 第三方源码”，由 [SourceTree 公共调度](../../../README.md) 加载；无需安装 Windows 右键扩展，须携带整个 WindowsOS 脚本目录。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与能力 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [Action.psm1](./Action.psm1) | 读取已有 lock 与 package_config，复制直接 / 间接 / dev 第三方源码和许可证，输出独立目录与版本清单；源目录只读。 |
| [Common.psm1](./Common.psm1) | 随包路径、工具执行与日志基础函数。 |
| [ExtractFlutterDependencies.dart](./ExtractFlutterDependencies.dart) | Dart 依赖解析、复制与清单输出引擎，与 Action 同目录携带。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、输入、输出与影响 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

调用使用明确的目标工程路径，先检查工程身份和已解析依赖；依次探测项目 FVM、FLUTTER_ROOT、Flutter 对应 Dart、package_config 记录与 PATH Dart，复用健康原生 dart.exe，不下载 SDK。具体输入、默认、可选动作与产物见 [Windows 功能总览](../../../../README.md) 与各 Run.ps1 包说明。模块供调度导入，不作为双击入口，不从另一台电脑的绝对路径加载。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、运行和验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要 Windows PowerShell 5.1+ 及该动作要求的项目工具。体检只读；生成、pub get 与构建会改写对应项目产物，依赖提取只写选择的输出目录；网络与签名边界按动作声明。复用核心日志在系统临时目录的 JobsSourceTree/logs，由实际运行输出位置。本文仅静态核对，未执行构建、下载或源码生成。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
