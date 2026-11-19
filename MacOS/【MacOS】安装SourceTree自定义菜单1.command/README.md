# Sourcetree 菜单与脚本库同步入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#jobs-toc-heading-2)
- [二、影响和日志](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

保留的独立菜单同步实施入口。先展示用途并确认，再按选择发送脚本库或同步 actions.plist；不能代替日常 Git 推送。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```shell
/bin/zsh "./【MacOS】安装SourceTree自定义菜单1.command"
```

需要现有 macOS、zsh 和系统脚本工具；fzf 健康时复用，确需列表且缺失或损坏时按已确认范围经 Homebrew 补齐。新装 Homebrew 先选择系统/用户目录，仅保存自身 shellenv 配置块。脚本包携带 actions.plist，资源从自身目录解析。菜单同步默认取消，方向键或 Tab 选择后确认；Ctrl+C 停止。选择同步会覆盖目标用户菜单或脚本包模板，写前保留可恢复备份；当前动作标题及未知动作按实际合并逻辑保留。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、影响和日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

日志由终端给出实际位置；共享菜单写入前暂停 Sourcetree，写后验证和重载。取消不会继续同步，失败保留日志及备份；未执行真实安装、覆盖或重启来验证本次目录调整。

[上级目录说明](../README.md)。

用户目录安装Homebrew前先复用健康Git（含自定义来源）；系统Git只是占位器时先查实际CLT工具，缺失才打开一次Apple原生安装窗口并持续复检。许可与密码由本人处理；显式开发目录损坏、只读、非交互或取消时停止，不改全局xcode-select，也不在准备成功前写Homebrew目标。该公共函数的12项隔离场景含10项真实PTY，函数体一致性与每份源码语法分别核对，不代表真实安装已执行。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
