# `【MacOS@SourceTree】同步edgetunnel代码后手动升级.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、运行方式](#jobs-toc-heading-2)
- [二、仓库和工具链](#jobs-toc-heading-3)
- [三、登录与授权](#jobs-toc-heading-4)
- [四、KV 绑定和配置](#jobs-toc-heading-5)
- [五、风险和日志](#jobs-toc-heading-6)
- [六、常见问题和验证](#jobs-toc-heading-7)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

校验 [**edgetunnel 官方仓库**](https://github.com/cmliu/edgetunnel)，使用 [**Cloudflare Wrangler**](https://developers.cloudflare.com/workers/wrangler/commands/) 检查登录、配置 KV 绑定并部署 Worker。脚本不拉取或提交 Git 代码，先在 Sourcetree 完成代码同步再执行此动作。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```shell
/bin/zsh './【MacOS@SourceTree】同步edgetunnel代码后手动升级.command' '/edgetunnel仓库'
```

终端先展示内置自述并等待回车；`Ctrl+C` 取消。Sourcetree 仓库动作传 `$REPO`，无交互连续执行；没有参数时只有普通可交互终端能提示输入目录，Sourcetree 必须提供目标。只接受一个路径，含空格路径作为一个参数传入；参数按字面路径处理，保留反斜线。仅交互拖入的不存在路径尝试还原转义。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、仓库和工具链 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

任意 remote 必须指向 `cmliu/edgetunnel`，兼容 HTTPS 与 SSH。目标确认后才切换目录，错误路径不回退其它仓库。

终端复用健康 [**Node.js**](https://nodejs.org) / npm 来源，不强制换成 Homebrew；缺失分支才通过已有或安装的 [**Homebrew**](https://brew.sh/) 补齐。brew、Git、Node.js、npm、npx 和实际 Wrangler 都做可执行检查。Sourcetree 复验现有工具链；缺失或损坏时将原目标、参数和工作目录按数据转交独立终端准备，原动作到此停止，不继续授权、KV或部署。取消码直接传递，不当作工具缺失反复修复。

`brew update`、npm 或 Wrangler 升级均回车跳过、输入任意字符后回车执行。项目已声明 Wrangler 时优先现存本地入口并复验；损坏本地依赖不回退全局或隐式下载其它版本。缺少本地入口时只按现有 npm 锁文件准备；没有可依据的锁文件则停止并说明。未声明 Wrangler 时保留全局安装后备，缺少 npx 时修复 npm 支撑链并复检。已选获取的网络失败留在当前流程重试；权限、许可、版本或磁盘阻塞立即停止。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、登录与授权 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

先执行 `wrangler whoami --json` 检查登录。只有普通交互终端可执行浏览器 OAuth 登录；Sourcetree 即使带 TTY 也不进入交互。`FORCE_WRANGLER_LOGIN=1` 同样只适用于交互终端。非交互登录失败时停止并提示先在终端完成登录，不部署未授权目标。授权行为以 [Wrangler 官方命令说明](https://developers.cloudflare.com/workers/wrangler/commands/general/) 为准。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、KV 绑定和配置 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、读取 KV 命名空间列表，优先核对原 `wrangler.toml` 或上次本地配置的有效 `KV` id。

2、没有有效 id 时按命名空间名称精确查找；JSON 列表解析失败立即停止，正确解析且缺失时才创建，不取用其它命名空间。名称优先 `EDGETUNNEL_KV_NAMESPACE_TITLE`、`EDGETUNNEL_KV_NAMESPACE`、`JOBS_EDGETUNNEL_KV_NAMESPACE`，再读取仓库内 `.edgetunnel-kv-namespace`，否则使用 `JobsGo`。

3、KV id 必须是 32 位十六进制。生成 `.wrangler.jobs.local.toml`，替换其中 `binding = "KV"` 的顶层命名空间表，保留其它配置；原 `wrangler.toml` 不修改。

4、将生成文件加入 Git 本地 `info/exclude`，使用 `wrangler deploy --config .wrangler.jobs.local.toml`。配置生成失败立即停止，不继续使用旧文件部署。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、风险和日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

此动作会部署真实 Worker；缺少命名空间时可能创建 Cloudflare KV。终端安装或升级可能改变用户工具链或项目 Wrangler 依赖；保留系统隔离属性和原生许可，执行受阻时说明原因，由本人使用系统设置处理。运行前确认 Cloudflare 账号、仓库和 namespace。

业务日志位于每次独立创建的系统临时目录 `JobsEdgeTunnel.*`，文件名 `【MacOS@SourceTree】同步edgetunnel代码后手动升级.log`；同目录另有 `.wrangler-whoami.log`、`.kv-list.log` 和 `.kv-create.log` 用于诊断。协议响应文件保留原始字节；展示和主日志去除 ANSI，支持样式的终端中 URL 绿色下划线。确认前不写日志，日志创建或写入失败停止；并发运行不覆盖另一轮日志。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">六、常见问题和验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

参数无效时在动作中使用 `$REPO`；登录失败先在终端运行；工具路径存在但版本检查失败时修复对应 shim 或 runtime 后重试。KV 不在当前账号中时重新核对账号与 id，生成配置不改原始 TOML。

已通过 `zsh -n`、入口门禁、非法 KV id 拒绝、命名空间精确匹配、列表解析失败和配置失败阻止部署的隔离测试；本轮另通过 27 个实际函数隔离场景（含 3 个真实 PTY）：目标先校验、健康工具复用、原生取消码、转交后不续行、项目 Wrangler 选择、入口 EOF／文字取消及私有日志失败关闭。另4个真实私有命令场景核对原始协议响应字节保全及主日志无ANSI；工具和 Cloudflare 边界使用私有替身；未执行真实工具安装、Cloudflare 登录、KV 创建或部署。

[**Homebrew**](https://brew.sh/) 安装路径由用户选择：已有可运行安装时复用；确实需要安装时先强提示，只有精确输入大写 `YES` 才选择系统标准目录，其它输入或直接回车选择当前用户的 `.local/homebrew`。`YES` 只表示选择路径，权限与密码由官方安装器实际处理；有管理员权限也可以选用户目录。选定路径失败立即停止，不自动切换；`Ctrl+C` / 输入结束取消整个任务。

Sourcetree 动作不能交互时，必要工具准备转交终端，由原生安装器处理许可、密码及安装路径；当前动作不声称部署成功。仅刷新本次进程的工具路径，不写 Shell 启动配置。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

用户目录安装Homebrew前先复用健康Git（含自定义来源）；系统Git只是占位器时先查实际CLT工具，缺失才打开一次Apple原生安装窗口并持续复检。许可与密码由本人处理；显式开发目录损坏、只读、非交互或取消时停止，不改全局xcode-select，也不在准备成功前写Homebrew目标。该公共函数的12项隔离场景含10项真实PTY，函数体一致性与每份源码语法分别核对，不代表真实安装已执行。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
