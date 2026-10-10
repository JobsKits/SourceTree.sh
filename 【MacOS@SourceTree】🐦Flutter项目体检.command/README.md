# `【MacOS@SourceTree】🐦Flutter项目体检.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

这是 [**Sourcetree**](https://www.sourcetreeapp.com/) 的 [**Flutter**](https://flutter.dev/) 工程动作。默认检查 Flutter 工具链健康状态，也可明确选择仅拉取依赖或清理后拉取依赖。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在 Sourcetree 已安装的动作中传入 `$REPO`。系统终端独立运行先打印脚本内置自述，按回车继续，按 `Ctrl+C` 取消；运行时不读取 README。Sourcetree 身份通过环境变量或父进程确认，非 TTY 本身不会绕过确认。

```shell
zsh "./【MacOS@SourceTree】🐦Flutter项目体检.command" "<工程目录>"
```

`[工程路径] [doctor|clean-get|pub-get]`，默认动作是 `doctor`。未知动作在操作工程前拒绝；路径中的 `|` 保留原样。

自述与确认阶段只输出到屏幕；确认后才初始化日志。非 Sourcetree 且没有交互输入时直接退出，不执行工程业务。

## 二、执行前检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需要工程对应 Flutter SDK。不会安装或升级 [**Homebrew**](https://brew.sh/)，不会修改 shell 配置。

```shell
zsh "./【MacOS@SourceTree】🐦Flutter项目体检.command" "<工程目录>" doctor
zsh "./【MacOS@SourceTree】🐦Flutter项目体检.command" "<工程目录>" clean-get
```

## 三、实际执行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

选择 SDK 前先进入工程，避免读取启动目录的 FVM 配置；不使用脆弱的字符串分隔符传递目录和动作。

```shell
flutter doctor
# clean-get：flutter clean && flutter pub get
# pub-get：flutter pub get
```

## 四、风险与失败处理 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

`doctor` 主要检查环境，Flutter 自身可能准备 SDK 缓存；另外两个显式动作会写入工程依赖或清理构建目录。

Sourcetree 不发起输入等待；无法安全确定目标或缺少必要条件时直接报错。外部命令失败返回非零状态，后续业务停止。脚本及外部输出在受限输出窗口使用纯文本。

## 五、日志与产物 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

执行日志位于系统临时目录，文件名为 `【MacOS@SourceTree】🐦Flutter项目体检.log`。终端和 Sourcetree 都会打印实际日志位置。

## 六、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

已用隔离假 SDK 验证三种动作、包含空格 / 中文 / 竖线的路径、未知动作提前拒绝与命令失败传播。

已通过 `zsh -n` 静态语法检查。 入口已隔离验证非交互拒绝、确认前不创建日志、`NO_COLOR` 空值降级与业务失败退出码传播。隔离夹具验证没有运行真实 Flutter / Xcode 构建、安装、依赖清理或模拟器操作；真实工程的签名、网络和工具版本仍需按运行日志确认。

## 七、流程图 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```mermaid
flowchart TD
    A[展示内置自述] --> B{是否 Sourcetree 动作}
    B -->|是| C[无交互解析参数]
    B -->|否| D[终端回车确认]
    D --> C
    C --> E[定位目标与检查条件]
    E --> F{目标是否唯一且有效}
    F -->|否| G[报错并退出]
    F -->|是| H[顺序执行业务并记录日志]
    H --> I{命令是否成功}
    I -->|否| G
    I -->|是| J[输出结果与日志位置]
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
