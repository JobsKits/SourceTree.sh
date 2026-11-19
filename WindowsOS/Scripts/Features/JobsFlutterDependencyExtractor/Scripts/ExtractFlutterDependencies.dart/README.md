# [**Dart**](https://dart.dev) 本地依赖源码提取器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、调用与范围](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ExtractFlutterDependencies.dart](./ExtractFlutterDependencies.dart) 由上级 PowerShell 功能模块调用，读取工程已经解析的本地依赖并按原协议提取源码；不运行 `pub get`，不联网。运行时使用调用方选定 Flutter SDK 中的 Dart，不安装另一份全局 SDK。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、调用与范围</span><!-- jobs-toc:heading-end -->

请通过功能入口选择目标工程；本文件是参数驱动的实施层，不另加终端选择或确认，避免破坏调度协议。缺少项目身份、锁文件或依赖源时保留原失败状态；产物与异常日志继续由调用方管理。完整迁移本目录时，必须同时保留上级模块及其配套资源。

源码文件按完整名称包装，调用方从自身目录定位内层文件，不依赖启动工作目录。验证仅覆盖既有隔离工程和语法，不执行真实依赖下载。

<a id="🔚" href="#前言">返回前言</a>
