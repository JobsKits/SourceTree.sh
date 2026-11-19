# Git 提交回退隔离回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、运行方式](#jobs-toc-heading-2)
- [二、验证范围](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

使用真实临时 [**Git**](https://git-scm.com/) 仓库验证 [提交回退入口](<../../【MacOS@SourceTree】♻️双击Git（识别子Git） 提交回退.command/README.md>)，不连接网络，不对用户业务仓库执行回退。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本 README 所在目录运行，先阅读自述并回车确认：

```shell
/bin/zsh 【MacOS】CommitReset.Tests.zsh
```

自动回归显式传入 `--run`，也可追加生产脚本路径测试其它副本：

```shell
/bin/zsh 【MacOS】CommitReset.Tests.zsh --run
```

依赖系统 zsh、Git 与基础命令，不安装软件。测试隔离全局／系统 Git 配置，禁止网络协议；临时目录、生产日志和失败证据保留在结尾显示的路径，按 `Ctrl+C` 可取消。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 无 upstream 时的 GitHub／码云同快照、唯一改名远端和 origin 兼容；已配置异名远端／分支、显式引用及失效配置覆盖。
- 缺失引用、remote／merge 部分配置、本地分支 upstream、无候选、其它分支、修订表达式、非祖先、游离 HEAD 和索引锁均安全停止。
- soft 保留索引和配置原始字节、已有暂存／未暂存／未跟踪文件；HEAD 与目标一致时不虚报撤回。
- 真实子模块 `.git` 指针文件寻址，子仓回退不修改父仓 HEAD、索引或配置。
- 多快照不同通过完整 `main` 加 Terminal 启动替身验证分流，选择期间快照变化通过真实解析函数和选择器替身验证停止。

前述交互替身不会打开 Terminal 或执行 fzf；它们不能证明真实菜单点击、终端窗口或键盘操作已验收。其它用例执行生产完整入口和真实 `git reset --soft`，影响仅限本轮临时仓库；测试不会执行 hard 回退。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
