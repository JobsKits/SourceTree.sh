# `【MacOS@SourceTree】同步edgetunnel代码后手动升级.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

校验 [**edgetunnel 官方仓库**](https://github.com/cmliu/edgetunnel)，使用 [**Cloudflare Wrangler**](https://developers.cloudflare.com/workers/wrangler/commands/) 检查登录、配置 KV 绑定并部署 Worker。脚本不拉取或提交 Git 代码，先在 Sourcetree 完成代码同步再执行此动作。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh './【MacOS@SourceTree】同步edgetunnel代码后手动升级.command' '/edgetunnel仓库'
```

终端先展示内置自述并等待回车；`Ctrl+C` 取消。Sourcetree 仓库动作传 `$REPO`，无交互连续执行；没有参数时只有普通可交互终端能提示输入目录，Sourcetree 必须提供目标。只接受一个路径，含空格路径作为一个参数传入；参数按字面路径处理，保留反斜线。仅交互拖入的不存在路径尝试还原转义。

## 二、仓库和工具链 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

任意 remote 必须指向 `cmliu/edgetunnel`，兼容 HTTPS 与 SSH。目标确认后才切换目录，错误路径不回退其它仓库。

终端复用健康 [**Node.js**](https://nodejs.org) / npm 来源，不强制换成 Homebrew；缺失分支才通过已有或安装的 [**Homebrew**](https://brew.sh/) 补齐。brew、Git、Node.js、npm、npx 和实际 Wrangler 都做可执行检查。Sourcetree 只使用已有工具链，不执行安装或升级。

`brew update`、npm 或 Wrangler 升级均回车跳过、输入任意字符后回车执行。项目已声明 Wrangler 时优先本地安装，其次全局安装，终端可安装缺失 Wrangler；缺少 npx 时修复 npm 支撑链并复检。

## 三、登录与授权 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

先执行 `wrangler whoami --json` 检查登录。只有普通交互终端可执行浏览器 OAuth 登录；Sourcetree 即使带 TTY 也不进入交互。`FORCE_WRANGLER_LOGIN=1` 同样只适用于交互终端。非交互登录失败时停止并提示先在终端完成登录，不部署未授权目标。授权行为以 [Wrangler 官方命令说明](https://developers.cloudflare.com/workers/wrangler/commands/general/) 为准。

## 四、KV 绑定和配置 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、读取 KV 命名空间列表，优先核对原 `wrangler.toml` 或上次本地配置的有效 `KV` id。

2、没有有效 id 时按命名空间名称精确查找；JSON 列表解析失败立即停止，正确解析且缺失时才创建，不取用其它命名空间。名称优先 `EDGETUNNEL_KV_NAMESPACE_TITLE`、`EDGETUNNEL_KV_NAMESPACE`、`JOBS_EDGETUNNEL_KV_NAMESPACE`，再读取仓库内 `.edgetunnel-kv-namespace`，否则使用 `JobsGo`。

3、KV id 必须是 32 位十六进制。生成 `.wrangler.jobs.local.toml`，替换其中 `binding = "KV"` 的顶层命名空间表，保留其它配置；原 `wrangler.toml` 不修改。

4、将生成文件加入 Git 本地 `info/exclude`，使用 `wrangler deploy --config .wrangler.jobs.local.toml`。配置生成失败立即停止，不继续使用旧文件部署。

## 五、风险和日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

此动作会部署真实 Worker；缺少命名空间时可能创建 Cloudflare KV。终端安装或升级可能改变用户工具链或项目 Wrangler 依赖；只清理 Wrangler / esbuild 路径的隔离属性，不改其它应用。运行前确认 Cloudflare 账号、仓库和 namespace。

业务日志位于系统临时目录，文件名 `【MacOS@SourceTree】同步edgetunnel代码后手动升级.log`；同目录另有 `.wrangler-whoami.log`、`.kv-list.log` 和 `.kv-create.log` 用于诊断。Sourcetree / 非 TTY / `NO_COLOR` 过滤 ANSI，确认前不写日志。

## 六、常见问题和验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

参数无效时在动作中使用 `$REPO`；登录失败先在终端运行；工具路径存在但版本检查失败时修复对应 shim 或 runtime 后重试。KV 不在当前账号中时重新核对账号与 id，生成配置不改原始 TOML。

已通过 `zsh -n`、入口门禁、非法 KV id 拒绝、命名空间精确匹配、列表解析失败和配置失败阻止部署的隔离测试；未执行真实工具安装、Cloudflare 登录、KV 创建或部署。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
