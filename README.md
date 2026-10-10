# 配置 [**Sourcetree**](https://www.sourcetreeapp.com/) 自定义脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

脚本库包含 32 个系统 `/bin/zsh` 入口，每个脚本包有同名 `.command` 和独立 `README.md`。源码、静态说明和运行时内置自述分别维护；运行时不读取 README。

运行态位于当前用户家目录的 `SourceTree.command`，备份态为 JobsGenesis 下的同名 Git 工作树。维护时保留两侧已有改动，修改完成后按相同相对路径同步脚本、README、资源及菜单配置；Git 元数据和系统生成文件不互相覆盖。

## 一、菜单安装 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从本 README 所在目录执行：

```shell
/bin/zsh './【MacOS】安装SourceTree自定义菜单.command/【MacOS】安装SourceTree自定义菜单.command'
```

安装器先确认库发送目标，再选择菜单安装或配置回收。已有目标库回车保留，输入 `YES` 才备份替换。菜单按脚本路径合并并保留自定义显示标题、快捷键和显示设置，覆盖前生成可恢复备份；正在运行的 Sourcetree 正常退出、保存配置后再写入并重新打开，不强制结束。

菜单动作目标默认使用家目录运行副本；指定其它发送目录时使用该目标库，仓库动作参数为 `$REPO`，不是把多个路径拼接成一个参数。所有动作目标须存在、可执行且唯一。安装器本身保留终端交互，不挂成仓库菜单；其余 31 个任务入口可作为仓库动作。

详细步骤、依赖与风险见 [安装器 README](./【MacOS】安装SourceTree自定义菜单.command/README.md)。

## 二、运行策略 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 终端运行：先展示固定内置自述，回车继续、`Ctrl+C` 取消；确认前不写日志、不执行项目业务。没有可交互输入且未明确识别 Sourcetree 时退出。
- Sourcetree 动作：根据明确环境或父进程链识别，无交互连续执行；相对脚本路径、非 TTY 或 `TERM=dumb` 单独不能作为身份依据。
- Sourcetree、非 TTY、`NO_COLOR` 使用纯文本输出；完整终端自述标题红色加粗、正文蓝色常规。业务错误不会被最后的成功输出掩盖。
- 递归动作跳过 Git、依赖、缓存与生成目录；具体范围及所有权过滤由各包 README 说明，明确目标错误时不回退到其它项目。
- 普通更新或升级回车跳过，输入任意字符后回车执行；危险替换或 hard 回退要求 `YES`。逐层 Push 与终端 Pod Install 会转交独立终端，以对应入口确认和结果为准。
- 开发工具、Java 17 和项目 SDK 先检查实际可用性。打开类动作复用现有工具，不为打开项目自动安装依赖或清理全局缓存；工具缺失时提供明确排查入口。

