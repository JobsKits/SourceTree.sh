# `【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

在明确项目目录执行 [**CocoaPods**](https://cocoapods.org/) `pod install`，兼容 [**Sourcetree**](https://www.sourcetreeapp.com/) 精简环境。默认单目录、纯净模式、`--no-repo-update`，不安装或升级全局工具链。

## 一、执行前检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需要健康 `pod --version`，其 [**Ruby**](https://www.ruby-lang.org/) / gem / shim 必须可用；仅找到命令名不足以继续。目标必须有 `Podfile`；不要求预先存在 `.xcodeproj`，允许由 Podfile 描述项目或生成流程。使用 UTF-8，保留已有 `RUBYOPT` 并追加编码设置。

## 二、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh './【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.command' '/项目目录'
/bin/zsh './【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.command' --with-hooks '/项目目录'
/bin/zsh './【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.command' --recursive --deployment --repo-update '/项目父目录'
```

终端显示固定内置自述并等待回车；`Ctrl+C` 取消。Sourcetree 仓库动作传 `$REPO`，无交互连续执行。非 Sourcetree 且没有可交互输入时退出。

## 三、参数和默认值 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 参数 | 行为 |
| --- | --- |
| 无路径参数 | 使用 `SOURCETREE_REPO_PATH`、`REPO` 或当前目录 |
| `--recursive` | 扫描子目录 Podfile，否则仅目标本身 |
| `--pure` | 默认，两个 Jobs 跳过外部增强变量设为 `1` |
| `--with-hooks` / `--full` | 两个 Jobs 跳过变量设为 `0` |
| `--repo-update` | 替换默认 `--no-repo-update` |
| `--deployment` | 限制依赖锁文件变更，参数顺序不影响它 |
| `--` | 后续参数作为路径，不再解析选项 |

只接受一个目标；多个目标及未知选项报错，不静默覆盖。拖入路径去除外围引号与末尾 CRLF 换行，文件参数转换为所在目录。

## 四、范围和结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

递归跳过 `.git`、`node_modules`、`Pods`、`.dart_tool`、`build`、`DerivedData`。递归会先保存 NUL 分隔列表并检查 `find` 的退出状态，全部枚举成功后才安装；枚举失败不处理已输出的部分目录，临时列表在该安装流程结束时清理。每个目录独立记录命令结果；任意失败最终返回非零，递归未找到 Podfile 也报错。外部 ANSI 码过滤后同步屏幕与日志，管道不会吞掉 pod 退出码。

## 五、风险和日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

依赖安装可能下载文件、更新 `Pods`、`Podfile.lock` 和 workspace。纯净模式只是约定变量，只有 Podfile 主动支持这些变量时才能跳过增强；它不阻止 Podfile 本身的业务代码。日志位于系统临时目录，文件名 `【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.log`；启动前不写文件。

## 六、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

已通过 `zsh -n`；假 pod 验证参数顺序、中文空格和 CRLF 拖入路径、健康检查失败、安装失败、纯文本输出、递归排除与失败汇总，并用假 `find` 验证部分枚举失败提前停止和临时列表清理。未对真实项目执行 `pod install`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
