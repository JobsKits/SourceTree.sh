# 提取器原生Dart离线边界回归

运行 `pwsh -NoProfile -File ./ExtractorNativeOnly.Tests.ps1`。真实校验临时PE文件，进程执行边界使用假返回，所有SDK/网络入口强制失败。覆盖native Dart存在而Flutter stamp缺失时的健康检查和本地提取、原argv/输出/退出码、取消不继续候选，以及此上下文不能用于Flutter/FVM或伪PE。Mac宿主不能执行Windows PE，实际Windows进程运行仍沿用原Common执行器，需目标机器验收。