## 三、脚本索引 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 脚本包 | 说明 |
| --- | --- |
| `⏬双击下载SourceTree效率脚本` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E2%8F%AC%E5%8F%8C%E5%87%BB%E4%B8%8B%E8%BD%BDSourceTree%E6%95%88%E7%8E%87%E8%84%9A%E6%9C%AC.command/README.md) |
| `♻️修复Flutter项目中文路径` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E2%99%BB%EF%B8%8F%E4%BF%AE%E5%A4%8DFlutter%E9%A1%B9%E7%9B%AE%E4%B8%AD%E6%96%87%E8%B7%AF%E5%BE%84.command/README.md) |
| `♻️双击Git（识别子Git） 提交回退` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E2%99%BB%EF%B8%8F%E5%8F%8C%E5%87%BBGit%EF%BC%88%E8%AF%86%E5%88%AB%E5%AD%90Git%EF%BC%89%20%E6%8F%90%E4%BA%A4%E5%9B%9E%E9%80%80.command/README.md) |
| `⚙️收集当前Flutter工程的依赖` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E2%9A%99%EF%B8%8F%E6%94%B6%E9%9B%86%E5%BD%93%E5%89%8DFlutter%E5%B7%A5%E7%A8%8B%E7%9A%84%E4%BE%9D%E8%B5%96.command/README.md) |
| `⚙️运行授权` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E2%9A%99%EF%B8%8F%E8%BF%90%E8%A1%8C%E6%8E%88%E6%9D%83.command/README.md) |
| `同步edgetunnel代码后手动升级` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E5%90%8C%E6%AD%A5edgetunnel%E4%BB%A3%E7%A0%81%E5%90%8E%E6%89%8B%E5%8A%A8%E5%8D%87%E7%BA%A7.command/README.md) |
| `用Android Studio打开` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E7%94%A8Android%20Studio%E6%89%93%E5%BC%80.command/README.md) |
| `用Android Studio打开openjdk64-17.0.16` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E7%94%A8Android%20Studio%E6%89%93%E5%BC%80openjdk64-17.0.16.command/README.md) |
| `用Trae打开@openjdk64-17.0.16` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E7%94%A8Trae%E6%89%93%E5%BC%80%40openjdk64-17.0.16.command/README.md) |
| `用Trea打开` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E7%94%A8Trea%E6%89%93%E5%BC%80.command/README.md) |
| `用VSCode打开` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E7%94%A8VSCode%E6%89%93%E5%BC%80.command/README.md) |
| `用VSCode打开@openjdk64-17.0.16` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E7%94%A8VSCode%E6%89%93%E5%BC%80%40openjdk64-17.0.16.command/README.md) |
| `用终端打开` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E7%94%A8%E7%BB%88%E7%AB%AF%E6%89%93%E5%BC%80.command/README.md) |
| `获取目标绝对地址` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%E8%8E%B7%E5%8F%96%E7%9B%AE%E6%A0%87%E7%BB%9D%E5%AF%B9%E5%9C%B0%E5%9D%80.command/README.md) |
| `（只打开当前目录）用Xcode打开` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%EF%BC%88%E5%8F%AA%E6%89%93%E5%BC%80%E5%BD%93%E5%89%8D%E7%9B%AE%E5%BD%95%EF%BC%89%E7%94%A8Xcode%E6%89%93%E5%BC%80.command/README.md) |
| `（递归目录寻找工程@不适用于多工程项目）用Xcode打开` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%EF%BC%88%E9%80%92%E5%BD%92%E7%9B%AE%E5%BD%95%E5%AF%BB%E6%89%BE%E5%B7%A5%E7%A8%8B%40%E4%B8%8D%E9%80%82%E7%94%A8%E4%BA%8E%E5%A4%9A%E5%B7%A5%E7%A8%8B%E9%A1%B9%E7%9B%AE%EF%BC%89%E7%94%A8Xcode%E6%89%93%E5%BC%80.command/README.md) |
| `🌐获取远程仓库地址` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%8C%90%E8%8E%B7%E5%8F%96%E8%BF%9C%E7%A8%8B%E4%BB%93%E5%BA%93%E5%9C%B0%E5%9D%80.command/README.md) |
| `🐦Flutter自动化生产代码` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%90%A6Flutter%E8%87%AA%E5%8A%A8%E5%8C%96%E7%94%9F%E4%BA%A7%E4%BB%A3%E7%A0%81.command/README.md) |
| `🐦Flutter重新拉取第三方依赖` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%90%A6Flutter%E9%87%8D%E6%96%B0%E6%8B%89%E5%8F%96%E7%AC%AC%E4%B8%89%E6%96%B9%E4%BE%9D%E8%B5%96.command/README.md) |
| `🐦Flutter项目体检` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%90%A6Flutter%E9%A1%B9%E7%9B%AE%E4%BD%93%E6%A3%80.command/README.md) |
| `🐦打开:运行Flutter项目` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%90%A6%E6%89%93%E5%BC%80%3A%E8%BF%90%E8%A1%8CFlutter%E9%A1%B9%E7%9B%AE.command/README.md) |
| `📘用Typora打开蓝皮书` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%93%98%E7%94%A8Typora%E6%89%93%E5%BC%80%E8%93%9D%E7%9A%AE%E4%B9%A6.command/README.md) |
| `📥修复Git无法Commit` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%93%A5%E4%BF%AE%E5%A4%8DGit%E6%97%A0%E6%B3%95Commit.command/README.md) |
| `📥修复Git无法Fetch` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%93%A5%E4%BF%AE%E5%A4%8DGit%E6%97%A0%E6%B3%95Fetch.command/README.md) |
| `📦双击打包Flutter.android` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%93%A6%E5%8F%8C%E5%87%BB%E6%89%93%E5%8C%85Flutter.android.command/README.md) |
| `📦双击打包Flutter.iOS` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%93%A6%E5%8F%8C%E5%87%BB%E6%89%93%E5%8C%85Flutter.iOS.command/README.md) |
| `📦双击自动生成ipa文件` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%93%A6%E5%8F%8C%E5%87%BB%E8%87%AA%E5%8A%A8%E7%94%9F%E6%88%90ipa%E6%96%87%E4%BB%B6.command/README.md) |
| `🚀逐层空白提交并Push` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%9A%80%E9%80%90%E5%B1%82%E7%A9%BA%E7%99%BD%E6%8F%90%E4%BA%A4%E5%B9%B6Push.command/README.md) |
| `🪄配置并运行Magic Resume` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%AA%84%E9%85%8D%E7%BD%AE%E5%B9%B6%E8%BF%90%E8%A1%8CMagic%20Resume.command/README.md) |
| `🫘在Sourcetree中运行Pod Install` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%AB%98%E5%9C%A8Sourcetree%E4%B8%AD%E8%BF%90%E8%A1%8CPod%20Install.command/README.md) |
| `🫘打开终端运行Pod Install` | [README](./%E3%80%90MacOS%40SourceTree%E3%80%91%F0%9F%AB%98%E6%89%93%E5%BC%80%E7%BB%88%E7%AB%AF%E8%BF%90%E8%A1%8CPod%20Install.command/README.md) |
| `安装SourceTree自定义菜单` | [README](./%E3%80%90MacOS%E3%80%91%E5%AE%89%E8%A3%85SourceTree%E8%87%AA%E5%AE%9A%E4%B9%89%E8%8F%9C%E5%8D%95.command/README.md) |

