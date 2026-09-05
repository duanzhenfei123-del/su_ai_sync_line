using Microsoft.Win32;
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Threading;

namespace SUAIInstaller
{
    internal static class InstallerCore
    {
        internal const string ExtensionName = "su-ai-png-export";
        private static readonly string[] LegacyRuntimeFiles = {
            "panel.heartbeat", "shortcut.command", "shortcuts.cfg"
        };

        internal static string DefaultExtensionsRoot()
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Adobe",
                "CEP",
                "extensions");
        }

        internal static string DefaultDataRoot()
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "SU_AI_PNG_Export");
        }

        internal static string TargetPath(string extensionsRoot)
        {
            if (String.IsNullOrWhiteSpace(extensionsRoot))
            {
                throw new ArgumentException("Extensions root is required.", "extensionsRoot");
            }

            return Path.Combine(Path.GetFullPath(extensionsRoot), ExtensionName);
        }

        internal static void ValidatePayload(Stream payload)
        {
            using (var copy = CopyToMemory(payload))
            using (var zip = new ZipArchive(copy, ZipArchiveMode.Read, true))
            {
                var hasManifest = false;
                var hasHostScript = false;

                foreach (var entry in zip.Entries)
                {
                    var name = entry.FullName.Replace('\\', '/');
                    if (String.Equals(name, "CSXS/manifest.xml", StringComparison.OrdinalIgnoreCase))
                    {
                        hasManifest = true;
                    }
                    if (String.Equals(name, "host/main.jsx", StringComparison.OrdinalIgnoreCase))
                    {
                        hasHostScript = true;
                    }
                }

                if (!hasManifest || !hasHostScript)
                {
                    throw new InvalidDataException("PluginPayload is missing required v3.7 files.");
                }
            }
        }

        internal static void Install(Stream payload, string extensionsRoot, bool enableDebugMode)
        {
            Install(payload, extensionsRoot, DefaultDataRoot(), enableDebugMode);
        }

        internal static void Install(
            Stream payload,
            string extensionsRoot,
            string dataRoot,
            bool enableDebugMode)
        {
            using (var bytes = CopyToMemory(payload))
            {
                ValidatePayload(bytes);
                bytes.Position = 0;

                var root = Path.GetFullPath(extensionsRoot);
                var target = TargetPath(root);
                var staging = Path.Combine(
                    root,
                    "." + ExtensionName + ".staging-" + Guid.NewGuid().ToString("N"));
                var backup = Path.Combine(
                    root,
                    "." + ExtensionName + ".backup-" + Guid.NewGuid().ToString("N"));

                Directory.CreateDirectory(root);
                var movedOld = false;
                var movedNew = false;

                try
                {
                    ExtractSafely(bytes, staging);
                    ValidateExtracted(staging);
                    PrepareLegacyShortcutRemoval(dataRoot, TimeSpan.FromSeconds(5));

                    if (Directory.Exists(target))
                    {
                        CreatePersistentBackup(target, dataRoot);
                        Directory.Move(target, backup);
                        movedOld = true;
                    }

                    Directory.Move(staging, target);
                    movedNew = true;

                    if (enableDebugMode)
                    {
                        EnableCepDebugMode();
                    }

                    if (Directory.Exists(backup))
                    {
                        Directory.Delete(backup, true);
                    }
                }
                catch (Exception installError)
                {
                    Exception restoreError = null;

                    try
                    {
                        if (movedNew && Directory.Exists(target))
                        {
                            Directory.Delete(target, true);
                        }
                    }
                    catch (Exception error)
                    {
                        restoreError = error;
                    }

                    try
                    {
                        if (movedOld && Directory.Exists(backup) && !Directory.Exists(target))
                        {
                            Directory.Move(backup, target);
                        }
                    }
                    catch (Exception error)
                    {
                        restoreError = restoreError == null
                            ? error
                            : new AggregateException(restoreError, error);
                    }

                    if (restoreError != null)
                    {
                        throw new IOException(
                            "Installation failed and the previous plugin could not be fully restored.",
                            new AggregateException(installError, restoreError));
                    }

                    throw;
                }
                finally
                {
                    TryDeleteDirectory(staging);
                }
            }
        }

        internal static void Uninstall(string extensionsRoot)
        {
            Uninstall(extensionsRoot, DefaultDataRoot());
        }

        internal static void Uninstall(string extensionsRoot, string dataRoot)
        {
            PrepareLegacyShortcutRemoval(dataRoot, TimeSpan.FromSeconds(5));
            var target = TargetPath(extensionsRoot);
            if (Directory.Exists(target))
            {
                Directory.Delete(target, true);
            }
        }

        internal static void EnableCepDebugMode()
        {
            for (var version = 9; version <= 20; version++)
            {
                using (var key = Registry.CurrentUser.CreateSubKey(@"Software\Adobe\CSXS." + version))
                {
                    if (key == null)
                    {
                        throw new InvalidOperationException("Unable to open CSXS." + version + " registry key.");
                    }
                    key.SetValue("PlayerDebugMode", "1", RegistryValueKind.String);
                }
            }
        }

        private static MemoryStream CopyToMemory(Stream input)
        {
            if (input == null)
            {
                throw new InvalidDataException("Missing PluginPayload resource.");
            }

            var copy = new MemoryStream();
            input.CopyTo(copy);
            copy.Position = 0;
            return copy;
        }

        private static void ExtractSafely(Stream payload, string staging)
        {
            Directory.CreateDirectory(staging);
            var prefix = Path.GetFullPath(staging).TrimEnd(Path.DirectorySeparatorChar)
                + Path.DirectorySeparatorChar;

            using (var zip = new ZipArchive(payload, ZipArchiveMode.Read, true))
            {
                foreach (var entry in zip.Entries)
                {
                    var relative = entry.FullName
                        .Replace('/', Path.DirectorySeparatorChar)
                        .Replace('\\', Path.DirectorySeparatorChar);
                    var destination = Path.GetFullPath(Path.Combine(staging, relative));

                    if (!destination.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    {
                        throw new InvalidDataException("Unsafe payload path: " + entry.FullName);
                    }

                    if (String.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(destination);
                        continue;
                    }

                    Directory.CreateDirectory(Path.GetDirectoryName(destination));
                    using (var input = entry.Open())
                    using (var output = File.Create(destination))
                    {
                        input.CopyTo(output);
                    }
                }
            }
        }

        private static void ValidateExtracted(string root)
        {
            var manifest = Path.Combine(root, "CSXS", "manifest.xml");
            var hostScript = Path.Combine(root, "host", "main.jsx");
            if (!File.Exists(manifest) || !File.Exists(hostScript))
            {
                throw new InvalidDataException("Extracted plugin is incomplete.");
            }
        }

        private static void PrepareLegacyShortcutRemoval(string dataRoot, TimeSpan timeout)
        {
            Directory.CreateDirectory(dataRoot);
            foreach (var name in LegacyRuntimeFiles)
            {
                TryDeleteFile(Path.Combine(dataRoot, name));
            }

            var status = Path.Combine(dataRoot, "shortcut-host.status");
            var deadline = DateTime.UtcNow + timeout;
            while (File.Exists(status) && LegacyHostIsRunning(status))
            {
                if (DateTime.UtcNow >= deadline)
                {
                    throw new IOException("旧版快捷键程序仍在运行。请关闭旧版 AI 插件面板后重试；Illustrator 不会被强制关闭。");
                }
                Thread.Sleep(100);
            }
            TryDeleteFile(status);
        }

        private static bool LegacyHostIsRunning(string statusPath)
        {
            try
            {
                int processId;
                if (!Int32.TryParse(File.ReadAllText(statusPath).Trim(), out processId))
                {
                    return false;
                }

                using (var process = Process.GetProcessById(processId))
                {
                    return !process.HasExited && String.Equals(
                        process.ProcessName,
                        "SUAIShortcutHost",
                        StringComparison.OrdinalIgnoreCase);
                }
            }
            catch
            {
                return false;
            }
        }

        private static string CreatePersistentBackup(string target, string dataRoot)
        {
            var backupRoot = Path.Combine(dataRoot, "backups");
            Directory.CreateDirectory(backupRoot);
            var name = "su-ai-png-export-" + DateTime.Now.ToString("yyyyMMdd-HHmmssfff") + ".zip";
            var path = Path.Combine(backupRoot, name);
            ZipFile.CreateFromDirectory(target, path, CompressionLevel.Optimal, false);
            return path;
        }

        private static void TryDeleteFile(string path)
        {
            try
            {
                if (File.Exists(path))
                {
                    File.Delete(path);
                }
            }
            catch
            {
            }
        }

        private static void TryDeleteDirectory(string path)
        {
            try
            {
                if (Directory.Exists(path))
                {
                    Directory.Delete(path, true);
                }
            }
            catch
            {
            }
        }
    }
}
