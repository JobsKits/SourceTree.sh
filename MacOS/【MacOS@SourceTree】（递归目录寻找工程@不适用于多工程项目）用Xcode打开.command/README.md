# `【MacOS@SourceTree】（递归目录寻找工程@不适用于多工程项目）用Xcode打开.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、运行方式](#jobs-toc-heading-2)
- [二、扫描与选择](#jobs-toc-heading-3)
- [三、可选配置](#jobs-toc-heading-4)
- [四、日志与退出码](#jobs-toc-heading-5)
- [五、验证边界](#jobs-toc-heading-6)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

为 [**Sourcetree**](https://www.sourcetreeapp.com/) 自定义动作选择明确的现有工程或工作区，用 [**Xcode**](https://developer.apple.com/xcode) 打开。默认仅执行工程打开；项目 Pods 安装仍使用独立 Pod Install 动作。实际打开需要健康完整 Xcode，缺失时只准备这一必要工具。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- Sourcetree 参数为 `"$REPO"`；也可以在终端传入唯一目录、`.xcodeproj` 或 `.xcworkspace`：

  ```shell
  './【MacOS@SourceTree】（递归目录寻找工程@不适用于多工程项目）用Xcode打开.command' '/path/to/project'
  ```

- 终端先展示源码内置自述，只接受回车继续；非空输入取消，EOF 失败退出，`Ctrl+C` 取消。Sourcetree 健康环境保持无交互并输出纯文本；只有必要 Xcode 缺失时交给真实 Terminal，保留原工作目录、目标与完整参数，原动作停止且不再打开工程。
- 参数优先于 `REPO`。终端无参数默认当前目录，Sourcetree 缺目标时停止。多个参数会停止，请把含空格路径整体加引号。
- 不以相对脚本路径或无 TTY 判断 Sourcetree；非 Sourcetree 且没有可交互输入时停止。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、扫描与选择 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

递归扫描目标目录；剪枝 `.git`、`Pods`、`.build`、`.dart_tool`、`build`、`DerivedData`、`node_modules`、`vendor`、`third_party`、`ManualBy*Pods@Pods`、`PodsManual`，不进入工程包和 workspace 包。

1、明确传入 `.xcodeproj` / `.xcworkspace` 时直接使用；扫描工程时排除 `Pods.xcodeproj`。NUL 分隔保留中文、空格及路径中的换行。

2、默认优先目标目录中与目录同名的 workspace，其次唯一顶层 workspace；同名 workspace 可汇集多个工程，无须单独猜测工程。

3、没有顶层 workspace 时，工程必须唯一。唯一工程旁有同名 workspace 时使用它；否则只接受唯一邻接 workspace。多个工程或多个可选 workspace 时列出候选并返回 `2`，请传入明确目标。

4、存在 `Podfile` 但没有 workspace 时直接打开 `.xcodeproj` 并提示依赖入口；不会为了打开工程运行 `pod install`。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、可选配置 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 变量 | 默认 | 行为 |
|---|---|---|
| `FORCE_XCODEPROJ` | `0` | `1` 时扫描阶段只选择唯一工程；明确传入目标仍按该目标打开 |
| `RESOLVE_SWIFTPM_BEFORE_OPEN` | `0` | `1` 才在打开前显式解析 [**SwiftPM**](https://www.swift.org/documentation/package-manager/) 依赖 |
| `XCODE_SCHEME` | 未设置 | 显式解析时可传入 Scheme；未设置时交给 xcodebuild |

- 正常打开也验证完整 Xcode 自身的 `xcodebuild -version`，Command Line Tools 不能替代完整 App。健康安装直接复用；显式 `DEVELOPER_DIR` 无效时停止，保留用户选择。
- 缺失才打开一次 Apple 官方 App Store 页面；已有 App 但许可或首次组件未就绪时，只打开一次该 App。由本人处理账号、许可和系统权限，当前流程持续复检，`Ctrl+C` 取消，不自动接受许可。
- 仅本次进程设置已验证 App 的 `DEVELOPER_DIR`，不修改全局 `xcode-select`。启用 SwiftPM 解析时使用这份 App 的 CLI；解析失败停止，可能联网并修改项目依赖解析结果。
- 不移除全局隔离属性，不扫描或改写其它项目的 SwiftPM / DerivedData 缓存。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、日志与退出码 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 系统临时目录中的 `【MacOS@SourceTree】（递归目录寻找工程@不适用于多工程项目）用Xcode打开.log` 确认后保存自述摘要、候选、选中目标和外部命令输出；取消前不清空旧日志。
- 无目标或候选歧义返回 `2`；打开或显式解析失败保留实际命令退出码，不显示操作成功。
- Sourcetree / 非彩色环境输出纯文本；参数中的引号、反斜杠与空格按原文传递，不拼接为 Shell 命令。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 已执行真实 macOS `zsh -n` 与临时目录隔离回归，覆盖唯一目标、同名 workspace、工作区独立存在、多工程拒绝、路径特殊字符、依赖目录剪枝及打开失败。
- 新增三个入口合计 138 个函数体/闭包断言、21 个隔离用例及 13 个真实 PTY 用例，覆盖健康复用、缺失交接、不再执行原业务、精确 Scheme 和 SwiftPM 顺序、完整 App 与 CLT 区分、单次官方界面等待及取消/打开失败。原生界面与安装均由私有替身封闭。
- 未启动真实 Xcode，未运行真实 `pod install` 或 `xcodebuild`；App GUI、成品和已安装副本未变，真实打开及显式解析结果仍需在实际工程中确认。

健康探针的子进程取消码 129／130／143 已单独验证：立即原码返回，不降级为缺工具，不获取依赖、不选择其它版本、不交接或打开原生界面。三入口共 18 个实际私有子命令取消／健康复用场景通过。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
