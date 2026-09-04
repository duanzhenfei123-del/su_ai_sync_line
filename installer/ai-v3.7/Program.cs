using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[assembly: AssemblyTitle("SU+AI PNG Export Installer")]
[assembly: AssemblyDescription("SU+AI PNG Export v3.7 installer")]
[assembly: AssemblyCompany("段土土")]
[assembly: AssemblyProduct("SU+AI PNG Export Installer")]
[assembly: AssemblyCopyright("Copyright © 段土土 2026")]
[assembly: AssemblyVersion("3.7.0.0")]
[assembly: AssemblyFileVersion("3.7.0.0")]
[assembly: AssemblyInformationalVersion("3.7")]
[assembly: ComVisible(false)]

namespace SUAIInstaller
{
    internal static class Program
    {
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
