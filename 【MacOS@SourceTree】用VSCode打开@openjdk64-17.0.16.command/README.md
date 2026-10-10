# `【MacOS@SourceTree】用VSCode打开@openjdk64-17.0.16.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

发现并验证健康的 [**OpenJDK / Java**](https://openjdk.org) 17，再使用 [**Visual Studio Code**](https://code.visualstudio.com) 打开工程目录。文件名保留旧 `17.0.16` 字样用于菜单路径兼容，运行时支持健康的 Java 17 补丁版本。

入口用于 [**Sourcetree**](https://www.sourcetreeapp.com/) 自定义动作，也支持终端独立运行；脚本自述写在源码里，不读取 README 作为运行说明。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- Sourcetree 动作使用本目录同名脚本，参数为 `"$REPO"`，整个路径作为一个参数传入。
- 在终端进入脚本目录后运行：

  ```shell
  './【MacOS@SourceTree】用VSCode打开@openjdk64-17.0.16.command' '/path/to/project'
  ```

- 终端先打印内置自述，按回车确认，`Ctrl+C` 取消；真实 Sourcetree 父进程或相关环境变量被识别后无交互执行。
- 非 Sourcetree 且没有可交互输入时停止；相对脚本路径、无 TTY、`TERM=dumb` 都不会单独绕过确认。

## 二、目标与依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 项目 | 规则 |
|---|---|
| 目标来源 | 单个命令行参数优先，其次 `REPO`；终端无参数时使用当前目录 |
| Sourcetree 缺参数 | 停止，并提示配置 `"$REPO"` |
| 路径支持 | 中文、空格、配对外层引号、`~/`；多参数停止，避免错误拼接 |
| 目标类型 | 现有工程目录 |
| CLI | `code` 存在且 `--version` 成功才使用；损坏 CLI 回退 app |
| 应用候选 | 系统级 / 用户级正式版、Insiders |
| 系统命令 | macOS `open`；日志使用原生 Shell 和系统文本工具 |

## 三、打开与失败策略 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、完成目标校验，发现并激活健康 JDK 17，然后尝试健康 CLI。

2、CLI 缺失或健康检查失败时，检查本机已有 `.app`，按明确路径启动。真正启动失败保留命令退出码，不显示操作成功。

3、没有可用应用时打开官方下载页面，返回 `3` 表示目标尚未打开；网页启动失败则保留实际退出码。不自动下载、安装、升级或修改 shell 环境配置。

4、参数和目标校验失败返回 `2`，其它运行错误返回非零；Sourcetree 输出窗口可据此识别失败。

## 四、Java 环境 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、优先复用已安装且健康的 [**jenv**](https://www.jenv.be/) 映射。优先检查 `17` 别名，其它别名逐个验证真实 `java` 与 `javac` 主版本；名字里包含 `17` 不作为通过条件。

2、没有健康 jenv 映射时，检查 `JAVA_HOME`、系统 `java_home -v 17`、Apple Silicon / Intel 的 OpenJDK 17 标准安装位置和用户 / 系统 JDK 目录。每个候选都要求 `java.specification.version=17`、`javac 17` 且命令成功。

3、只对本次启动设置 `JAVA_HOME`、`PATH`。有健康 jenv 映射时设置 `JENV_VERSION`，并幂等更新目标目录的 `.java-version`；目标标记是符号链接时停止，避免写到项目之外。没有健康映射时保留现有标记，不写无法解析的版本配置。

4、不要求安装 [**Homebrew**](https://brew.sh/) / jenv，不修改用户 shell 配置，不安装或升级 JDK。健康 JDK 17 缺失时停止并输出排查方向。

5、CLI 会继承本次启动环境；已运行的编辑器进程或 GUI 启动可能使用应用自身的 JDK 设置。编辑器 Java 插件的 JDK 配置需要在工程里核对，脚本不会改写 IDE 配置。

## 五、日志与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 日志位于系统临时目录，文件名为 `【MacOS@SourceTree】用VSCode打开@openjdk64-17.0.16.log`；确认后初始化日志，记录自述摘要和业务输出；取消前不清空旧日志。
- Sourcetree、非彩色终端或设置 `NO_COLOR` 时输出纯文本；路径中的反斜杠按原文保留。
- 只有健康 jenv 映射时会保存项目 `.java-version`，可能影响以后在该目录运行 Java。
- 关闭输出窗口后仍可查看日志；应用启动接受请求不等于项目构建或运行成功。

## 六、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 已执行真实 macOS `zsh -n` 和隔离假命令回归，覆盖路径校验、损坏 CLI 回退、启动失败、Sourcetree 无交互和终端确认拒绝。Java 分支额外覆盖真实主版本校验、jenv 映射和现有标记保护。
- 回归没有安装软件、启动真实编辑器或改写用户业务项目；各应用 GUI 和实际项目加载仍由使用时确认。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
