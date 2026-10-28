using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;

namespace SUAIInstaller
{
    internal static class InstallerCoreTests
    {
        private static int assertions;

        private static void Assert(bool condition, string message)
        {
            assertions++;
            if (!condition)
            {
                throw new Exception(message);
            }
        }

        private static string Hash(string path)
        {
            using (var sha = SHA256.Create())
            using (var input = File.OpenRead(path))
            {
                return BitConverter.ToString(sha.ComputeHash(input)).Replace("-", "");
            }
        }

        private static Dictionary<string, string> FileHashes(string root)
        {
            var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var path in Directory.GetFiles(root, "*", SearchOption.AllDirectories))
            {
                var relative = path.Substring(root.Length).TrimStart(Path.DirectorySeparatorChar);
                result[relative] = Hash(path);
            }
            return result;
        }

        private static Stream Payload()
        {
            return Assembly.GetExecutingAssembly().GetManifestResourceStream("PluginPayload");
        }

        private static MemoryStream InvalidPayload()
        {
            var payload = new MemoryStream();
            using (var zip = new ZipArchive(payload, ZipArchiveMode.Create, true))
            {
                var entry = zip.CreateEntry("bad.txt");
                using (var writer = new StreamWriter(entry.Open()))
                {
                    writer.Write("bad");
                }
            }
            payload.Position = 0;
            return payload;
        }

        private static MemoryStream UnsafePayload()
        {
            var payload = new MemoryStream();
            using (var zip = new ZipArchive(payload, ZipArchiveMode.Create, true))
            {
                var manifest = zip.CreateEntry("CSXS/manifest.xml");
                using (var writer = new StreamWriter(manifest.Open()))
                {
                    writer.Write("manifest");
                }
                var host = zip.CreateEntry("host/main.jsx");
                using (var writer = new StreamWriter(host.Open()))
                {
                    writer.Write("host");
                }
                var escape = zip.CreateEntry("../escape.txt");
                using (var writer = new StreamWriter(escape.Open()))
                {
                    writer.Write("escape");
                }
            }
            payload.Position = 0;
            return payload;
        }

