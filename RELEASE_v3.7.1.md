# SU+AI PNG Export v3.7.1

## 变更

- 移除全局快捷键设置、低级键盘钩子辅助程序和相关后台轮询。
- PNG、轮廓导出以及与 SketchUp v3.7 的 schema-v2 协议保持不变。

## 原因

v3.7 在空快捷键配置下可能错误拦截 Ctrl、Shift、Alt 等未绑定按键。

## 升级与备份

安装器会停用旧快捷键宿主，并把旧扩展备份到 `%APPDATA%\SU_AI_PNG_Export\backups\`。
安装器不会强制关闭或重启 Illustrator。

## 回滚

关闭 AI 面板后卸载 v3.7.1，再运行保留的 v3.7 安装包或恢复备份。回滚会恢复旧快捷键功能及其已知风险。

## 验证状态

以下自动测试已通过：

- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File test\ai_manual_installer_test.ps1`
- `node test\ai_global_shortcut_removal_test.js`
- `node test\illustrator_protocol_test.js`

Illustrator 2023 原生快捷键、面板焦点及真实导出：**待问题电脑复测**。
