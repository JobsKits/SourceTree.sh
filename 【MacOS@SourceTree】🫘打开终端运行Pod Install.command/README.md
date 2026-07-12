# `【MacOS@SourceTree】🫘打开终端运行Pod Install.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

> 这是一个 [**Sourcetree**](https://www.sourcetreeapp.com/) 自定义动作脚本：以当前仓库为起点打开 Terminal.app，并在可见终端中运行 [**CocoaPods**](https://cocoapods.org/) 的 `pod install`。

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 希望从 Sourcetree 当前仓库直接打开终端并安装 Pod 依赖。
- 希望在独立 Terminal.app 窗口里持续查看完整安装过程和错误信息。
- 脚本只处理当前项目根目录，不递归查找子项目的 `Podfile`。

## 二、Sourcetree 配置 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在 Sourcetree 的“偏好设置 → 自定义操作”中新增动作：

| 配置项 | 内容 |
| --- | --- |
| 菜单名称 | `🫘打开终端运行 Pod Install` |
| 要运行的脚本 | `./【MacOS@SourceTree】🫘打开终端运行Pod Install.command` |
| 参数 | `$REPO` |

Sourcetree 调用时不会等待回车；脚本会直接打开 Terminal.app，再把当前仓库绝对路径和 `pod install` 命令提交给终端。

## 三、执行前检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 当前仓库根目录需要存在 `Podfile`。
- 终端登录环境需要能够调用 `pod`。
- `pod install` 可能联网下载依赖，也可能修改 `Pods`、`Podfile.lock` 和工作区文件；建议先确认项目当前改动。
- 首次由脚本控制 Terminal.app 时，macOS 可能要求自动化权限。

## 四、终端独立运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
'./【MacOS@SourceTree】🫘打开终端运行Pod Install.command' '/path/to/project'
```

独立运行时会先展示内置自述并等待回车确认；按 `Ctrl+C` 可以取消。

## 五、日志与排查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 新终端窗口负责显示 `pod install` 的实时输出和最终退出码。
- 启动脚本日志位于系统临时目录中的 `【MacOS@SourceTree】🫘打开终端运行Pod Install.log`。
- 如果提示找不到 `Podfile`，请检查 Sourcetree 自定义动作参数是否为 `$REPO`。
- 如果提示找不到 `pod`，请先在普通终端中确认 `pod --version` 可执行。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
