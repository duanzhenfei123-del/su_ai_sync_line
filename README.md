# SU+AI 同步

将 Adobe Illustrator 的路径、文字轮廓、分组和图片导出为同步数据，再导入 SketchUp 继续建模。

当前发布版本：**v3.7.3**。

## 下载与安装

请从 [Releases](https://github.com/duanzhenfei123-del/su_ai_sync_line/releases) 下载同一版本的两个成品：

1. `AI同步导入SU_2026_v*.rbz`：在 SketchUp 的“扩展管理器 → 安装扩展”中安装。
2. `SU_AI_PNG_Export_v*_Setup.exe`：Windows 上运行安装器安装 Illustrator 端。

首次在 Illustrator 面板点击导出时，若未选择其他目录，会在桌面创建 `ai-export`；启动插件本身不会创建该目录。

## 主要功能

- 路径、复合路径、文字轮廓、分组、图片和颜色同步。
- SketchUp 导入、封面与拉成立体；文字孔洞和侧面朝向可正确处理。
- `PluginItem` 轮廓导出时自动在临时副本执行“扩展外观”，不改动原对象。
- AI 端不再安装全局快捷键钩子，避免影响 Illustrator 原生快捷键。

## Release list

| 版本 | 发布内容 | 说明 |
| --- | --- | --- |
| [v3.7.3](https://github.com/duanzhenfei123-del/su_ai_sync_line/releases/tag/v3.7.3) | SketchUp RBZ + AI Windows 安装器 | 当前版本；AI 延迟创建默认导出目录，SU 导入端保持 v3.7.3。 |
| [v3.7.2](https://github.com/duanzhenfei123-del/su_ai_sync_line/releases/tag/v3.7.2) | SketchUp RBZ + AI Windows 安装器 | 支持 `PluginItem` 临时扩展后导出轮廓。 |
| [v3.7.1](https://github.com/duanzhenfei123-del/su_ai_sync_line/releases/tag/v3.7.1) | SketchUp v3.7 RBZ + AI Windows 安装器 | 移除 AI 全局快捷键。 |
| [v3.7.0](https://github.com/duanzhenfei123-del/su_ai_sync_line/releases/tag/v3.7.0) | SketchUp RBZ + AI Windows 安装器 | schema-v2 同步协议版本。 |
| [v3.6.0](https://github.com/duanzhenfei123-del/su_ai_sync_line/releases/tag/v3.6.0) | SketchUp RBZ + AI Windows 安装器 | 首个公开版本。 |

旧版本仅用于兼容和回退。日常使用请安装同一 Release 中的成品；v3.7.1 是仅更新 AI 端的例外。

## 仓库结构

| 目录/文件 | 用途 |
| --- | --- |
| `source/` | SketchUp Ruby 源码。 |
| `illustrator/su-ai-png-export/` | Illustrator CEP 插件源码与手动安装说明。 |
| `releases/` | 从 v3.7.2 起按版本保存的发布成品与校验说明。 |
| `installer/` | AI Windows 安装器构建源码。 |
| `RELEASE_v3.6.md`、`RELEASE_v3.7.1.md` | 历史版本说明。 |

## 使用流程

1. 在 Illustrator 面板选择导出目录并导出 JSON。
2. 在 SketchUp 中打开“SU+AI 同步”，选择同一目录。
3. 按需要设置比例、曲线精度、封面或拉伸后导入。

## 许可

本项目源码公开，仅限学习、分发和非商业修改。禁止用于商业产品、收费服务或盈利性分发；详见 [LICENSE](./LICENSE)。
