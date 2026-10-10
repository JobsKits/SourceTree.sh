# `【MacOS@SourceTree】🫘打开终端运行Pod Install.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

从 [**Sourcetree**](https://www.sourcetreeapp.com/) 打开 Terminal，并转交同库 [**CocoaPods**](https://cocoapods.org/) 安装入口。完整安装参数与边界见 [Pod Install README](../【MacOS@SourceTree】🫘在Sourcetree中运行Pod%20Install.command/README.md)。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh './【MacOS@SourceTree】🫘打开终端运行Pod Install.command' '/项目目录'
```

Sourcetree 仓库动作参数为 `$REPO`。终端独立调用先显示自述并回车确认；Sourcetree 启动器无交互，新终端中的子入口仍显示自述并等待回车。`Ctrl+C` 取消后不安装。

## 二、目录和依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

只接受一个目标目录；无参数使用 `SOURCETREE_REPO_PATH`、`REPO` 或当前目录。文件参数取父目录；目录必须包含 `Podfile`。需要系统 `osascript` 及同库 Pod Install 子入口，转发前检查子入口的 `zsh -n` 语法。

## 三、执行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

通过 AppleScript 的 `argv` 和 `quoted form` 传递脚本与目录，支持中文、空格、引号及其它 shell 特殊字符；新终端调用 `/bin/zsh` 子入口，再输出安装退出码。默认安装为纯净模式的 `pod install --no-repo-update`。子入口自行检查 CocoaPods 健康状态。

## 四、结果与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

启动器成功只表示已向 Terminal 提交命令，不能代表依赖安装成功。实际安装结果、退出码及失败原因在新终端与子入口日志中；安装会影响依赖、锁文件和 workspace。系统拒绝自动化权限时启动器返回失败。

## 五、日志和常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

启动日志位于系统临时目录，文件名 `【MacOS@SourceTree】🫘打开终端运行Pod Install.log`；实际安装日志使用子入口文件名。找不到子入口时保留完整脚本库目录；缺少 Podfile 时传正确项目根目录；Terminal 拒绝启动时检查系统自动化授权。

## 六、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

已通过 `zsh -n`，隔离检查目标/子入口校验和 AppleScript argv 转义。未实际打开 Terminal 或安装真实依赖。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
