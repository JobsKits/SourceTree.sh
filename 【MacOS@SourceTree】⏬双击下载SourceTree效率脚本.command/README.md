# `【MacOS@SourceTree】⏬双击下载SourceTree效率脚本.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

从 [**JobsKits 脚本仓库**](https://github.com/JobsKits/SourceTree.sh) 下载 [**Sourcetree**](https://www.sourcetreeapp.com/) 效率脚本。下载、语法及结构校验完成后才替换运行目录，旧内容完整保存在同级备份。

## 一、执行前检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

运行环境为 [**macOS**](https://www.apple.com/macos/) 与系统 `/bin/zsh`，需要健康 [**Git**](https://git-scm.com/)。不使用 `sudo`；目标运行目录必须是普通目录，符号链接和文件占用会停止。无需 Homebrew，也不改 shell 配置。

## 二、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh './【MacOS@SourceTree】⏬双击下载SourceTree效率脚本.command'
```

终端先展示内置自述并等待回车；`Ctrl+C` 取消。已有运行目录时必须再输入 `YES`，其它输入结束且不改目录。Sourcetree 模式无交互，仅允许目标尚不存在时首次安装；运行目录已存在时报告错误并提示改用终端。

## 三、下载和替换流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、在当前用户家目录建立独立暂存目录，克隆官方仓库；网络失败保留现有运行目录。

2、检查总 `README.md`、各 `.command` 的配套 README 和 `zsh -n` 语法；跳过 Git、第三方及生成目录，仅为下载包中经校验的 `.command` 入口添加用户执行权限。

3、将旧运行目录完整移到带时间戳及随机后缀的同级备份，再写入已校验的新目录；写入失败恢复原目录。

4、仅清理本次生成的暂存目录。下载后不自动执行新脚本；菜单由库内安装入口维护。

## 四、风险和产物 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

目标为当前用户家目录中的 `SourceTree.command`；备份名为 `SourceTree.command.bak.年月日_时分秒.随机后缀`，包含旧脚本、README、隐藏文件及 Git 元数据。新下载内容可能替换尚未推送的自定义代码，只有确认 `YES` 后才替换；通过同级备份恢复旧版本。语法校验不能证明远端脚本业务正确，运行前仍应阅读各自 README。

## 五、日志和常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

日志位于系统临时目录，文件名 `【MacOS@SourceTree】⏬双击下载SourceTree效率脚本.log`，确认前不写入。克隆失败检查网络、Git 和仓库访问；README 或语法缺失时停止替换；目标是符号链接时先使用真实独立目录。

## 六、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

已通过 `zsh -n`；隔离夹具验证下载失败、无效包、已有目录门禁与替换失败保留旧目录。未实际下载并替换用户运行库。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
