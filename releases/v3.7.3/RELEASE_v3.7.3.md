# SU+AI 同步 v3.7.3

## 成品与 SHA-256

| 成品 | SHA-256 |
| --- | --- |
| `AI同步导入SU_2026_v3.7.3.rbz` | `29B7F4285E7AEDE87F6FA92D158D4E6FBD90E78BD5ABAF30E81EA9155F855529` |
| `SU_AI_PNG_Export_v3.7.3.zip` | `BDF3DB283BAF72750A696CB4827D84E6FF576BF45B90C1D04C2C543AFA55DF91` |
| `SU_AI_PNG_Export_v3.7.3_Setup.exe` | `15487765D52E78043F231E28589AC22538B0601D6561F28108AC22F8FEE8C0D9` |

## 更新

- AI 端不再在启动时创建桌面的 `ai-export`；首次点击导出且未自定义路径时才创建。
- 默认配置写入用户数据目录，保留旧桌面配置的读取兼容。
- 包含 v3.7.3 已有的端点分桶吸附、导入面板轮询暂停和 `PluginItem` 临时扩展导出。

## 验证

- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File installer\ai-v3.7.3\build.ps1`：通过，`InstallerCore` 85 项断言、嵌入载荷和版本元数据均已校验。
- SketchUp RBZ：12 个归档文件与当前 `source/` 文件数一致，根加载文件已校验。
- 未在本次打包后新增 Illustrator 或 SketchUp 人工现场测试；沿用此前已确认的导入和 AI 原生快捷键测试结果。
