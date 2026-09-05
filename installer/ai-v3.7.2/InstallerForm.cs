using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

namespace SUAIInstaller
{
    internal sealed class InstallerForm : Form
    {
        private readonly Button installButton;
        private readonly Button uninstallButton;
        private readonly Label statusLabel;
        private readonly string extensionsRoot;

        internal InstallerForm()
        {
            extensionsRoot = InstallerCore.DefaultExtensionsRoot();

            Text = "SU+AI PNG 导出 v3.7.2 安装器";
            ClientSize = new Size(560, 306);
            MinimumSize = new Size(576, 345);
            MaximumSize = new Size(576, 345);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = true;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(245, 246, 248);
            Font = new Font("Microsoft YaHei UI", 9F, FontStyle.Regular, GraphicsUnit.Point);
            AutoScaleMode = AutoScaleMode.Font;

            var header = new Panel
            {
                BackColor = Color.FromArgb(36, 39, 46),
                Dock = DockStyle.Top,
                Height = 90
            };
            var title = new Label
            {
                Text = "SU+AI PNG 导出",
                ForeColor = Color.White,
                Font = new Font("Microsoft YaHei UI", 19F, FontStyle.Bold, GraphicsUnit.Point),
                AutoSize = true,
                Location = new Point(24, 17)
            };
            var version = new Label
            {
                Text = "Illustrator 插件安装器  ·  v3.7.2",
                ForeColor = Color.FromArgb(190, 196, 207),
                AutoSize = true,
                Location = new Point(27, 57)
            };
            header.Controls.Add(title);
            header.Controls.Add(version);

            var pathTitle = new Label
            {
                Text = "安装位置",
                ForeColor = Color.FromArgb(75, 79, 88),
                Font = new Font(Font, FontStyle.Bold),
                AutoSize = true,
                Location = new Point(28, 112)
            };
            var pathBox = new TextBox
            {
                Text = InstallerCore.TargetPath(extensionsRoot),
                ReadOnly = true,
                BorderStyle = BorderStyle.FixedSingle,
                BackColor = Color.White,
                Location = new Point(28, 136),
                Size = new Size(504, 26),
                TabStop = false
            };

            installButton = new Button
            {
                Text = "安装插件",
                BackColor = Color.FromArgb(44, 116, 219),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat,
                Location = new Point(98, 187),
                Size = new Size(160, 42),
                Cursor = Cursors.Hand
            };
            installButton.FlatAppearance.BorderSize = 0;

            uninstallButton = new Button
            {
                Text = "卸载插件",
                BackColor = Color.White,
                ForeColor = Color.FromArgb(66, 69, 76),
                FlatStyle = FlatStyle.Flat,
                Location = new Point(302, 187),
                Size = new Size(160, 42),
                Cursor = Cursors.Hand
            };
            uninstallButton.FlatAppearance.BorderColor = Color.FromArgb(190, 194, 202);

            var footer = new Panel
            {
                BackColor = Color.FromArgb(232, 234, 238),
                Dock = DockStyle.Bottom,
                Height = 48
            };
            statusLabel = new Label
            {
                Text = Directory.Exists(InstallerCore.TargetPath(extensionsRoot))
                    ? "状态：检测到已安装插件，可覆盖安装或卸载。"
                    : "状态：尚未安装。",
                ForeColor = Color.FromArgb(76, 80, 88),
                AutoEllipsis = true,
                Location = new Point(28, 15),
                Size = new Size(504, 24)
            };
            footer.Controls.Add(statusLabel);

            installButton.Click += InstallClicked;
            uninstallButton.Click += UninstallClicked;
            AcceptButton = installButton;

            Controls.Add(header);
            Controls.Add(pathTitle);
            Controls.Add(pathBox);
            Controls.Add(installButton);
            Controls.Add(uninstallButton);
            Controls.Add(footer);
        }

        private void SetBusy(bool busy)
        {
            installButton.Enabled = !busy;
            uninstallButton.Enabled = !busy;
            UseWaitCursor = busy;
        }

        private void InstallClicked(object sender, EventArgs args)
        {
            SetBusy(true);
            statusLabel.Text = "状态：正在安装……";
            Refresh();

            try
            {
                using (var payload = Assembly.GetExecutingAssembly()
                    .GetManifestResourceStream("PluginPayload"))
                {
                    InstallerCore.Install(payload, extensionsRoot, true);
                }

                statusLabel.Text = "状态：安装完成；安装器未重启 Illustrator。";
                MessageBox.Show(
                    this,
                    "SU+AI PNG 导出 v3.7.2 安装完成。\n\n安装器没有重启 Illustrator。如需自行重启，请先保存工作。\n\n打开：\n窗口 > 扩展（旧版）> SU+AI PNG 导出",
                    "安装完成",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }
            catch (Exception error)
            {
                statusLabel.Text = "状态：安装失败。";
                MessageBox.Show(
                    this,
                    error.Message,
                    "安装失败",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                SetBusy(false);
            }
        }

        private void UninstallClicked(object sender, EventArgs args)
        {
            SetBusy(true);
            statusLabel.Text = "状态：正在卸载……";
            Refresh();

            try
            {
                var target = InstallerCore.TargetPath(extensionsRoot);
                var existed = Directory.Exists(target);
                InstallerCore.Uninstall(extensionsRoot);

                statusLabel.Text = existed
                    ? "状态：卸载完成。"
                    : "状态：没有检测到已安装插件。";
                MessageBox.Show(
                    this,
                    existed ? "插件已卸载。" : "没有检测到已安装的插件。",
                    "SU+AI PNG 导出",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }
            catch (Exception error)
            {
                statusLabel.Text = "状态：卸载失败。";
                MessageBox.Show(
                    this,
                    error.Message,
                    "卸载失败",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                SetBusy(false);
            }
        }
    }
}
