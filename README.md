# 菜狗现代桌宠

一个用 PowerShell 和 WPF 编写的 Windows 桌宠。程序直接播放透明 PNG 帧，不需要安装额外运行库，也不会创建桌面快捷方式或设置开机自启。

## 启动

- 双击 `启动动态菜狗.vbs` 静默启动。
- 也可以运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\菜狗现代桌宠.ps1`。
- 如果已经配置桌面右键入口，也可以选择“打开动态菜狗桌宠”。

## 操作

- 点击头部摸头，点击身体陪玩，拖动可以改变位置。
- 鼠标悬停会展开生活面板；移开后自动收起。
- 面板可以喂食、陪玩、切换跟随、调整大小、启用安静模式或让菜狗休息。
- 跟随模式会持续追随鼠标，停止后菜狗自行回到右下角。

## 状态与作息

生命、饱食、体力和亲密度会保存到本地 `state.json`。饱食缓慢下降，安静和睡眠会恢复体力；长期饥饿会损失生命，持续忽视或越界互动会降低亲密度。存档、日志和本机备份不会提交到仓库。

无人操作时，菜狗会在睡眠、安静清醒和短暂活跃之间切换。主动问候至少间隔数十分钟，安静模式则只响应直接互动。

## 仓库结构

- `菜狗现代桌宠.ps1`：主程序。
- `启动动态菜狗.vbs`：UTF-16LE 静默启动器。
- `assets-hq`：动画帧与清单。
- `design-tokens.json`：界面尺寸和配色。
- `tests\test-caigou-dynamic.ps1`：资源与行为自检。
- `同步到GitHub.ps1`：测试、提交并推送当前更新。

## 验证

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\test-caigou-dynamic.ps1
```

通过时输出 `CAIGOU_DYNAMIC_TEST_OK`。

## 下载

- [公开源码](https://github.com/fanqiye/caigou-desktop-pet)
- [最新运行包](https://github.com/fanqiye/caigou-desktop-pet/releases/latest)

运行包由 GitHub Actions 在 `main` 分支测试通过后生成。