        public static int Main(string[] args)
        {
            if (args.Length != 1)
            {
                Console.Error.WriteLine("Usage: InstallerCoreTests.exe <plugin-source-directory>");
                return 2;
            }

            var source = Path.GetFullPath(args[0]);
            var temp = Path.Combine(Path.GetTempPath(), "suai-installer-test-" + Guid.NewGuid().ToString("N"));
            var extensions = Path.Combine(temp, "extensions");
            var dataRoot = Path.Combine(temp, "data");
            var sibling = Path.Combine(extensions, "keep-me");
            Directory.CreateDirectory(sibling);
            File.WriteAllText(Path.Combine(sibling, "marker.txt"), "keep");
            Directory.CreateDirectory(dataRoot);
            foreach (var name in new[] { "panel.heartbeat", "shortcut.command", "shortcuts.cfg" })
            {
                File.WriteAllText(Path.Combine(dataRoot, name), "legacy");
            }
            File.WriteAllText(Path.Combine(dataRoot, "shortcut-host.status"), "not-a-pid");

            try
            {
                using (var payload = Payload())
                {
                    InstallerCore.Install(payload, extensions, dataRoot, false);
                }
                foreach (var name in new[] { "panel.heartbeat", "shortcut.command", "shortcuts.cfg", "shortcut-host.status" })
                {
                    Assert(!File.Exists(Path.Combine(dataRoot, name)), "Legacy file remained: " + name);
                }

                var target = Path.Combine(extensions, "su-ai-png-export");
                Assert(
                    InstallerCore.TargetPath(extensions) == target,
                    "Installer target directory name changed");
                var expected = FileHashes(source);
                var actual = FileHashes(target);
                Assert(expected.Count == 11, "Expected 11 source files");
                Assert(actual.Count == expected.Count, "Installed file count differs");
                foreach (var pair in expected)
                {
                    Assert(
                        actual.ContainsKey(pair.Key) && actual[pair.Key] == pair.Value,
                        "Installed file mismatch: " + pair.Key);
                }

                File.WriteAllText(Path.Combine(target, "previous-version.txt"), "v3.7");
                using (var payload = Payload())
                {
                    InstallerCore.Install(payload, extensions, dataRoot, false);
                }
                var backups = Directory.GetFiles(Path.Combine(dataRoot, "backups"), "*.zip");
                Assert(backups.Length == 1, "Persistent upgrade backup was not retained");
                using (var zip = ZipFile.OpenRead(backups[0]))
                {
                    Assert(zip.GetEntry("previous-version.txt") != null, "Backup omitted previous plugin files");
                }
                Assert(!File.Exists(Path.Combine(target, "previous-version.txt")), "Upgrade left obsolete files");
                Assert(!File.Exists(Path.Combine(target, "bin", "SUAIShortcutHost.exe")), "Installed payload retained helper");

                var marker = Path.Combine(target, "existing.txt");
                File.WriteAllText(marker, "existing");
                using (var invalid = InvalidPayload())
                {
                    try
                    {
                        InstallerCore.Install(invalid, extensions, dataRoot, false);
                        Assert(false, "Invalid payload was accepted");
                    }
                    catch (InvalidDataException)
                    {
                    }
                }
                Assert(File.ReadAllText(marker) == "existing", "Invalid payload changed existing install");

                var escapedPath = Path.Combine(temp, "escape.txt");
                using (var unsafePayload = UnsafePayload())
                {
                    try
                    {
                        InstallerCore.Install(unsafePayload, extensions, dataRoot, false);
                        Assert(false, "Unsafe payload path was accepted");
                    }
                    catch (InvalidDataException)
                    {
                    }
                }
                Assert(!File.Exists(escapedPath), "Unsafe payload escaped the staging directory");
                Assert(File.ReadAllText(marker) == "existing", "Unsafe payload changed existing install");

                var beforeRollback = FileHashes(target);
                using (var payload = Payload())
                {
                    try
                    {
                        InstallerCore.Install(
                            payload,
                            extensions,
                            dataRoot,
                            false,
                            delegate { throw new IOException("forced after old target moved"); });
                        Assert(false, "Post-move failure was accepted");
                    }
                    catch (IOException error)
                    {
                        Assert(error.Message == "forced after old target moved", "Unexpected rollback failure");
                    }
                }
                var afterRollback = FileHashes(target);
                Assert(afterRollback.Count == beforeRollback.Count, "Rollback restored an incomplete target");
                foreach (var pair in beforeRollback)
                {
                    Assert(
                        afterRollback.ContainsKey(pair.Key) && afterRollback[pair.Key] == pair.Value,
                        "Rollback file mismatch: " + pair.Key);
                }

                var lockedOldFile = Path.Combine(target, "locked-old.txt");
                File.WriteAllText(lockedOldFile, "old");
                string retainedRollbackDirectory = null;
                FileStream locked = null;
                try
                {
                    Exception cleanupError = null;
                    using (var payload = Payload())
                    {
                        try
                        {
                            InstallerCore.Install(
                                payload,
                                extensions,
                                dataRoot,
                                false,
                                delegate
                                {
                                    foreach (var directory in Directory.GetDirectories(extensions))
                                    {
                                        var movedOldFile = Path.Combine(directory, "locked-old.txt");
                                        if (File.Exists(movedOldFile))
                                        {
                                            locked = new FileStream(
                                                movedOldFile,
                                                FileMode.Open,
                                                FileAccess.Read,
                                                FileShare.None);
                                            return;
                                        }
                                    }
                                    throw new IOException("Moved old target was not found");
                                });
                        }
                        catch (Exception error)
                        {
                            cleanupError = error;
                        }
                    }
                    Assert(cleanupError == null, "Post-commit rollback cleanup escaped: " + cleanupError);
                    var installedAfterCleanupFailure = FileHashes(target);
                    Assert(
                        installedAfterCleanupFailure.Count == expected.Count,
                        "Post-commit cleanup failure removed the valid new target");
                    foreach (var pair in expected)
                    {
                        Assert(
                            installedAfterCleanupFailure.ContainsKey(pair.Key)
                                && installedAfterCleanupFailure[pair.Key] == pair.Value,
                            "Post-commit target mismatch: " + pair.Key);
                    }
                    var retainedRollbackDirectories = Directory.GetDirectories(
                        extensions,
                        ".su-ai-png-export.rollback-*");
                    Assert(retainedRollbackDirectories.Length == 1, "Locked rollback directory was not retained");
                    retainedRollbackDirectory = retainedRollbackDirectories[0];
                }
                finally
                {
                    if (locked != null)
                    {
                        locked.Dispose();
                    }
                }
                Directory.Delete(retainedRollbackDirectory, true);

                var fakeHostAlive = true;
                var hostProbeCalls = 0;
                var beforeLiveHost = FileHashes(target);
                File.WriteAllText(Path.Combine(dataRoot, "shortcut-host.status"), "123");
                IOException liveHostError = null;
                try
                {
                    InstallerCore.Uninstall(
                        extensions,
                        dataRoot,
                        TimeSpan.Zero,
                        delegate(string statusPath)
                        {
                            hostProbeCalls++;
                            Assert(
                                statusPath == Path.Combine(dataRoot, "shortcut-host.status"),
                                "Host probe received the wrong status path");
                            return fakeHostAlive;
                        });
                }
                catch (IOException error)
                {
                    liveHostError = error;
                }
                Assert(hostProbeCalls == 1, "Live host was not probed exactly once");
                Assert(fakeHostAlive, "Live host probe was given a termination capability");
                Assert(liveHostError != null, "Live shortcut host did not block uninstall");
                Assert(
                    liveHostError.Message.Contains("请关闭旧版 AI 插件面板后重试")
                        && liveHostError.Message.Contains("Illustrator 不会被强制关闭"),
                    "Live host error was not actionable");
                Assert(Directory.Exists(target), "Live host timeout mutated the target");
                var afterLiveHost = FileHashes(target);
                Assert(afterLiveHost.Count == beforeLiveHost.Count, "Live host timeout changed target files");
                foreach (var pair in beforeLiveHost)
                {
                    Assert(
                        afterLiveHost.ContainsKey(pair.Key) && afterLiveHost[pair.Key] == pair.Value,
                        "Live host timeout changed target file: " + pair.Key);
                }

                var allBackups = Directory.GetFiles(Path.Combine(dataRoot, "backups"), "*.zip");
                Assert(allBackups.Length == 3, "Expected one persistent backup per attempted upgrade");
                var backupNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var backupPath in allBackups)
                {
                    var backupName = Path.GetFileNameWithoutExtension(backupPath);
                    Guid backupId;
                    Assert(
                        backupName.Length > 32
                            && Guid.TryParseExact(
                                backupName.Substring(backupName.Length - 32),
                                "N",
                                out backupId),
                        "Persistent backup name lacks a collision-resistant ID: " + backupName);
                    Assert(backupNames.Add(backupName), "Persistent backup names collided");
                }

                foreach (var name in new[] { "panel.heartbeat", "shortcut.command", "shortcuts.cfg" })
                {
                    File.WriteAllText(Path.Combine(dataRoot, name), "legacy");
                }
                File.WriteAllText(Path.Combine(dataRoot, "shortcut-host.status"), "not-a-pid");

                InstallerCore.Uninstall(extensions, dataRoot);
                Assert(!Directory.Exists(target), "Target remained after uninstall");
                foreach (var name in new[] { "panel.heartbeat", "shortcut.command", "shortcuts.cfg", "shortcut-host.status" })
                {
                    Assert(!File.Exists(Path.Combine(dataRoot, name)), "Legacy file remained after uninstall: " + name);
                }
                Assert(File.Exists(backups[0]), "Uninstall removed persistent backup");
                Assert(
                    File.ReadAllText(Path.Combine(sibling, "marker.txt")) == "keep",
                    "Sibling extension was changed");

                Console.WriteLine("PASS InstallerCore: " + assertions + " assertions");
                return 0;
            }
            catch (Exception error)
            {
                Console.Error.WriteLine("FAIL InstallerCore: " + error);
                return 1;
            }
            finally
            {
                if (Directory.Exists(temp))
                {
                    Directory.Delete(temp, true);
                }
            }
        }
    }
}
