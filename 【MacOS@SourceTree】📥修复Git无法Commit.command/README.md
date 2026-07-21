# `【MacOS@SourceTree】📥修复Git无法Commit.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

> 这是一个挂载到 [**Sourcetree**](https://www.sourcetreeapp.com/) 的 Git Commit 修复动作。它会先处理 `.gitmodules` 的安全暂存，再检查子模块，并用一次完整索引刷新取代 Sourcetree 对单个路径的分步 `add` / `rm`。

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 暂存已跟踪文件的内容修改或文件名修改。
- 暂存新增文件、删除文件和 Git 识别到的重命名。
- 处理“已跟踪文件变为同名目录”或“同名目录变为文件”。
- 恢复“父仓登记了 gitlink，但子模块工作树缺失”的半初始化状态。
- 处理子模块目录改名，例如 `SourceTree.sh` 迁移为 `SourceTree.command`。
- 识别目录改名后 `.git` 文件仍指向旧子模块元数据、`core.worktree` 与当前路径不一致的问题。
- 自动收口“旧 gitlink 已登记、旧目录已不存在、新目录仍指向原 gitdir”的未完成迁移，同时更新 `.gitmodules`、`core.worktree` 和父仓索引。
- 修复已登记到 `.gitmodules` 的同源子模块副本仍借用旧路径 gitdir 的问题，例如 `JobsSh.sh` 误指向 `.git/modules/JobsSh`。
- 阻止 Sourcetree 把错位副本误显示为 `HEAD`，或在错位路径执行 `git submodule update --init` 后报错。
- 规避 Git 在删除旧 gitlink 时报错 `please stage your changes to .gitmodules or stash them to proceed`。
- 处理 Sourcetree 执行 `git rm -q -f -- JobsMockTool` 这类旧子模块删除命令时，因为 `.gitmodules` 尚未暂存导致 Commit 中断的问题。
- 阻止 Sourcetree 把缺失子模块误暂存为删除，或在子模块内部有真实修改时继续提交。
- 规避 Sourcetree 生成缺少 `-r` 的 `git rm` 后报错：

  ```text
  fatal: not removing 'build_macos.command' recursively without -r
  ```

## 二、执行行为 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

脚本会先检查 `.gitmodules` 是否有工作区变更；如果有，会优先执行：

```shell
git add -A -- .gitmodules
```

这一步用于满足 [**Git**](https://git-scm.com/) 对子模块配置和 gitlink 删除顺序的安全要求，避免 Sourcetree 先执行 `git rm -q -f -- 旧子模块` 时被拒绝。

`.gitmodules` 会在 `.git/core.worktree` 错位目录预检之前写入索引；即使后续因为错位工作树、脏子模块等安全问题中止，Sourcetree 也不应再卡在 `please stage your changes to .gitmodules or stash them to proceed` 这一层。

随后脚本从父仓索引中收集模式为 `160000` 的 gitlink，逐个检查子模块：

1. 子模块工作树存在且 clean：允许继续。
2. 子模块工作树缺失，或只留下空目录：按 `.gitmodules` 尝试 `git submodule update --init --recursive`。
3. 父仓锁定提交已被远端历史重写移除：只对本轮新克隆的子模块收口工作树，保留当前有效 `HEAD`。
4. 传入路径存在 `.git/core.worktree` 错位：旧路径仍存在时，将当前路径转换为独立 Git 工作树；旧路径已不存在时，直接修正 `core.worktree`。
5. 旧路径仍是父仓索引 gitlink、旧目录已不存在，而新目录继续指向原 gitdir：核对 `.gitmodules` URL 与 gitdir remote 一致后，自动更新 `.gitmodules` 路径、`core.worktree` 和父仓新旧 gitlink。
6. 仓库内部其它嵌套目录存在 `.git/core.worktree` 错位：如果该路径已登记到当前 `.gitmodules`，且 URL 与借用的旧 gitdir remote 一致，则复制一份独立 gitdir 给新路径；否则只诊断并中止。
7. 同一 `.gitmodules` section 的路径发生迁移：先安全修正 `.git/modules` 中的 `core.worktree`，再检查新路径是否为 clean 的有效子模块。
8. 旧 gitlink 已经从当前 `.gitmodules` 移除，且路径不存在或只是空目录：允许后续 `git add -A -- .` 暂存删除。
9. 子模块已存在且有内部修改：列出状态并保持原状，继续刷新父仓索引；不丢弃、不暂存、不提交子模块内部内容。

完成 `.gitmodules` 安全暂存和子模块预检后，脚本会在 Sourcetree 传入的仓库根目录执行：

```shell
git add -A -- .
```

`-A` 会让 Git 统一刷新整个工作树的索引状态，同时处理新增、修改和删除；Git 再根据内容相似度识别重命名。子模块未通过预检时，这条命令不会执行。

## 三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 3.1、Sourcetree 自定义动作

1. 在 Sourcetree 中选中目标仓库。
2. 运行自定义动作 `📥修复Git无法Commit`。
3. 脚本接收 `$REPO` 后自动执行，不在 Sourcetree 非交互环境中停留等待。
4. 回到“文件状态”刷新，核对暂存变更后再提交。

### 3.2、终端双击

- 双击脚本时，脚本会先显示内置自述。
- 按回车后，脚本会尝试处理当前工作目录所在的 Git 仓库。
- 需要指定仓库时，可在终端执行：

  ```shell
  '~/SourceTree.command/【MacOS@SourceTree】📥修复Git无法Commit.command/【MacOS@SourceTree】📥修复Git无法Commit.command' '/目标/Git仓库'
  ```

## 四、风险说明 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 脚本会修改当前仓库的 Git 索引，将所有未忽略的工作区改动放入暂存区。
- 缺失子模块时，脚本会访问 `.gitmodules` 中的远端并初始化工作树。
- 父仓锁定提交已从远端历史消失时，脚本可将父仓 gitlink 暂存为新克隆子模块的当前有效 `HEAD`；提交前必须核对这个版本变化。
- `.gitmodules` 发生变化时，脚本会在全量暂存前先将它写入索引，避免 Git 拒绝删除或迁移旧 gitlink。
- 直接移动子模块目录时，脚本可修正父仓 `.git/modules` 内部配置的 `core.worktree`；不会修改子模块的提交历史。
- 旧 gitlink 已在索引中、子模块目录却在暂存前直接改名时，脚本会在 URL 同源且旧路径不存在的前提下自动同步 `.gitmodules`、`core.worktree` 与新旧 gitlink；不会重写子模块提交历史。
- 已登记到 `.gitmodules` 的同源子模块副本如果还借用旧路径 gitdir，脚本会复制旧 gitdir 到新路径对应的 `.git/modules/<新路径>`，并把副本目录的 `.git` 指针切到新 gitdir。
- 如果 Sourcetree 当前选中的目录误借用了另一个目录的 gitdir，脚本会复制一份 Git 元数据到当前目录，并把旧 `.git` 指针文件保存到新 `.git` 目录内。
- 如果错位目录不是当前传入路径，脚本只报告错位目录与真实目录，不会擅自删除、覆盖或重新绑定未选中的目录。
- 已存在子模块中的未提交内容不会被清理或暂存；脚本会列出状态并继续刷新父仓索引，父仓提交不会包含这些子模块工作区内容。
- 脚本不会执行 `git commit`、`git push`、`git reset`、`git clean` 或删除工作区文件。
- 脚本不使用 `git add -f`，不会主动强制暂存 `.gitignore` 已忽略的文件。
- 执行后必须在 Sourcetree 中检查暂存区，确认范围无误后再提交。

## 五、日志文件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

运行日志同步保存到：

```text
$TMPDIR/【MacOS@SourceTree】📥修复Git无法Commit.log
```

## 六、常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 6.1、是否会直接提交？

不会。脚本只处理暂存区，提交仍由用户在 Sourcetree 中确认后执行。

### 6.2、是否能解决文件与同名目录转换的报错？

能。关键是不再让 Sourcetree 先后对新旧路径执行独立命令，而是让 `git add -A -- .` 一次完整刷新索引。

### 6.3、为什么还需要刷新 Sourcetree？

Git 索引已在外部脚本中修改，Sourcetree 界面可能仍保留旧的文件列表，刷新后即可看到最新暂存状态。

### 6.4、为什么 Sourcetree 显示“未提交的子模块”，点进去却没有可提交文件？

这不一定是子模块内部有修改。常见原因是父仓索引仍登记 gitlink，但子模块工作树没有初始化、被移除，或父仓锁定的提交已被远端历史重写删除。Sourcetree 把这些父仓级异常包装成子模块提交弹窗，但子模块本身又没有可用工作树，因此会进入无法继续的界面。

### 6.5、子模块里确实有未提交修改怎么办？

脚本会列出子模块内部状态并保持这些内容原样，然后继续执行父仓 `git add -A -- .`。父仓提交不会包含子模块工作区里的未提交内容；请进入对应子模块，根据修改性质单独提交、暂存或手工恢复。

### 6.6、为什么子模块改名时必须先暂存 `.gitmodules`？

Git 要求子模块路径配置与 gitlink 删除保持一致。如果 Sourcetree 先执行 `git rm SourceTree.sh` 或 `git rm -q -f -- JobsMockTool`，但 `.gitmodules` 中的新路径或删除记录还没有写入索引，Git 会主动拒绝操作。脚本先暂存 `.gitmodules`，然后再由 `git add -A -- .` 同步旧 gitlink 删除和新 gitlink 添加。

### 6.7、为什么 Sourcetree 列表显示 `HEAD`，窗口里面却显示 `main`？

常见原因是当前 Sourcetree 书签指向了一个错位目录：该目录下的 `.git` 文件指向某个子模块的 gitdir，但 gitdir 里的 `core.worktree` 仍指向另一个真实目录。脚本会识别这种特征；如果这个错位目录就是当前传入路径，会将它转换成独立 Git 工作树，之后 Sourcetree 自己执行 `checkout main` 和 `submodule update --init` 也能正常通过。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
