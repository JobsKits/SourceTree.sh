# <span id="前言">Flutter 标准运行器资源</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、文件与入口](#jobs-toc-heading-1)
- [二、操作与边界](#jobs-toc-heading-2)
  - [SDK获取前网络检测](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

本目录是 [Sourcetree 运行入口](../README.md) 的标准回退资源，完整动作目录可独立复制。保留工程 `setup.command` 优先；没有工程脚本时，由上层入口相对定位这里的运行器，不读取其它仓库或已安装的扩展。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、文件与入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| `RunFlutterProject.zsh` | 校验 [**Flutter**](https://flutter.dev/) 工程与 SDK，选择设备，初始化 / 启动 iOS、Android 模拟器，后台运行及日志控制。 |
| `FlutterRunner.jxa` | 结构化解析设备 / 模拟器数据、校验工程、生成后台作业配置及显示运行日志。 |

从本目录独立运行：

```shell
/bin/zsh 【MacOS】RunFlutterProject.zsh/【MacOS】RunFlutterProject.zsh --project "<Flutter 工程目录>"
```

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">二、操作与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

先展示内置自述，回车继续，非空或 `Ctrl+C` 取消。设备选择、已有模拟器启动及缺失时的型号 / 系统镜像初始化均在独立终端中处理；下载和创建前确认，取消不继续业务。项目 SDK 缺失时沿原 FVM 流程确认，不静默切换全局 SDK。

设备枚举前先检查所选 SDK 的公共缓存；完整本地 stamp、组件目录及工具依赖均就绪时直接复用，不新增联网前提。否则先执行 `flutter precache --universal`，沿用本次网络选路、真实进度和持续重试，单次窗口为 1800 秒，直到就绪或 `Ctrl+C` 结束；这一步不下载所有目标平台。输出保存到 `<操作日志>.discovery-sdk`；每次尝试结束后，将输出和退出码追加到 `<操作日志>.discovery-sdk.attempts.log`，中断时保留当次日志。公共组件完成后才运行短时 `flutter devices --machine`，避免机器模式下的隐式下载被设备查询超时反复中止。

运行后 `r` 热重载、`R` 热重启、`d` 离开日志、`s` 停止，均需回车。关闭终端仅离开日志，后台任务继续；操作日志、持久会话和模拟器日志的位置均由运行器打印。完整工具依赖、创建副作用、失败与验证边界见 [动作说明](../README.md)。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>


### <span id="jobs-toc-heading-3" data-jobs-toc="v2">SDK获取前网络检测</span><!-- jobs-toc:heading-end -->

Flutter SDK 源码、Dart 首次补齐、设备发现公共组件及目标平台制品获取前，先以目标版本/engine/架构的小Range正文核对来源与现有网络路线；显式源和代理（包含空值）保留。AUTO只在获准的官方/CFUG等价公开对象及当前已配置网络中选择，配置仅传当前SDK子进程，不持久修改Shell、Git或系统代理。健康本地Dart缓存可直接复用；获取失败自动使路线缓存失效并持续退避重测，Ctrl+C结束。构建、运行及项目依赖业务不因SDK网络错误被整段重放。
