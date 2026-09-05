# SU+AI 同步导入 — 发布包 v3.7.2

本目录为本次配套发布的独立成品目录；不会覆盖仓库根目录或旧版本成品。

## 成品与 SHA-256

| 成品 | 说明 | SHA-256 |
| --- | --- | --- |
| `AI同步导入SU_2026_v3.7.rbz` | SketchUp 导入端；本次无 SU 源码行为变更，插件内部版本保持 v3.7。 | `C1527AA4E07F4B5042DE019A9983B318901D9E090A730C1BC09F1C5EE8E7E418` |
| `SU_AI_PNG_Export_v3.7.2.zip` | Illustrator CEP 插件平铺安装包。 | `1D4F2F66BC30389414892F6A7EDDBFB06407E4B4AF1E75DFDC4837952C1C2724` |
| `SU_AI_PNG_Export_v3.7.2_Setup.exe` | Illustrator Windows 安装器。 | `8B3A794FF055FFB96E9EA582484CB974303AF481ABFD5362E4E03C440EB0F845` |

## 本次 AI 更新

- 导出 `PluginItem` 时，仅在临时副本上调用 Illustrator 的“扩展外观”（`expandStyle`）；原对象及当前选择会恢复。
- 扩展结果中的组、路径与复合路径可继续按既有协议导出；无法扩展的对象会保留明确的跳过原因。
- 保持 v3.7.1 已移除全局快捷键的实现，避免拦截 Illustrator 原生按键。

用户已在 Illustrator 中对本次 `PluginItem` 自动扩展导出进行了实机确认；本 v3.7.2 成品相对此测试版本仅更新发布版本元数据与安装器标识。

## 已完成的验证

- `node test\\illustrator_protocol_test.js`：通过。
- `node test\\ai_global_shortcut_removal_test.js`：通过。
- AI 安装器内核：`PASS InstallerCore: 85 assertions`。
- AI 安装器构建后已校验嵌入载荷，文件版本为 `3.7.2.0`，产品版本为 `3.7.2`。
- SU RBZ 已按当前 `source` 打包，并逐文件校验 12 个归档条目与源码 SHA-256 一致。

未在本轮运行 SketchUp 的 Ruby 自动化套件；SU 成品来自当前已合并的 v3.7 源码，未改动其行为。

## 安装

- SketchUp：在扩展管理器中安装 `AI同步导入SU_2026_v3.7.rbz`。
- Illustrator：优先运行 `SU_AI_PNG_Export_v3.7.2_Setup.exe`；安装器不会重启 Illustrator。也可解压 ZIP 后按包内《手动安装说明》安装。
