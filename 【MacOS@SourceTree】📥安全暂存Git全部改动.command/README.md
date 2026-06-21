# `【MacOS@SourceTree】📥安全暂存Git全部改动.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

> 这是一个挂载到 [**Sourcetree**](https://www.sourcetreeapp.com/) 的 Git 安全暂存动作，用一次完整索引刷新取代 Sourcetree 对单个路径的分步 `add` / `rm`。

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 暂存已跟踪文件的内容修改或文件名修改。
- 暂存新增文件、删除文件和 Git 识别到的重命名。
- 处理“已跟踪文件变为同名目录”或“同名目录变为文件”。
- 规避 Sourcetree 生成缺少 `-r` 的 `git rm` 后报错：

  ```text
  fatal: not removing 'build_macos.command' recursively without -r
  ```

## 二、执行行为 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

脚本在 Sourcetree 传入的仓库根目录执行：

```shell
git add -A -- .
```

`-A` 会让 Git 统一刷新整个工作树的索引状态，同时处理新增、修改和删除；Git 再根据内容相似度识别重命名。

## 三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 3.1、Sourcetree 自定义动作

1. 在 Sourcetree 中选中目标仓库。
2. 运行自定义动作 `📥安全暂存 Git 全部改动`。
3. 脚本接收 `$REPO` 后自动执行，不在 Sourcetree 非交互环境中停留等待。
4. 回到“文件状态”刷新，核对暂存变更后再提交。

### 3.2、终端双击

- 双击脚本时，脚本会先显示内置自述。
- 按回车后，脚本会尝试处理当前工作目录所在的 Git 仓库。
- 需要指定仓库时，可在终端执行：

  ```shell
  '/Users/jobs/SourceTree.command/【MacOS@SourceTree】📥安全暂存Git全部改动.command/【MacOS@SourceTree】📥安全暂存Git全部改动.command' '/目标/Git仓库'
  ```

## 四、风险说明 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 脚本会修改当前仓库的 Git 索引，将所有未忽略的工作区改动放入暂存区。
- 脚本不会执行 `git commit`、`git push`、`git reset`、`git clean` 或删除工作区文件。
- 脚本不使用 `git add -f`，不会主动强制暂存 `.gitignore` 已忽略的文件。
- 执行后必须在 Sourcetree 中检查暂存区，确认范围无误后再提交。

## 五、日志文件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

运行日志同步保存到：

```text
/tmp/【MacOS@SourceTree】📥安全暂存Git全部改动.log
```

## 六、常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 6.1、是否会直接提交？

不会。脚本只处理暂存区，提交仍由用户在 Sourcetree 中确认后执行。

### 6.2、是否能解决文件与同名目录转换的报错？

能。关键是不再让 Sourcetree 先后对新旧路径执行独立命令，而是让 `git add -A -- .` 一次完整刷新索引。

### 6.3、为什么还需要刷新 Sourcetree？

Git 索引已在外部脚本中修改，Sourcetree 界面可能仍保留旧的文件列表，刷新后即可看到最新暂存状态。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
