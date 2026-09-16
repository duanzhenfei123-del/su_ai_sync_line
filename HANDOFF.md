# SU+AI 同步开发交接

用于下次继续调整本插件。先阅读本文件，再检查 `README.md`、`source/` 和 `illustrator/su-ai-png-export/`。

## 当前状态

- 仓库：`git@github.com:duanzhenfei123-del/su_ai_sync_line.git`
- 主分支：`main`，最近一次 README/Release 规范提交为 `4aa07aa`。
- 当前配套版本：SketchUp `v3.7.3` + Illustrator `v3.7.3`。
- 已推送标签：`v3.6.0`、`v3.7.0`、`v3.7.1`、`v3.7.2`、`v3.7.3`。
- GitHub Releases 已按版本建立；每个版本只手动附加 SketchUp RBZ 和 AI Windows 安装器 EXE。GitHub 自动生成的 Source code ZIP/TAR 不属于手动上传附件。
- `v3.7.1` 是 AI 端维护版，SketchUp 端使用兼容的 `v3.7` RBZ。

## 继续开发约束

- SketchUp `v3.6` 面板布局和用户操作保持不变；后台能力可调整。
- 当前优化范围只有两项：端点吸附改为空间分桶；导入期间暂停 AI 面板选区轮询并保留导出完成提示。除非用户重新授权，不扩展其他优化项。
- AI 端不恢复全局快捷键钩子；Illustrator 原生快捷键必须放行。
- 默认导出目录只在用户点击导出时创建；未自定义路径时使用桌面的 `ai-export`。
- 日志保持单份：点击导入后删除历史日志，再生成本次导入日志。
- 修改前先运行 `git status -sb`，不要覆盖或删除用户未跟踪的历史包、备份和参考资料。

## GitHub 上传规范（每次发布必须遵守）

1. 先完成代码、测试和成品打包，再提交并推送 `main`。
2. 每次上传前都更新 `README.md`，必须包含：软件简介、适用端（SketchUp/Illustrator）、安装方式、基本使用方法、当前版本和 Release list 链接。
3. Release 使用语义化标签 `vX.Y.Z`，标题写成 `SU+AI 同步 vX.Y.Z`，并保持 v3.7.3 这类稳定版为 Latest。
4. Release 下载方式统一为 GitHub Releases；不要把根目录散落文件当作主要下载入口。
5. 每个 Release 只上传两个手动附件：
   - SketchUp 导入端：`SU_AI_Sync_Import_vX.Y.Z.rbz`（若该 SU 端兼容上一小版本，在 Release 说明中写明）。
   - AI 端：`SU_AI_PNG_Export_vX.Y.Z_Setup.exe`。
6. 不上传 ZIP、PDF、源码压缩包或构建中间文件到 Release；GitHub 自动生成的 Source code ZIP/TAR 无需处理。
7. 发布前核对标签、版本号、附件数量（手动附件应为 2 个）和 SHA-256；Release 说明只写实际验证过的内容，未实测项目明确标注。
8. 不删除旧 Release、旧草稿、历史包或用户备份；需要清理时先确认目标，再优先移入回收站或归档目录。

## 本地整理记录

- `build/` 为可重建的临时编译目录，已于 2026-09-16 移入 Windows 回收站。
- `backups/`、`reference_uploaded_v36/`、`reference_v361/`、`.worktrees/` 及根目录历史 RBZ 暂时保留，分别用于回滚、对比和历史调试。

## 下次开始检查

- `git status -sb`：确认只存在用户保留的未跟踪资料。
- `git worktree list`：不要删除仍有分支关联的 worktree。
- 运行 AI 自动化测试：
  `node test\\illustrator_protocol_test.js`
  `node test\\ai_global_shortcut_removal_test.js`
  `node test\\ai_selection_polling_test.js`
- 修改安装器版本时，复制对应 `installer/ai-vX.Y.Z/`，同步更新 `Program.cs`、`InstallerForm.cs`、`app.manifest` 和 `build.ps1`，不要改写旧版目录。
- SketchUp Ruby 自动化测试需要在 SketchUp 内运行；命令行没有可用的 SketchUp Ruby 运行时。

## 回滚

- 代码：切换到已推送的历史标签，例如 `v3.7.2`。
- 安装文件：使用对应 Release 的旧 RBZ/EXE，或使用本机安装备份目录恢复。
- 回收站中的 `build/` 可恢复；不要清空回收站后再判断是否需要它。
