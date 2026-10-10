# `【MacOS@SourceTree】⚙️运行授权.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

为明确选定的 `.command` 普通文件添加用户执行权限，并移除该文件已有的隔离属性。用于 [**Sourcetree**](https://www.sourcetreeapp.com/) 菜单入口授权，不修改 Git 或安装工具链。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh './【MacOS@SourceTree】⚙️运行授权.command' '/目标目录'
/bin/zsh './【MacOS@SourceTree】⚙️运行授权.command' '/目标脚本.command' '/另一个目录'
RECURSIVE=1 /bin/zsh './【MacOS@SourceTree】⚙️运行授权.command' '/脚本库目录'
```

无参数时使用环境 `REPO`，否则使用脚本库根目录。文件参数直接授权，不会丢掉第一个文件。带空格路径必须作为一个参数传入；拖入路径去除外围引号与末尾 CRLF 换行。

## 二、交互和范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

终端展示内置自述，回车继续、`Ctrl+C` 取消；明确识别为 Sourcetree 后无交互执行，非 Sourcetree 且没有可交互输入时退出。

默认只扫描目标目录第一层；`RECURSIVE=1` 才递归。递归跳过 `.git`、`node_modules`、`Pods`、`.dart_tool`、`build`、`DerivedData`；不跟随目录符号链接。多个目标去重处理。递归先把 NUL 分隔列表保存到本次独立临时文件，确认 `find` 完整成功后才收集目标；枚举失败时停止，不按已输出的部分路径授权，临时列表随该枚举流程结束清理。

## 三、实际命令 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

仅执行目标文件的 `chmod u+x`；检测到 `com.apple.quarantine` 后执行单文件 `xattr -d`，不对目录执行递归授权或递归移除属性。已可执行入口幂等处理。文件不存在、符号链接、非 `.command` 文件均停止，不静默换成其它路径。

## 四、结果和日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

每个入口输出成功或失败，最后汇总总数、成功数、失败数；任何失败最终返回非零。空目录返回成功并报告零操作。日志位于系统临时目录，文件名 `【MacOS@SourceTree】⚙️运行授权.log`；确认前不写日志。

## 五、风险和常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

授权只改变执行位，不证明脚本可信。只选择自有脚本范围；移除隔离属性会改变 Gatekeeper 提示，执行前先检查内容。权限失败检查目标所有者和写入权限，不使用全目录 `chmod -R`。

## 六、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

已通过 `zsh -n`，使用临时目录验证多个含中文/空格路径、第一参数为文件、递归排除、重复目标去重、CRLF 拖入路径及失败退出，并用假 `find` 验证输出部分列表后失败时不执行授权、临时列表完成清理。未对真实项目批量授权。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