## 四、维护和验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

回归覆盖入口确认、Sourcetree 纯文本、特殊字符路径、工具链健康、参数与默认值、命令失败传播、目录安全、产物选择和文档对账。Git 采用临时仓库复现，构建、工具安装和外部应用启动采用假命令；不把真实项目构建、提交或推送作为回归测试。

两态均执行所有入口的 `zsh -n`；按内容哈希及执行权限核对脚本、README、资源和 `actions.plist`，并检查菜单解档、目标唯一、`$REPO` 参数和实际可执行路径。运行态的 Git 元数据、备份态的子模块绑定以及 `.DS_Store` 保持各自独立。

验证完成的代码不代表全部外部环境验收：开发者签名、真实 Flutter/Xcode 构建、包管理器安装、Cloudflare 部署、具体 IDE/模拟器启动仍需在对应项目环境使用时确认结果。各 README 分别说明真实能力与未执行边界。

## 五、日志和常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

各包 README 列出实际日志名称，默认位于系统临时目录。终端启动器的成功仅表示已提交启动；最终业务退出码和详细日志在子入口或新终端中。

- 菜单提示路径不可访问：重新运行安装器，检查动作是否指向当前运行副本且有执行位。
- Terminal/Sourcetree 缺工具：先检查各脚本声明的 PATH、SDK、版本管理器及工具健康；不依赖图形应用继承外部终端全部设置。
- 多项目歧义：显式传入目标工程或工作区，不依赖扫描顺序选第一个。
- 执行失败：保留现场，按非零退出码和日志中的目标排查；下载或替换失败使用覆盖前备份恢复。

手工配置的界面位置可参考以下图，最终字段以安装器生成配置为准：

<img src="./assets/image-20250726230655312.png" alt="Sourcetree 自定义动作配置" style="zoom:50%;" />

<img src="./assets/image-20250814100342111.png" alt="Sourcetree 菜单配置示例" style="zoom:50%;" />

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
