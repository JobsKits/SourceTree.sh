# 配置 [**Sourcetree**](https://www.sourcetreeapp.com/) 自定义脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、菜单安装](#jobs-toc-heading-2)
- [二、运行策略](#jobs-toc-heading-3)
- [三、脚本索引](#jobs-toc-heading-4)
- [四、维护和验证](#jobs-toc-heading-5)
- [五、日志和常见问题](#jobs-toc-heading-6)
- [六、目录结构](#repository-layout)
- [七、脚本执行流程](#script-workflows)
  - [【MacOS@SourceTree】⏬只拉取远程代码.command](#jobs-toc-heading-9)
  - [【MacOS@SourceTree】⏬双击下载SourceTree效率脚本.command](#jobs-toc-heading-10)
  - [【MacOS@SourceTree】♻️修复Flutter项目中文路径.command](#jobs-toc-heading-11)
  - [【MacOS@SourceTree】♻️双击Git（识别子Git） 提交回退.command](#jobs-toc-heading-12)
  - [【MacOS@SourceTree】⚙️收集当前Flutter工程的依赖.command](#jobs-toc-heading-13)
  - [【MacOS@SourceTree】⚙️运行授权.command](#jobs-toc-heading-14)
  - [【MacOS@SourceTree】同步edgetunnel代码后手动升级.command](#jobs-toc-heading-15)
  - [【MacOS@SourceTree】用Android Studio打开.command](#jobs-toc-heading-16)
  - [【MacOS@SourceTree】用Android Studio打开openjdk64-17.0.16.command](#jobs-toc-heading-17)
  - [【MacOS@SourceTree】用Trae打开@openjdk64-17.0.16.command](#jobs-toc-heading-18)
  - [【MacOS@SourceTree】用Trea打开.command](#jobs-toc-heading-19)
  - [【MacOS@SourceTree】用VSCode打开.command](#jobs-toc-heading-20)
  - [【MacOS@SourceTree】用VSCode打开@openjdk64-17.0.16.command](#jobs-toc-heading-21)
  - [【MacOS@SourceTree】用终端打开.command](#jobs-toc-heading-22)
  - [【MacOS@SourceTree】获取目标绝对地址.command](#jobs-toc-heading-23)
  - [【MacOS@SourceTree】（只打开当前目录）用Xcode打开.command](#jobs-toc-heading-24)
  - [【MacOS@SourceTree】（递归目录寻找工程@不适用于多工程项目）用Xcode打开.command](#jobs-toc-heading-25)
  - [【MacOS@SourceTree】🌐获取远程仓库地址.command](#jobs-toc-heading-26)
  - [【MacOS@SourceTree】🐦Flutter自动化生产代码.command](#jobs-toc-heading-27)
  - [【MacOS@SourceTree】🐦Flutter重新拉取第三方依赖.command](#jobs-toc-heading-28)
  - [【MacOS@SourceTree】🐦Flutter项目体检.command](#jobs-toc-heading-29)
  - [【MacOS@SourceTree】🐦打开:运行Flutter项目.command](#jobs-toc-heading-30)
  - [【MacOS@SourceTree】📘用Typora打开蓝皮书.command](#jobs-toc-heading-31)
  - [【MacOS@SourceTree】📥修复Git无法Commit.command](#jobs-toc-heading-32)
  - [【MacOS@SourceTree】📥修复Git无法Fetch.command](#jobs-toc-heading-33)
  - [【MacOS@SourceTree】📦双击打包Flutter.android.command](#jobs-toc-heading-34)
  - [【MacOS@SourceTree】📦双击打包Flutter.iOS.command](#jobs-toc-heading-35)
  - [【MacOS@SourceTree】📦双击自动生成ipa文件.command](#jobs-toc-heading-36)
  - [【MacOS@SourceTree】🚀逐层空白提交并Push.command](#jobs-toc-heading-37)
  - [【MacOS@SourceTree】🪄配置并运行Magic Resume.command](#jobs-toc-heading-38)
  - [【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.command](#jobs-toc-heading-39)
  - [【MacOS@SourceTree】🫘打开终端运行Pod Install.command](#jobs-toc-heading-40)
  - [【MacOS】安装SourceTree自定义菜单.command](#jobs-toc-heading-41)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

脚本库包含 33 个系统 `/bin/zsh` 入口，每个脚本包有同名 `.command` 和独立 `README.md`。源码、静态说明和运行时内置自述分别维护；运行时不读取 README。

运行态位于当前用户家目录的 `SourceTree.command`，备份态为 JobsGenesis 下的同名 Git 工作树。维护时保留两侧已有改动，修改完成后按相同相对路径同步脚本、README、资源及菜单配置；Git 元数据和系统生成文件不互相覆盖。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、菜单安装 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从本 README 所在目录执行：

```shell
/bin/zsh './【MacOS】安装SourceTree自定义菜单.command/【MacOS】安装SourceTree自定义菜单.command'
```

安装器先确认库发送目标，再选择菜单安装或配置回收。已有目标库回车保留，输入 `YES` 才备份替换。菜单按脚本路径合并并保留自定义显示标题、快捷键和显示设置，覆盖前生成可恢复备份；正在运行的 Sourcetree 正常退出、保存配置后再写入并重新打开，不强制结束。

菜单动作目标默认使用家目录运行副本；指定其它发送目录时使用该目标库，仓库动作参数为 `$REPO`，不是把多个路径拼接成一个参数。所有动作目标须存在、可执行且唯一。安装器本身保留终端交互，不挂成仓库菜单；其余 32 个任务入口可作为仓库动作。

详细步骤、依赖与风险见 [安装器 README](./【MacOS】安装SourceTree自定义菜单.command/README.md)。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行策略 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 终端运行：先展示固定内置自述，回车继续、`Ctrl+C` 取消；确认前不写日志、不执行项目业务。没有可交互输入且未明确识别 Sourcetree 时退出。
- Sourcetree 动作：根据明确环境或父进程链识别，无交互连续执行；相对脚本路径、非 TTY 或 `TERM=dumb` 单独不能作为身份依据。
- Sourcetree、非 TTY、`NO_COLOR` 使用纯文本输出；完整终端自述标题红色加粗、正文蓝色常规。业务错误不会被最后的成功输出掩盖。
- 递归动作跳过 Git、依赖、缓存与生成目录；具体范围及所有权过滤由各包 README 说明，明确目标错误时不回退到其它项目。
- 普通更新或升级回车跳过，输入任意字符后回车执行；危险替换或 hard 回退要求 `YES`。只拉取远程代码、逐层 Push 与终端 Pod Install 会转交独立终端，以对应入口确认和结果为准。
- 开发工具、Java 17 和项目 SDK 先检查实际可用性。打开类动作复用现有工具，不为打开项目自动安装依赖或清理全局缓存；工具缺失时提供明确排查入口。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、脚本索引 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 脚本包 | 说明 |
| --- | --- |
| `⏬只拉取远程代码` | [README](./【MacOS@SourceTree】⏬只拉取远程代码.command/README.md) |
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

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、维护和验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

回归覆盖入口确认、Sourcetree 纯文本、特殊字符路径、工具链健康、参数与默认值、命令失败传播、目录安全、产物选择和文档对账。Git 采用临时仓库复现，构建、工具安装和外部应用启动采用假命令；不把真实项目构建、提交或推送作为回归测试。

两态均执行所有入口的 `zsh -n`；按内容哈希及执行权限核对脚本、README、资源和 `actions.plist`，并检查菜单解档、目标唯一、`$REPO` 参数和实际可执行路径。运行态的 Git 元数据、备份态的子模块绑定以及 `.DS_Store` 保持各自独立。

验证完成的代码不代表全部外部环境验收：开发者签名、真实 Flutter/Xcode 构建、包管理器安装、Cloudflare 部署、具体 IDE/模拟器启动仍需在对应项目环境使用时确认结果。各 README 分别说明真实能力与未执行边界。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、日志和常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

各包 README 列出实际日志名称，默认位于系统临时目录。终端启动器的成功仅表示已提交启动；最终业务退出码和详细日志在子入口或新终端中。

- 菜单提示路径不可访问：重新运行安装器，检查动作是否指向当前运行副本且有执行位。
- Terminal/Sourcetree 缺工具：先检查各脚本声明的 PATH、SDK、版本管理器及工具健康；不依赖图形应用继承外部终端全部设置。
- 多项目歧义：显式传入目标工程或工作区，不依赖扫描顺序选第一个。
- 执行失败：保留现场，按非零退出码和日志中的目标排查；下载或替换失败使用覆盖前备份恢复。

手工配置的界面位置可参考以下图，最终字段以安装器生成配置为准：

<img src="./assets/image-20250726230655312.png" alt="Sourcetree 自定义动作配置" style="zoom:50%;" />

<img src="./assets/image-20250814100342111.png" alt="Sourcetree 菜单配置示例" style="zoom:50%;" />

## 六、<span id="repository-layout">目录结构</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

下面按当前磁盘第一层列出真实文件与目录；包内主脚本由下方完整名称直接进入。

```text
SourceTree.command/
├── README.md
├── assets/
├── icon.png
├── 【MacOS@SourceTree】⏬只拉取远程代码.command/  # 1 个入口
├── 【MacOS@SourceTree】⏬双击下载SourceTree效率脚本.command/  # 1 个入口
├── 【MacOS@SourceTree】♻️修复Flutter项目中文路径.command/  # 1 个入口
├── 【MacOS@SourceTree】♻️双击Git（识别子Git） 提交回退.command/  # 1 个入口
├── 【MacOS@SourceTree】⚙️收集当前Flutter工程的依赖.command/  # 1 个入口
├── 【MacOS@SourceTree】⚙️运行授权.command/  # 1 个入口
├── 【MacOS@SourceTree】同步edgetunnel代码后手动升级.command/  # 1 个入口
├── 【MacOS@SourceTree】用Android Studio打开.command/  # 1 个入口
├── 【MacOS@SourceTree】用Android Studio打开openjdk64-17.0.16.command/  # 1 个入口
├── 【MacOS@SourceTree】用Trae打开@openjdk64-17.0.16.command/  # 1 个入口
├── 【MacOS@SourceTree】用Trea打开.command/  # 1 个入口
├── 【MacOS@SourceTree】用VSCode打开.command/  # 1 个入口
├── 【MacOS@SourceTree】用VSCode打开@openjdk64-17.0.16.command/  # 1 个入口
├── 【MacOS@SourceTree】用终端打开.command/  # 1 个入口
├── 【MacOS@SourceTree】获取目标绝对地址.command/  # 1 个入口
├── 【MacOS@SourceTree】（只打开当前目录）用Xcode打开.command/  # 1 个入口
├── 【MacOS@SourceTree】（递归目录寻找工程@不适用于多工程项目）用Xcode打开.command/  # 1 个入口
├── 【MacOS@SourceTree】🌐获取远程仓库地址.command/  # 1 个入口
├── 【MacOS@SourceTree】🐦Flutter自动化生产代码.command/  # 1 个入口
├── 【MacOS@SourceTree】🐦Flutter重新拉取第三方依赖.command/  # 1 个入口
├── 【MacOS@SourceTree】🐦Flutter项目体检.command/  # 1 个入口
├── 【MacOS@SourceTree】🐦打开:运行Flutter项目.command/  # 1 个入口
├── 【MacOS@SourceTree】📘用Typora打开蓝皮书.command/  # 1 个入口
├── 【MacOS@SourceTree】📥修复Git无法Commit.command/  # 1 个入口
├── 【MacOS@SourceTree】📥修复Git无法Fetch.command/  # 1 个入口
├── 【MacOS@SourceTree】📦双击打包Flutter.android.command/  # 1 个入口
├── 【MacOS@SourceTree】📦双击打包Flutter.iOS.command/  # 1 个入口
├── 【MacOS@SourceTree】📦双击自动生成ipa文件.command/  # 1 个入口
├── 【MacOS@SourceTree】🚀逐层空白提交并Push.command/  # 1 个入口
├── 【MacOS@SourceTree】🪄配置并运行Magic Resume.command/  # 1 个入口
├── 【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.command/  # 1 个入口
├── 【MacOS@SourceTree】🫘打开终端运行Pod Install.command/  # 1 个入口
└── 【MacOS】安装SourceTree自定义菜单.command/  # 1 个入口
```

## 七、<span id="script-workflows">脚本执行流程</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

本仓共有 33 个用户入口。这里只列本仓维护的主入口；独立子 Git、测试、函数库及打包资源模板不作为用户运行入口。步骤来自静态源码与配套说明，不在真实业务仓执行安装、清理、构建或 Git 写操作。

### <span id="jobs-toc-heading-9" data-jobs-toc="v2">[【MacOS@SourceTree】⏬只拉取远程代码.command](./【MacOS@SourceTree】⏬只拉取远程代码.command/【MacOS@SourceTree】⏬只拉取远程代码.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 从独立终端安全同步只能拉取的第三方仓库，不提交、不推送。

- SourceTree 只负责打开 Terminal，终端显示自述并等待回车。
- 确认当前分支的明确远程上游，显示来源，成功 fetch 后固定目标提交。
- 检查工作区、暂存内容、未跟踪文件及本地独有提交；有风险时红字列明，精确输入 `YES` 才舍弃并同步。
- 忽略文件保留；可能覆盖忽略内容、嵌套仓库、子模块改动、未完成操作及上游不明确时停止，不递归父子仓。
- 核验最终提交与工作区，输出来源、日志和退出码。

### <span id="jobs-toc-heading-10" data-jobs-toc="v2">[【MacOS@SourceTree】⏬双击下载SourceTree效率脚本.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E2%8F%AC%E5%8F%8C%E5%87%BB%E4%B8%8B%E8%BD%BDSourceTree%E6%95%88%E7%8E%87%E8%84%9A%E6%9C%AC.command/%E3%80%90MacOS@SourceTree%E3%80%91%E2%8F%AC%E5%8F%8C%E5%87%BB%E4%B8%8B%E8%BD%BDSourceTree%E6%95%88%E7%8E%87%E8%84%9A%E6%9C%AC.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 先校验下载内容，再安全替换本机脚本库。

- 检查系统 Git 与目标运行目录，先确认是否允许替换。
  - 如果运行目录已存在，终端须输入 `YES`；Sourcetree 无交互模式停止，不覆盖已有库。
- 从预设仓库下载到暂存目录。
- 检查脚本语法和包结构，给入口补执行权限。
- 完整备份旧目录后替换并输出结果。

### <span id="jobs-toc-heading-11" data-jobs-toc="v2">[【MacOS@SourceTree】♻️修复Flutter项目中文路径.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E2%99%BB%EF%B8%8F%E4%BF%AE%E5%A4%8DFlutter%E9%A1%B9%E7%9B%AE%E4%B8%AD%E6%96%87%E8%B7%AF%E5%BE%84.command/%E3%80%90MacOS@SourceTree%E3%80%91%E2%99%BB%EF%B8%8F%E4%BF%AE%E5%A4%8DFlutter%E9%A1%B9%E7%9B%AE%E4%B8%AD%E6%96%87%E8%B7%AF%E5%BE%84.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 解码自有 Dart package 指令中的 URI 编码路径。

- 定位工程并限定可修改的自有 Dart 文件。
- 逐项检测编码路径，备份原文件后写入解码内容。
- 汇总修复数量，跳过生成和第三方文件。

### <span id="jobs-toc-heading-12" data-jobs-toc="v2">[【MacOS@SourceTree】♻️双击Git（识别子Git） 提交回退.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E2%99%BB%EF%B8%8F%E5%8F%8C%E5%87%BBGit%EF%BC%88%E8%AF%86%E5%88%AB%E5%AD%90Git%EF%BC%89%20%E6%8F%90%E4%BA%A4%E5%9B%9E%E9%80%80.command/%E3%80%90MacOS@SourceTree%E3%80%91%E2%99%BB%EF%B8%8F%E5%8F%8C%E5%87%BBGit%EF%BC%88%E8%AF%86%E5%88%AB%E5%AD%90Git%EF%BC%89%20%E6%8F%90%E4%BA%A4%E5%9B%9E%E9%80%80.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 将选中历史之后的提交退回暂存区，或在终端明确选择回退模式。

- 定位仓库，检查冲突、锁与未完成 Git 操作。
- 选择回退目标与模式。
  - 如果来自 Sourcetree，只执行保留内容的 soft；hard 只在终端输入 YES 后允许。
- 执行并核对状态，不 Fetch、不提交、不推送，也不递归重置子仓。

### <span id="jobs-toc-heading-13" data-jobs-toc="v2">[【MacOS@SourceTree】⚙️收集当前Flutter工程的依赖.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E2%9A%99%EF%B8%8F%E6%94%B6%E9%9B%86%E5%BD%93%E5%89%8DFlutter%E5%B7%A5%E7%A8%8B%E7%9A%84%E4%BE%9D%E8%B5%96.command/%E3%80%90MacOS@SourceTree%E3%80%91%E2%9A%99%EF%B8%8F%E6%94%B6%E9%9B%86%E5%BD%93%E5%89%8DFlutter%E5%B7%A5%E7%A8%8B%E7%9A%84%E4%BE%9D%E8%B5%96.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 归档已解析的 Flutter / 原生依赖和工程清单。

- 定位项目并检查已有依赖解析；默认不执行 pub get。
- 选择全量或终端多选范围，复制实际包源码与工程依赖清单。
- 写入可追溯说明并生成桌面 Zip，默认不改工程依赖。
  - 显式启用 `flutter pub get` 时会联网，并可能更新工程依赖解析文件。

### <span id="jobs-toc-heading-14" data-jobs-toc="v2">[【MacOS@SourceTree】⚙️运行授权.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E2%9A%99%EF%B8%8F%E8%BF%90%E8%A1%8C%E6%8E%88%E6%9D%83.command/%E3%80%90MacOS@SourceTree%E3%80%91%E2%9A%99%EF%B8%8F%E8%BF%90%E8%A1%8C%E6%8E%88%E6%9D%83.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 为明确选定的 .command 文件添加用户执行权限并移除其隔离属性。

- 解析一个或多个目标，默认只扫描目标第一层。
- 核对 .command 普通文件，按显式递归参数扩展扫描。
- 逐项修改执行权限、移除隔离属性并输出成功 / 失败统计；文件正文保留。

### <span id="jobs-toc-heading-15" data-jobs-toc="v2">[【MacOS@SourceTree】同步edgetunnel代码后手动升级.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E5%90%8C%E6%AD%A5edgetunnel%E4%BB%A3%E7%A0%81%E5%90%8E%E6%89%8B%E5%8A%A8%E5%8D%87%E7%BA%A7.command/%E3%80%90MacOS@SourceTree%E3%80%91%E5%90%8C%E6%AD%A5edgetunnel%E4%BB%A3%E7%A0%81%E5%90%8E%E6%89%8B%E5%8A%A8%E5%8D%87%E7%BA%A7.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 为已同步的 edgetunnel 仓库配置并部署 Worker。

- 校验仓库身份、Node / 包管理器和 Wrangler。
- 检查 Cloudflare 登录、部署配置与 KV 绑定。
- 安装工程依赖并执行部署，显示结果；本入口不负责 Git 拉取或提交。

### <span id="jobs-toc-heading-16" data-jobs-toc="v2">[【MacOS@SourceTree】用Android Studio打开.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8Android%20Studio%E6%89%93%E5%BC%80.command/%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8Android%20Studio%E6%89%93%E5%BC%80.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 用 Android Studio 打开明确选定的项目或文档。

- 解析并校验目录或文件目标。
- 先尝试健康命令行入口，再查找本机应用。
- 调用应用打开目标并保留真实退出状态。
  - 如果工具不存在，打开官方下载页并报告需要安装，不把浏览器打开当成工程已打开。

### <span id="jobs-toc-heading-17" data-jobs-toc="v2">[【MacOS@SourceTree】用Android Studio打开openjdk64-17.0.16.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8Android%20Studio%E6%89%93%E5%BC%80openjdk64-17.0.16.command/%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8Android%20Studio%E6%89%93%E5%BC%80openjdk64-17.0.16.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 用 Android Studio 打开明确选定的项目或文档。

- 解析并校验目录或文件目标。
- 发现并验证健康 Java 17，在本次启动进程中设置 Java 环境。
  - 存在健康的 jenv 映射时，还会保存项目 `.java-version`。
- 先尝试健康命令行入口，再查找本机应用。
- 调用应用打开目标并保留真实退出状态。
  - 如果工具不存在，打开官方下载页并报告需要安装，不把浏览器打开当成工程已打开。

### <span id="jobs-toc-heading-18" data-jobs-toc="v2">[【MacOS@SourceTree】用Trae打开@openjdk64-17.0.16.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8Trae%E6%89%93%E5%BC%80@openjdk64-17.0.16.command/%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8Trae%E6%89%93%E5%BC%80@openjdk64-17.0.16.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 用 Trae 打开明确选定的项目或文档。

- 解析并校验目录或文件目标。
- 发现并验证健康 Java 17，在本次启动进程中设置 Java 环境。
  - 存在健康的 jenv 映射时，还会保存项目 `.java-version`。
- 先尝试健康命令行入口，再查找本机应用。
- 调用应用打开目标并保留真实退出状态。
  - 如果工具不存在，打开官方下载页并报告需要安装，不把浏览器打开当成工程已打开。

### <span id="jobs-toc-heading-19" data-jobs-toc="v2">[【MacOS@SourceTree】用Trea打开.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8Trea%E6%89%93%E5%BC%80.command/%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8Trea%E6%89%93%E5%BC%80.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 用 Trae 打开明确选定的项目或文档。

- 解析并校验目录或文件目标。
- 先尝试健康命令行入口，再查找本机应用。
- 调用应用打开目标并保留真实退出状态。
  - 如果工具不存在，打开官方下载页并报告需要安装，不把浏览器打开当成工程已打开。

### <span id="jobs-toc-heading-20" data-jobs-toc="v2">[【MacOS@SourceTree】用VSCode打开.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8VSCode%E6%89%93%E5%BC%80.command/%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8VSCode%E6%89%93%E5%BC%80.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 用 VS Code 打开明确选定的项目或文档。

- 解析并校验目录或文件目标。
- 先尝试健康命令行入口，再查找本机应用。
- 调用应用打开目标并保留真实退出状态。
  - 如果工具不存在，打开官方下载页并报告需要安装，不把浏览器打开当成工程已打开。

### <span id="jobs-toc-heading-21" data-jobs-toc="v2">[【MacOS@SourceTree】用VSCode打开@openjdk64-17.0.16.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8VSCode%E6%89%93%E5%BC%80@openjdk64-17.0.16.command/%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8VSCode%E6%89%93%E5%BC%80@openjdk64-17.0.16.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 用 VS Code 打开明确选定的项目或文档。

- 解析并校验目录或文件目标。
- 发现并验证健康 Java 17，在本次启动进程中设置 Java 环境。
  - 存在健康的 jenv 映射时，还会保存项目 `.java-version`。
- 先尝试健康命令行入口，再查找本机应用。
- 调用应用打开目标并保留真实退出状态。
  - 如果工具不存在，打开官方下载页并报告需要安装，不把浏览器打开当成工程已打开。

### <span id="jobs-toc-heading-22" data-jobs-toc="v2">[【MacOS@SourceTree】用终端打开.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8%E7%BB%88%E7%AB%AF%E6%89%93%E5%BC%80.command/%E3%80%90MacOS@SourceTree%E3%80%91%E7%94%A8%E7%BB%88%E7%AB%AF%E6%89%93%E5%BC%80.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开 Terminal 并进入指定仓库或文件所在目录。

- 解析仓库参数，文件目标转换为父目录。
- 校验目录并构造安全的 cd 命令。
- 打开系统终端执行该命令。

### <span id="jobs-toc-heading-23" data-jobs-toc="v2">[【MacOS@SourceTree】获取目标绝对地址.command](./%E3%80%90MacOS@SourceTree%E3%80%91%E8%8E%B7%E5%8F%96%E7%9B%AE%E6%A0%87%E7%BB%9D%E5%AF%B9%E5%9C%B0%E5%9D%80.command/%E3%80%90MacOS@SourceTree%E3%80%91%E8%8E%B7%E5%8F%96%E7%9B%AE%E6%A0%87%E7%BB%9D%E5%AF%B9%E5%9C%B0%E5%9D%80.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 取得所选路径的物理绝对地址并复制。

- 解析仓库、文件或目录参数，核对目标或其父目录。
  - 目标尚不存在但父目录有效时，仍可给出绝对地址；缺少 `pbcopy` 时只打印结果。
- 将路径解析为物理绝对地址。
- 在输出窗口显示并复制到剪贴板。

### <span id="jobs-toc-heading-24" data-jobs-toc="v2">[【MacOS@SourceTree】（只打开当前目录）用Xcode打开.command](./%E3%80%90MacOS@SourceTree%E3%80%91%EF%BC%88%E5%8F%AA%E6%89%93%E5%BC%80%E5%BD%93%E5%89%8D%E7%9B%AE%E5%BD%95%EF%BC%89%E7%94%A8Xcode%E6%89%93%E5%BC%80.command/%E3%80%90MacOS@SourceTree%E3%80%91%EF%BC%88%E5%8F%AA%E6%89%93%E5%BC%80%E5%BD%93%E5%89%8D%E7%9B%AE%E5%BD%95%EF%BC%89%E7%94%A8Xcode%E6%89%93%E5%BC%80.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 用 Xcode 打开当前目录的明确工程或工作区。

- 解析仓库参数，检查顶层 .xcworkspace / .xcodeproj。
- 选择唯一或明确指定的工程；多候选时要求明确目标。
- 调用 Xcode 打开，不自动执行 Pod 安装。

### <span id="jobs-toc-heading-25" data-jobs-toc="v2">[【MacOS@SourceTree】（递归目录寻找工程@不适用于多工程项目）用Xcode打开.command](./%E3%80%90MacOS@SourceTree%E3%80%91%EF%BC%88%E9%80%92%E5%BD%92%E7%9B%AE%E5%BD%95%E5%AF%BB%E6%89%BE%E5%B7%A5%E7%A8%8B@%E4%B8%8D%E9%80%82%E7%94%A8%E4%BA%8E%E5%A4%9A%E5%B7%A5%E7%A8%8B%E9%A1%B9%E7%9B%AE%EF%BC%89%E7%94%A8Xcode%E6%89%93%E5%BC%80.command/%E3%80%90MacOS@SourceTree%E3%80%91%EF%BC%88%E9%80%92%E5%BD%92%E7%9B%AE%E5%BD%95%E5%AF%BB%E6%89%BE%E5%B7%A5%E7%A8%8B@%E4%B8%8D%E9%80%82%E7%94%A8%E4%BA%8E%E5%A4%9A%E5%B7%A5%E7%A8%8B%E9%A1%B9%E7%9B%AE%EF%BC%89%E7%94%A8Xcode%E6%89%93%E5%BC%80.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 递归定位明确的 Xcode 工程并打开。

- 解析目标目录，跳过依赖和生成目录递归查找工程。
- 核对候选；存在歧义时停止，使用明确工程路径重试。
- 用 Xcode 打开所选工作区或工程，不自动安装依赖。

### <span id="jobs-toc-heading-26" data-jobs-toc="v2">[【MacOS@SourceTree】🌐获取远程仓库地址.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%8C%90%E8%8E%B7%E5%8F%96%E8%BF%9C%E7%A8%8B%E4%BB%93%E5%BA%93%E5%9C%B0%E5%9D%80.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%8C%90%E8%8E%B7%E5%8F%96%E8%BF%9C%E7%A8%8B%E4%BB%93%E5%BA%93%E5%9C%B0%E5%9D%80.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 读取当前 Git 的首选远端地址并复制。

- 解析目标仓库并验证 Git 可执行。
- 按脚本优先级读取 remote 与原始 URL。
- 显示远端名称和地址，复制 URL；不联网探测。

### <span id="jobs-toc-heading-27" data-jobs-toc="v2">[【MacOS@SourceTree】🐦Flutter自动化生产代码.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%90%A6Flutter%E8%87%AA%E5%8A%A8%E5%8C%96%E7%94%9F%E4%BA%A7%E4%BB%A3%E7%A0%81.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%90%A6Flutter%E8%87%AA%E5%8A%A8%E5%8C%96%E7%94%9F%E4%BA%A7%E4%BB%A3%E7%A0%81.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 按工程实际启用的生成器生成代码与资源。

- 定位项目与 SDK，读取 pubspec.yaml 和生成目录。
- 按配置顺序执行 clean / get、代码生成、图标、国际化或 Protobuf。
  - 默认先清理并拉取依赖；`build_runner` 可覆盖冲突的生成输出。
- 报告结果；持续 watch 仅允许明确的终端模式，Sourcetree 跳过。

### <span id="jobs-toc-heading-28" data-jobs-toc="v2">[【MacOS@SourceTree】🐦Flutter重新拉取第三方依赖.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%90%A6Flutter%E9%87%8D%E6%96%B0%E6%8B%89%E5%8F%96%E7%AC%AC%E4%B8%89%E6%96%B9%E4%BE%9D%E8%B5%96.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%90%A6Flutter%E9%87%8D%E6%96%B0%E6%8B%89%E5%8F%96%E7%AC%AC%E4%B8%89%E6%96%B9%E4%BE%9D%E8%B5%96.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 清理当前 Flutter 工程并重建依赖解析。

- 定位项目，复用其全局或 FVM SDK。
- 顺序执行 flutter clean 与 flutter pub get。
- 输出执行结果，任一步失败停止。

### <span id="jobs-toc-heading-29" data-jobs-toc="v2">[【MacOS@SourceTree】🐦Flutter项目体检.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%90%A6Flutter%E9%A1%B9%E7%9B%AE%E4%BD%93%E6%A3%80.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%90%A6Flutter%E9%A1%B9%E7%9B%AE%E4%BD%93%E6%A3%80.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 检查 Flutter 工具链或执行明确选择的依赖准备模式。

- 解析项目与模式参数，检查 SDK。
- 按模式执行 doctor 或依赖准备。
  - 如果选择仅 get，拉取依赖；如果选择 clean-get，先清理再拉取。
- 输出诊断和日志，保留失败状态。

### <span id="jobs-toc-heading-30" data-jobs-toc="v2">[【MacOS@SourceTree】🐦打开:运行Flutter项目.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%90%A6%E6%89%93%E5%BC%80%3A%E8%BF%90%E8%A1%8CFlutter%E9%A1%B9%E7%9B%AE.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%90%A6%E6%89%93%E5%BC%80%3A%E8%BF%90%E8%A1%8CFlutter%E9%A1%B9%E7%9B%AE.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 将 Flutter 运行交给目标工程的 Terminal 流程。

- 解析项目路径并查找该项目的 setup.command。
- 构造运行命令并打开系统终端。
  - 如果没有 setup.command，使用校验后的标准 Flutter 运行流程。
- 在新终端查看设备等待、依赖和运行结果。

### <span id="jobs-toc-heading-31" data-jobs-toc="v2">[【MacOS@SourceTree】📘用Typora打开蓝皮书.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%98%E7%94%A8Typora%E6%89%93%E5%BC%80%E8%93%9D%E7%9A%AE%E4%B9%A6.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%98%E7%94%A8Typora%E6%89%93%E5%BC%80%E8%93%9D%E7%9A%AE%E4%B9%A6.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 用 Typora 打开明确选定的项目或文档。

- 解析并校验目录或文件目标。
- 先尝试健康命令行入口，再查找本机应用。
- 调用应用打开目标并保留真实退出状态。
  - 如果工具不存在，打开官方下载页并报告需要安装，不把浏览器打开当成工程已打开。

### <span id="jobs-toc-heading-32" data-jobs-toc="v2">[【MacOS@SourceTree】📥修复Git无法Commit.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%A5%E4%BF%AE%E5%A4%8DGit%E6%97%A0%E6%B3%95Commit.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%A5%E4%BF%AE%E5%A4%8DGit%E6%97%A0%E6%B3%95Commit.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 按故障场景修复阻止本地 Commit 的元数据问题。

- 定位仓库，按 7 个场景检查工作树绑定、索引锁、`.gitmodules`、路径迁移与子模块等阻塞。
- 备份后修复允许处理的配置或阻塞项，刷新 / 暂存索引并复验。
  - 子模块缺失时可能联网初始化；已有子仓的真实修改保留，归属或安全前提不明时停止。
- 输出修复和复验结果，不替用户创建提交或推送。

### <span id="jobs-toc-heading-33" data-jobs-toc="v2">[【MacOS@SourceTree】📥修复Git无法Fetch.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%A5%E4%BF%AE%E5%A4%8DGit%E6%97%A0%E6%B3%95Fetch.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%A5%E4%BF%AE%E5%A4%8DGit%E6%97%A0%E6%B3%95Fetch.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 定位并修复可安全处理的远端跟踪引用故障。

- 读取远端并执行 Fetch，收集真实错误。
- 根据错误定位实际阻塞引用，先备份再处理允许修复的项。
- 每处理一项立即重新 Fetch；成功即停止，仍失败则保留日志；工作区、索引及本地分支指向保留。

### <span id="jobs-toc-heading-34" data-jobs-toc="v2">[【MacOS@SourceTree】📦双击打包Flutter.android.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%A6%E5%8F%8C%E5%87%BB%E6%89%93%E5%8C%85Flutter.android.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%A6%E5%8F%8C%E5%87%BB%E6%89%93%E5%8C%85Flutter.android.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 构建选定 Flutter 工程的 APK 或 AAB。

- 定位工程和全局 / FVM SDK，校验构建参数。
- 按所选模式处理依赖并执行 APK、AAB 或两种构建。
- 核验输出，显示产物与实时日志；构建失败返回非零状态。

### <span id="jobs-toc-heading-35" data-jobs-toc="v2">[【MacOS@SourceTree】📦双击打包Flutter.iOS.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%A6%E5%8F%8C%E5%87%BB%E6%89%93%E5%8C%85Flutter.iOS.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%A6%E5%8F%8C%E5%87%BB%E6%89%93%E5%8C%85Flutter.iOS.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 执行 Flutter iOS 归档并导出 IPA。

- 定位工程、SDK 和签名 / 导出参数。
- 按所选配置执行 flutter build ipa。
- 核验 IPA；仅产生 xcarchive 时明确提示后续导出要求。

### <span id="jobs-toc-heading-36" data-jobs-toc="v2">[【MacOS@SourceTree】📦双击自动生成ipa文件.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%A6%E5%8F%8C%E5%87%BB%E8%87%AA%E5%8A%A8%E7%94%9F%E6%88%90ipa%E6%96%87%E4%BB%B6.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%93%A6%E5%8F%8C%E5%87%BB%E8%87%AA%E5%8A%A8%E7%94%9F%E6%88%90ipa%E6%96%87%E4%BB%B6.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 把明确选定的现有真机 App 重新封装成 IPA。

- 根据项目、配置或 --app 定位 iPhoneOS App，拒绝模拟器产物与歧义。
- 在独立临时 Payload 中复制 App 并压缩。
- 验证输出并移动到指定目录，不执行构建、重签名或 App Store 导出。

### <span id="jobs-toc-heading-37" data-jobs-toc="v2">[【MacOS@SourceTree】🚀逐层空白提交并Push.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%9A%80%E9%80%90%E5%B1%82%E7%A9%BA%E7%99%BD%E6%8F%90%E4%BA%A4%E5%B9%B6Push.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%9A%80%E9%80%90%E5%B1%82%E7%A9%BA%E7%99%BD%E6%8F%90%E4%BA%A4%E5%B9%B6Push.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 按子仓到父仓顺序提交并同步已配置远端。

- 发现目标子树与向上父仓，检查分支和远端映射。
- 从 Sourcetree 转交 Terminal，阅读自述并回车确认。
  - 有上次失败检查点时，选择从失败处继续或从头执行，并复核已完成仓库。
  - 有游离态仓库时，先列出舍弃范围和恢复目标；输入 `YES` 后才丢弃其中临时改动与独有提交、恢复远端版本。
  - 队列命中 OC 独立快照例外时，在 Git 写入前停止。
- 由内向外获取远端历史，暂存本层变化并在有变化时提交。
  - 只复用已有本地分支；整合冲突或目标线路失败时停止，保留现场，不强推。
- 整合全部目标线路，再将同一最终 HEAD 逐条推送并核验，随后处理父仓指针。

### <span id="jobs-toc-heading-38" data-jobs-toc="v2">[【MacOS@SourceTree】🪄配置并运行Magic Resume.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%AA%84%E9%85%8D%E7%BD%AE%E5%B9%B6%E8%BF%90%E8%A1%8CMagic%20Resume.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%AA%84%E9%85%8D%E7%BD%AE%E5%B9%B6%E8%BF%90%E8%A1%8CMagic%20Resume.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 准备并后台运行匹配的 Magic Resume 项目。

- 验证当前仓库；不匹配时扫描同级官方仓，仍无匹配才克隆到安全空目录。
- 检查项目工具并执行 pnpm install。
- 核对端口后后台启动 pnpm dev，服务就绪再打开网页，日志与 PID 留存。

### <span id="jobs-toc-heading-39" data-jobs-toc="v2">[【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%AB%98%E5%9C%A8Sourcetree%E4%B8%AD%E8%BF%90%E8%A1%8CPod%20Install.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%AB%98%E5%9C%A8Sourcetree%E4%B8%AD%E8%BF%90%E8%A1%8CPod%20Install.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 在指定 Podfile 目录执行受控的 Pod 安装。

- 解析目标目录并验证 Ruby / pod 实际可用。
- 检查参数、单目录边界与 Podfile。
- 默认执行纯净模式 pod install --no-repo-update，输出实时日志，不升级全局工具链。

### <span id="jobs-toc-heading-40" data-jobs-toc="v2">[【MacOS@SourceTree】🫘打开终端运行Pod Install.command](./%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%AB%98%E6%89%93%E5%BC%80%E7%BB%88%E7%AB%AF%E8%BF%90%E8%A1%8CPod%20Install.command/%E3%80%90MacOS@SourceTree%E3%80%91%F0%9F%AB%98%E6%89%93%E5%BC%80%E7%BB%88%E7%AB%AF%E8%BF%90%E8%A1%8CPod%20Install.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 把 Pod Install 交给独立 Terminal 执行。

- 解析目标目录并检查 Podfile 与同库 Pod 安装入口。
- 通过 AppleScript 打开终端并传入明确目录。
- 子入口展示自述、确认后安装；启动器成功仅代表已转交。

### <span id="jobs-toc-heading-41" data-jobs-toc="v2">[【MacOS】安装SourceTree自定义菜单.command](./%E3%80%90MacOS%E3%80%91%E5%AE%89%E8%A3%85SourceTree%E8%87%AA%E5%AE%9A%E4%B9%89%E8%8F%9C%E5%8D%95.command/%E3%80%90MacOS%E3%80%91%E5%AE%89%E8%A3%85SourceTree%E8%87%AA%E5%AE%9A%E4%B9%89%E8%8F%9C%E5%8D%95.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 发送脚本库并合并安装 Sourcetree 自定义动作。

- 选择脚本库发送目标，核对既有内容与备份替换选择。
- 选择安装或回收配置，备份当前动作配置。
- 合并动作并保留自定义标题与快捷键，重新打开 Sourcetree 后核验路径和参数。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
