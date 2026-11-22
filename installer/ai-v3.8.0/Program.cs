using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[assembly: AssemblyTitle("DTT 轮廓与图片导出安装器")]
[assembly: AssemblyDescription("DTT 轮廓与图片导出安装器")]
[assembly: AssemblyCompany("段土土")]
[assembly: AssemblyProduct("DTT 轮廓与图片导出安装器")]
[assembly: AssemblyCopyright("Copyright © 段土土 2026")]
[assembly: AssemblyVersion(SUAIInstaller.Program.PluginVersion + ".0")]
[assembly: AssemblyFileVersion(SUAIInstaller.Program.PluginVersion + ".0")]
[assembly: AssemblyInformationalVersion(SUAIInstaller.Program.PluginVersion)]
[assembly: ComVisible(false)]

namespace SUAIInstaller
{
    internal static class Program
    {
        internal const string PluginVersion = "3.8.0";

        [STAThread]
        private static int Main(string[] args)
        {
            if (args.Length == 1 && args[0] == "--verify-payload")
            {
                try
                {
                    using (var payload = Assembly.GetExecutingAssembly()
                        .GetManifestResourceStream("PluginPayload"))
                    {
                        InstallerCore.ValidatePayload(payload);
                    }
                    return 0;
                }
                catch
                {
                    return 1;
                }
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new InstallerForm());
            return 0;
        }
    }
}
