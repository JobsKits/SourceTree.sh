# Windows 动作内部实现

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

`SourceTree.psm1` 分发 27 项业务；`Features/` 携带四套既有 Windows Flutter 模块（体检、生成、依赖收集和打包），由本仓独立日志适配。原模块来源为本工作区 `OS@Extension/WindowsOS@Extension`，只复制 Jobs 自维护源码，后续在此独立携带。

原生命令执行期间使用 UTF-8，避免系统 OEM 代码页损坏中文 Git 路径；命令成功或失败后恢复调用前的终端与管道编码，不持久修改控制台配置。对应夹具见[测试说明](../Tests/README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

见 [Windows 总览](../README.md) 的功能对照与运行命令。业务日志在系统临时目录；不直接运行内部模块作为用户入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
