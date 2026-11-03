# 构建输出：必须同时看 OK 与 error

> 来源：2026-10-19 夜。改 `main.c` 时把 `if (0 && ...)` 误改成 `if (1(0 && ...)`（语法错误），
> 然后用 `Select-String -Pattern 'OK:'` 过滤构建输出——**只过滤了自己想看的成功标志**，
> 构建其实失败了，脚本照样往下走，把**上一次的旧 bin** 下载到板上。
> 结果是：后面连续两轮读数"没变化"，而我据此判断"CNN 计数器是垃圾 / 加速器不可用"。
> 真相直到我回头去看构建日志才出现。

## 规则

**任何"改代码 → 构建 → 上板"的链条，判据必须是"构建成功"，而不是"没看到失败"。**

```powershell
$log = powershell -ExecutionPolicy Bypass -File ps_ui\build.ps1 2>&1
$ok  = ($log | Select-String -Pattern 'OK:').Count
$err = ($log | Select-String -Pattern 'error:|FAILED').Count
Write-Host "OK lines=$ok  error lines=$err"
if ($ok -lt 1 -or $err -gt 0) { throw "build did not succeed -- do not download" }
```

## 为什么容易犯

1. 构建脚本"成功时打印 OK"，**失败时也可能打印其他东西**；只 grep OK 等于只问"你想让我过吗"；
2. PowerShell 的 `Select-String` 过滤会**把错误行一起过滤掉**，屏幕上看起来干干净净；
3. 构建失败时 `build.ps1` 的退出码在管道里可能被 `Select-Object` 吞掉，
   `$LASTEXITCODE` 也不一定是你以为的那个。

## 上板前的三个必查

- [ ] 构建日志里 **OK 行 ≥ 1**，且 **error 行 = 0**；
- [ ] 产物的**时间戳是刚才**（`Get-Item ps_ui\ps_ui.bin` 的 `LastWriteTime`）；
- [ ] 下载脚本打印的**字节数**与刚构建的一致。

**第二条最容易被忽略**：构建失败时旧 bin 仍在，下载"成功"，一切看起来正常。

## 一句话

**"没有错误"和"构建成功"是两件事。** 判据要写成前者还是后者，取决于你 grep 的是哪一行。
