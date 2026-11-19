# macOS 动作隔离测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#jobs-toc-heading-2)
- [二、验证范围](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[GitRemote.Tests.zsh](【MacOS】GitRemote.Tests.zsh/【MacOS】GitRemote.Tests.zsh) 读取远程地址动作的函数定义，以临时 [**Git**](https://git-scm.com/) 仓库和命令替身验证收集、选择、复制、网页转换及依赖失败行为。测试不会联网、真实安装软件、启动浏览器或写入系统剪贴板。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录的真实终端运行：

```shell
/bin/zsh 【MacOS】GitRemote.Tests.zsh/【MacOS】GitRemote.Tests.zsh
```

依赖 macOS 自带 zsh、Git 和基础命令；依赖安装分支的上游只读检查需要可用 Command Line Tools。已安装 [**fzf**](https://github.com/junegunn/fzf) 时额外验证真实二进制的选项健康探针；没有安装时跳过此探针，不安装软件。非 TTY 会停止，避免把生产选择器的终端门禁误报为成功。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 无远程、唯一地址、多远程、单 remote 多 fetch / push URL、完整 URL 去重、显式 remote 与 `insteadOf` 展开。
- 中文与空格路径、输入文件、最近嵌套工作树、`.git` 指针文件和进程 Git 环境隔离。
- 复制与打开两个真实入口的文件作用域寻址、中文空格与单引号改名目录、无关工作目录、相对路径和只有脚本名的启动方式；这些场景不替换路径解析函数。
- `zsh -c` 文本启动时按原始脚本名寻找隔离 HOME 内的运行副本，忽略工作目录内名为 `zsh` 的干扰文件；缺少副本时明确失败，不转交虚构路径。
- Terminal 外部命令替身捕获完整脚本路径、仓库路径及远程名；转交前脚本缺失时停止。单地址使用完整入口验证获取动作复制原始 URL、打开动作使用转换后的网页 URL。
- 选择菜单、终端摘要和日志完整显示原始地址，保留 `git@`、HTTP 用户信息、查询参数与片段；原始 URL 复制、HTTP(S) / SSH / SCP / Git 网页转换、控制字符拒绝与浏览器目标。
- 替身 fzf 第二行选择、隐藏 ID 映射、用户默认配置隔离、取消、无匹配、空输出、失败和伪造结果。
- 依赖健康、末端缺失、上游多层缺失、安装失败、安装后复检失败及既有 Homebrew 复用；安装均由替身执行。

每例在独立子进程运行，临时目录结束后精确清理。预期失败会输出生产错误提示，最终以通过 / 失败计数和退出码判断结果。真实 Terminal 启动、交互式 fzf 按键、菜单重载与浏览器窗口仍须另行验收，不能由命令替身代替。


[FlutterHarmonyBuild.Tests.rb](FlutterHarmonyBuild.Tests.rb/FlutterHarmonyBuild.Tests.rb) 用 `ruby FlutterHarmonyBuild.Tests.rb/FlutterHarmonyBuild.Tests.rb` 运行：仅以私有假 Flutter / Node / OHPM / Hvigor / Java 验证鸿蒙默认双包及失败传播；不联网、不真实构建、不修改菜单或签名。覆盖普通 CLI 单目标兼容、Sourcetree 固定 `all/release` 覆盖环境值，以及 APP 构建删除 HAP 时的最终双包复核。

[FlutterRunDispatch.Tests.rb](FlutterRunDispatch.Tests.rb/FlutterRunDispatch.Tests.rb) 用 `ruby FlutterRunDispatch.Tests.rb/FlutterRunDispatch.Tests.rb` 运行：在隔离目录验证 Flutter 运行入口的同包资源、完整目录复制改名、特殊字符参数、无关工作目录、工程 `setup.command` 优先、资源缺失停止与 dry-run 不执行。仅使用假运行器，不打开 Terminal、不下载 SDK、不启动真实 Flutter 或模拟器。

[InstallerGitCopy.Tests.rb](InstallerGitCopy.Tests.rb/InstallerGitCopy.Tests.rb) 用 `ruby InstallerGitCopy.Tests.rb/InstallerGitCopy.Tests.rb` 运行：提取菜单安装器函数，在私有临时目录验证 Unix socket 在 NUL 清单中预排除、同名普通文件与文件属性保留、独立 `.git/` 和外置 gitdir 的复制、源配置与索引不变、成功发送的旧目录备份，以及读取 / 提取 / 枚举失败时停止并保护旧目标；同时检查中文跳过提示、无原始 socket 噪声、缺末尾换行的诊断和临时清单清理。需要系统 Ruby、Git、find、tar 与 xattr；不复制到真实运行库、不操作菜单、不联网。

[InstallerMenuCompatibility.Tests.rb](InstallerMenuCompatibility.Tests.rb/InstallerMenuCompatibility.Tests.rb) 用 `ruby InstallerMenuCompatibility.Tests.rb/InstallerMenuCompatibility.Tests.rb` 运行：以不同临时 HOME、源库和目标库构造跨机菜单，验证旧用户路径和 Flutter 冒号迁移、健康运行库选择、保留旧库时整组回退、错误拒绝、自定义设置及额外动作保留、重装幂等；应用运行 / 未运行、预检失败与最终合并失败使用替身验证，不启动真实 SourceTree、不修改真实菜单。

[PushRepair.Tests.zsh](【MacOS】PushRepair.Tests.zsh/README.md) 使用临时工作树与本地 bare 远端完成 32 个场景，覆盖 Push 修复的历史整合、本地文件迁入同名目录、目标映射、冲突与隐藏／损坏索引保护、快进／分叉 ignored 文件碰撞、新增路径祖先文件／软链、隐藏子模块改动、并发更新及应答丢失、hook 与额外标签、结果与跟踪引用核验；不连接真实平台。从本 `Tests` 目录执行：

```shell
/bin/zsh '【MacOS】PushRepair.Tests.zsh/【MacOS】PushRepair.Tests.zsh'
```

[CommitPathRepair.Tests.zsh](【MacOS】CommitPathRepair.Tests.zsh/README.md) 在隔离仓库验证旧文件删除、文件变目录、Sourcetree 旧路径、部分暂存及索引保护；包括先 `add -f` 两子项再 `rm` 旧父路径的真实报错顺序、已暂存替换诊断与相似前缀边界。不暂存或提交真实业务仓库。在本目录运行：

```shell
/bin/zsh '【MacOS】CommitPathRepair.Tests.zsh/【MacOS】CommitPathRepair.Tests.zsh'
```

[CommitReset.Tests.zsh](【MacOS】CommitReset.Tests.zsh/README.md) 在临时仓库验证回退脚本的远端别名、无 upstream 候选、显式引用、失败停止及索引／工作区／父仓保护；不回退真实业务仓库。在本目录运行：

```shell
/bin/zsh '【MacOS】CommitReset.Tests.zsh/【MacOS】CommitReset.Tests.zsh' --run
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
