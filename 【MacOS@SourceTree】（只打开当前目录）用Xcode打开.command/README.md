# `【MacOS@SourceTree】（只打开当前目录）用Xcode打开.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

为 [**Sourcetree**](https://www.sourcetreeapp.com/) 自定义动作选择明确的现有工程或工作区，用 [**Xcode**](https://developer.apple.com/xcode) 打开。默认仅执行打开；依赖安装使用独立 Pod Install 动作。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- Sourcetree 参数为 `"$REPO"`；也可以在终端传入唯一目录、`.xcodeproj` 或 `.xcworkspace`：

  ```shell
  './【MacOS@SourceTree】（只打开当前目录）用Xcode打开.command' '/path/to/project'
  ```

- 终端先展示源码内置自述，按回车继续，`Ctrl+C` 取消；Sourcetree 实际发起时无交互，输出纯文本。
- 参数优先于 `REPO`。终端无参数默认当前目录，Sourcetree 缺目标时停止。多个参数会停止，请把含空格路径整体加引号。
- 不以相对脚本路径或无 TTY 判断 Sourcetree；非 Sourcetree 且没有可交互输入时停止。

## 二、扫描与选择 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

仅扫描目标目录第一层；不会寻找子目录里的项目。

1、明确传入 `.xcodeproj` / `.xcworkspace` 时直接使用；扫描工程时排除 `Pods.xcodeproj`。NUL 分隔保留中文、空格及路径中的换行。

2、默认优先目标目录中与目录同名的 workspace，其次唯一顶层 workspace；同名 workspace 可汇集多个工程，无须单独猜测工程。

3、没有顶层 workspace 时，工程必须唯一。唯一工程旁有同名 workspace 时使用它；否则只接受唯一邻接 workspace。多个工程或多个可选 workspace 时列出候选并返回 `2`，请传入明确目标。

4、存在 `Podfile` 但没有 workspace 时直接打开 `.xcodeproj` 并提示依赖入口；不会为了打开工程运行 `pod install`。

## 三、可选配置 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 变量 | 默认 | 行为 |
|---|---|---|
| `FORCE_XCODEPROJ` | `0` | `1` 时扫描阶段只选择唯一工程；明确传入目标仍按该目标打开 |
| `RESOLVE_SWIFTPM_BEFORE_OPEN` | `0` | `1` 才在打开前显式解析 [**SwiftPM**](https://www.swift.org/documentation/package-manager/) 依赖 |
| `XCODE_SCHEME` | 未设置 | 显式解析时可传入 Scheme；未设置时交给 xcodebuild |

- 默认只要求 macOS `open`，无需 CocoaPods、Python 或命令行构建环境。
- 启用 SwiftPM 解析时，先验证 `xcodebuild -version`，解析命令失败则停止；解析可能联网并修改项目依赖解析结果。
- 不移除全局隔离属性，不扫描或改写其它项目的 SwiftPM / DerivedData 缓存。

## 四、日志与退出码 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 系统临时目录中的 `【MacOS@SourceTree】（只打开当前目录）用Xcode打开.log` 确认后保存自述摘要、候选、选中目标和外部命令输出；取消前不清空旧日志。
- 无目标或候选歧义返回 `2`；打开或显式解析失败保留实际命令退出码，不显示操作成功。
- Sourcetree / 非彩色环境输出纯文本；参数中的引号、反斜杠与空格按原文传递，不拼接为 Shell 命令。

## 五、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 已执行真实 macOS `zsh -n` 与临时目录隔离回归，覆盖唯一目标、同名 workspace、工作区独立存在、多工程拒绝、路径特殊字符、依赖目录剪枝及打开失败。
- 未启动真实 Xcode，未运行真实 `pod install` 或 `xcodebuild`；GUI 加载和显式解析的真实结果需在实际工程中确认。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
