# 菜狗桌宠仓库维护约定

- 用户要求每次完成桌宠更新并验证后，同步到本仓库的 GitHub 远端。
- 修改程序、素材或设计参数后，先运行 `tests\test-caigou-dynamic.ps1`。
- 测试通过后运行 `同步到GitHub.ps1 -Message "本次更新摘要"`，完成提交、拉取和推送。
- 不提交 `state.json`、日志、`backup-before-*`、旧版脚本或本机临时文件。
- `启动动态菜狗.vbs` 必须保持 UTF-16LE 编码，否则 Windows Script Host 会报错。
- 不创建桌面快捷方式，不设置开机自启；保留桌面空白处右键启动方式。

