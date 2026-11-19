# `【MacOS@SourceTree】用Android Studio打开openjdk64-17.0.16.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、运行方式](#jobs-toc-heading-2)
- [二、目标与依赖](#jobs-toc-heading-3)
- [三、打开与失败策略](#jobs-toc-heading-4)
- [四、Java 环境](#jobs-toc-heading-5)
- [五、日志与风险](#jobs-toc-heading-6)
- [六、验证边界](#jobs-toc-heading-7)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

发现并验证健康的 [**OpenJDK / Java**](https://openjdk.org) 17，再使用 [**Android Studio**](https://developer.android.com/studio?hl=zh-c) 打开工程目录。文件名保留旧 `17.0.16` 字样用于菜单路径兼容，运行时支持健康的 Java 17 补丁版本。

入口用于 [**Sourcetree**](https://www.sourcetreeapp.com/) 自定义动作，也支持终端独立运行；脚本自述写在源码里，不读取 README 作为运行说明。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- Sourcetree 动作使用本目录同名脚本，参数为 `"$REPO"`，整个路径作为一个参数传入。
- 在终端进入脚本目录后运行：

  ```shell
  './【MacOS@SourceTree】用Android Studio打开openjdk64-17.0.16.command' '/path/to/project'
  ```

- 终端先打印内置自述，按回车确认，`Ctrl+C` 取消；真实 Sourcetree 父进程或相关环境变量被识别后无交互执行。
- 非 Sourcetree 且没有可交互输入时停止；相对脚本路径、无 TTY、`TERM=dumb` 都不会单独绕过确认。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、目标与依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 项目 | 规则 |
|---|---|
| 目标来源 | 单个命令行参数优先，其次 `REPO`；终端无参数时使用当前目录 |
| Sourcetree 缺参数 | 停止，并提示配置 `"$REPO"` |
| 路径支持 | 中文、空格、配对外层引号、`~/`；多参数停止，避免错误拼接 |
| 目标类型 | 现有工程目录 |
| CLI | `studio` 是 GUI launcher；不使用 `--version` 探测，只带明确目标启动一次，并保留实际失败码 |
| 应用候选 | 系统级 / 用户级正式版、Beta、Preview |
| 系统命令 | macOS `open`；日志使用原生 Shell 和系统文本工具 |

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、打开与失败策略 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、完成目标校验，发现并激活健康 JDK 17，然后检查本机应用元数据并发现 Studio launcher。

2、可执行 Studio launcher 存在时仅带目标启动一次，支持自定义安装位置；缺 launcher 时使用已发现的本机 `.app`。实际启动失败保留命令退出码，不再次尝试另一入口，避免重复打开。

3、所需编辑器缺失时只打开一次官方页面，并在当前交互流程持续复检，安装／许可由本人完成，Ctrl+C 可取消。健康 CLI 或现有 `.app` 直接复用；网页已打开不表示目标已打开。Sourcetree 无交互动作只承接到独立终端，不在动作窗口安装或读取输入。

4、参数和目标校验失败返回 `2`，其它运行错误返回非零；Sourcetree 输出窗口可据此识别失败。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、Java 环境 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、优先复用已安装且健康的 [**jenv**](https://www.jenv.be/) 映射。优先检查 `17` 别名，其它别名逐个验证真实 `java` 与 `javac` 主版本；名字里包含 `17` 不作为通过条件。

2、没有健康 jenv 映射时，检查 `JAVA_HOME`、系统 `java_home -v 17`、Apple Silicon / Intel 的 OpenJDK 17 标准安装位置和用户 / 系统 JDK 目录。每个 JDK 候选都要求 `java.specification.version=17`、`javac 17` 且命令成功。

3、只对本次启动设置 `JAVA_HOME`、`PATH`。有健康 jenv 映射时设置 `JENV_VERSION`，并幂等更新目标目录的 `.java-version`；目标标记是符号链接时停止，避免写到项目之外。没有健康映射时保留现有标记，不写无法解析的版本配置。

4、健康 JDK 17 直接复用（包括既有用户 Homebrew 前缀）；缺失时才准备必要 Apple 工具链、Homebrew 和精确 `openjdk@17`，随后再次核验 java／javac 主版本。仅刷新当前进程，不安装 jenv、不升级其它软件、不修改 Shell 启动配置。

5、CLI 会继承本次启动环境；已运行的编辑器进程或 GUI 启动可能使用应用自身的 JDK 设置。Android Studio 的 Gradle JDK / Java 插件配置需要在工程里核对，脚本不会改写 IDE 配置。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、日志与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 确认后在系统临时目录创建独立 `JobsJdk17.*/open.log`，不清空上次记录；日志目录／文件创建失败立即停止。
- Sourcetree、非彩色终端或设置 `NO_COLOR` 时输出纯文本；路径中的反斜杠按原文保留。
- 只有健康 jenv 映射时会保存项目 `.java-version`，可能影响以后在该目录运行 Java。
- 关闭输出窗口后仍可查看日志；应用启动接受请求不等于项目构建或运行成功。

Sourcetree 必要准备转交成功时，原动作返回 `0` 仅表示新终端已接收；最终安装／打开结果见该终端。承接保留原参数、工作目录、已解析目标，以及显式 Java／开发目录／Homebrew 前缀，不修改系统或代理配置。

子进程返回取消码时直接停止，不继续枚举其它JDK、修复或打开目标。增加15项实际有界子进程取消场景；原54项在本次最终源码重新通过。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">六、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 已执行真实 macOS `zsh -n` 和隔离假命令回归，覆盖路径校验、Studio 不探测 `--version`、启动失败、Sourcetree 无交互和终端确认拒绝。Java 分支额外覆盖真实主版本校验、jenv 映射和现有标记保护。
- 回归没有安装软件、启动真实编辑器或改写用户业务项目；各应用 GUI 和实际项目加载仍由使用时确认。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

2026-11-17 补验：3 份脚本共 34 项实际 caller／双版本／TTY 假边界用例，12 项既有用户前缀复用、独立日志和失败门禁，以及 2 项原生承接 worker 数据／环境／退出码／清理、6 项真实 PTY 首屏非空取消／EOF 门禁用例通过。安装器、网络、浏览器和真实编辑器均被硬拒或替身隔离；不等同于真实软件安装／项目加载验收。

用户目录安装Homebrew前先复用健康Git（含自定义来源）；系统Git只是占位器时先查实际CLT工具，缺失才打开一次Apple原生安装窗口并持续复检。许可与密码由本人处理；显式开发目录损坏、只读、非交互或取消时停止，不改全局xcode-select，也不在准备成功前写Homebrew目标。该公共函数的12项隔离场景含10项真实PTY，函数体一致性与每份源码语法分别核对，不代表真实安装已执行。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
