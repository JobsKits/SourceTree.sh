# 【WindowsOS@SourceTree】🌍打开远程仓库地址

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与选择](#jobs-toc-heading-2)
- [二、地址转换与边界](#jobs-toc-heading-3)
- [三、依赖、日志与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> 用默认浏览器打开所选 [**Git**](https://git-scm.com/) 远程仓库网页。与[获取远程仓库地址](../【WindowsOS@SourceTree】🌐获取远程仓库地址/README.md)共用候选、去重和依赖检查，使用 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1+。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与选择 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击本目录 `.cmd`，或从终端传入目标：

```powershell
.\Run.ps1 -Target 'D:\Projects\My Project'
```

- 终端先显示内置自述并等待回车；`Ctrl+C` 取消。枚举全部 remote 的 fetch / push URL，按原始 URL 去重，无远程时停止。
- [**Sourcetree**](https://www.sourcetreeapp.com/) 菜单传 `-SourceTree -Target "$REPO"`。只有一个去重地址时直接打开；多个地址或 Git 不可用时才转独立终端，回车确认后使用 [**fzf**](https://github.com/junegunn/fzf) 单选。回车选择，`Esc` / `Ctrl+C` 取消；空选或失败不打开任何页面。
- 完整携带 `WindowsOS/`，不单独复制 `Run.ps1`；共享逻辑在[公共模块](../Scripts/README.md)。`-Option` / `-Value` 为兼容保留，不参与本动作。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、地址转换与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| Git 地址示例 | 打开网页 |
| --- | --- |
| `https://host.example:8443/team/repo.git` | `https://host.example:8443/team/repo` |
| `http://host.example:8080/team/repo.git` | `http://host.example:8080/team/repo` |
| `git@host.example:team/repo.git` | `https://host.example/team/repo` |
| `ssh://git@host.example:22/team/repo.git` | `https://host.example/team/repo` |
| `git://host.example:9418/team/repo.git` | `https://host.example/team/repo` |

- 表中域名是未部署示例，只验证离线地址转换。保留多层 namespace 与 HTTP(S) 显式端口；去掉末尾 `.git`、认证信息、查询串和片段，不把私密参数传给浏览器。
- 非标准 SSH / Git 端口无法证明对应网页端口，停止并提示使用明确的 HTTP(S) remote。SSH Host 别名和自建服务网页路由不自动映射，需配置服务实际网页对应的地址。
- 本地路径、`file://`、危险或其它协议、控制字符地址不打开。浏览器启动失败返回非零；本动作不验证网页在线性，不执行 Git 网络传输，不修改远程配置、工作区或索引，不提交、不推送。
- 状态、日志与选择面板显示脱敏 URL。要复制原始地址使用配对的获取动作。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 健康 Git 复用；单地址不要求 fzf。多地址检查 fzf 路径、版本及实际所需选项，不引入健康路径不需要的包管理器。
- 缺失或损坏时在独立终端检查 [**WinGet**](https://learn.microsoft.com/windows/package-manager/winget/) 的版本与 `--info`。回车允许官方 `winget` 源以 `--scope user` 安装/修复 `Git.Git` / `junegunn.fzf` 一次，任意字符取消；刷新当前进程 PATH 后复检，失败停止。WinGet / App Installer 缺失给官方修复入口，不自动安装包管理器、不主动提权、不全局升级。
- 日志在系统临时目录 `JobsSourceTree-remote-open-*.log`；终端转交只携带入口与仓库路径，重新读取 Git 配置，不将 URL 拼入执行命令。Sourcetree 参数缺失直接停止；继承的 Git 仓库寻址变量与 fzf 默认绑定只在本流程隔离，结束后恢复。
- [隔离测试](../Tests/README.md)覆盖候选枚举、转换、单/多地址分流、取消及依赖失败；本机未实际运行 Windows 菜单、剪贴板、浏览器启动或真实依赖安装。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
