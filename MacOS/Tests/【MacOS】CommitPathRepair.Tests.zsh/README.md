# `CommitPathRepair.Tests.zsh`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、执行方式](#usage)
- [二、覆盖内容](#coverage)
- [三、结果与边界](#evidence)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> 使用临时 [**Git**](https://git-scm.com/) 仓库验证 Commit 修复动作的旧路径处理及索引保护边界，执行完整生产入口，不访问真实业务仓库或网络。

## 一、<span id="usage">执行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 在本 README 同级目录运行，系统使用 `/bin/zsh`、`git` 与原生文件工具：

  ```shell
  /bin/zsh 【MacOS】CommitPathRepair.Tests.zsh
  ```

- 先显示隔离范围，回车开始、`Ctrl+C` 取消；自动回归显式使用 `--run`，可在其后传入另一份待测脚本的实际路径：

  ```shell
  /bin/zsh 【MacOS】CommitPathRepair.Tests.zsh --run
  /bin/zsh 【MacOS】CommitPathRepair.Tests.zsh --run '/目标目录/【MacOS@SourceTree】📥修复Git无法Commit.command'
  ```

- 默认按测试脚本位置定位同一 `MacOS/` 下的生产脚本，不依赖启动工作目录。测试仅向生产子进程注入 `SOURCETREE=1` 模拟 [**Sourcetree**](https://www.sourcetreeapp.com/) 无交互入口，主要调用 `[仓库路径] --repair-paths`，另覆盖默认自动识别模式。

## 二、<span id="coverage">覆盖内容</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 文件变同名目录、普通已跟踪文件删除、旧路径已从索引移除及重复执行。
- 新目录子文件已有部分暂存、无关部分暂存、删除候选自身已有暂存内容与未跟踪文件保持。
- 精确中文脚本名先 `git add -f` 两个子项、再 `git rm -q -f` 同名旧路径，确认报 `without -r` 且未改索引；默认／显式精确入口均明确诊断已暂存替换，逐字节保留索引、已有部分暂存和工作区。相似前缀的其它目录不误报。
- 纯 `git add -N` 子项不报告内容已暂存；与实际已暂存子项混合时只统计后者，保留意图添加标志和真实索引字节。
- 中文、空格、通配字符、前导短横线、制表符和换行路径按字面值处理。
- 原符号链接、祖先符号链接、父目录变文件、`skip-worktree` / `assume-unchanged` 与缺失 gitlink 保留。
- 精确与 `--stage-all` 完整模式都拒绝未解决冲突，已有索引锁和未知参数保持失败状态；拒绝分支比较真实索引字节，检查 Sourcetree 输出没有 ANSI 残留。
- 原索引备份逐字节一致，HEAD 与 Git 配置保持；默认自动识别文件变目录、已暂存普通文档迁移与已暂存删除，保留已有部分暂存和未跟踪文件；linked worktree 使用自身索引并保持主工作树索引不变。
- 显式 `--stage-all` 模式继续暂存全部新增、修改和删除，但不创建提交。

## 三、<span id="evidence">结果与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 临时目录名为 `$TMPDIR/jobs-commit-path-tests.*`，每例保留 `result.log`、生产入口的 `subject.log`、执行前索引及真实夹具；测试结束不自动删除证据。
- 每例显示 `PASS` 或 `FAIL`；任一失败最终退出码非零。索引锁、冲突等预期失败会核对具体状态或诊断，不能只因任意异常就算通过。
- 全部提交及分支只在临时仓库创建；Git 全局、系统配置与身份已隔离，传输协议只允许 `file`，不运行真实业务提交、推送、依赖安装或构建。
- 这些结果证明脚本与 Git 索引的隔离行为；真实 Sourcetree 界面刷新及业务仓库最终提交需独立验证。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
