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

- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File test\ai_manual_installer_test.ps1`（覆盖来源/目标重叠时的无改动拒绝、已安装清单文件及旧文件备份内容）
- `node test\ai_global_shortcut_removal_test.js`
- `node test\illustrator_protocol_test.js`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File installer\ai-v3.7.1\build.ps1`（`InstallerCore` 85 项断言；ZIP 11 个文件且不含快捷键辅助程序）

发布产物 SHA-256：

- `SU_AI_PNG_Export_v3.7.1.zip`: `73FF90DCC709AC531C82983525F77D3B3E2C36F5C550B2BC2F08BC895654086E`
- `SU_AI_PNG_Export_v3.7.1_Setup.exe`: `F7065910A7B50D38B66E875A55B6FD0EB7D6843A81CFC7DE489B1216B112E7CC`

Illustrator 2023 原生快捷键、面板焦点及真实导出：**待问题电脑复测**。
