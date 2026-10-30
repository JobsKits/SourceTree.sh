# <span id="前言">Flutter 标准运行器资源</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、文件与入口](#jobs-toc-heading-1)
- [二、操作与边界](#jobs-toc-heading-2)

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
/bin/zsh ./RunFlutterProject.zsh --project "<Flutter 工程目录>"
```

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">二、操作与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

先展示内置自述，回车继续，非空或 `Ctrl+C` 取消。设备选择、已有模拟器启动及缺失时的型号 / 系统镜像初始化均在独立终端中处理；下载和创建前确认，取消不继续业务。项目 SDK 缺失时沿原 FVM 流程确认，不静默切换全局 SDK。

运行后 `r` 热重载、`R` 热重启、`d` 离开日志、`s` 停止，均需回车。关闭终端仅离开日志，后台任务继续；操作日志、持久会话和模拟器日志的位置均由运行器打印。完整工具依赖、创建副作用、失败与验证边界见 [动作说明](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
