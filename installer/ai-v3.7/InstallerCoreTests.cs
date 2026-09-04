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
            var sibling = Path.Combine(extensions, "keep-me");
            Directory.CreateDirectory(sibling);
            File.WriteAllText(Path.Combine(sibling, "marker.txt"), "keep");

            try
            {
                using (var payload = Payload())
                {
                    InstallerCore.Install(payload, extensions, false);
                }

                var target = Path.Combine(extensions, "su-ai-png-export");
                Assert(
                    InstallerCore.TargetPath(extensions) == target,
                    "Installer target directory name changed");
                var expected = FileHashes(source);
                var actual = FileHashes(target);
                Assert(expected.Count == 12, "Expected 12 source files");
                Assert(actual.Count == expected.Count, "Installed file count differs");
                foreach (var pair in expected)
                {
                    Assert(
                        actual.ContainsKey(pair.Key) && actual[pair.Key] == pair.Value,
                        "Installed file mismatch: " + pair.Key);
                }

                File.WriteAllText(Path.Combine(target, "obsolete.txt"), "old");
                using (var payload = Payload())
                {
                    InstallerCore.Install(payload, extensions, false);
                }
                Assert(!File.Exists(Path.Combine(target, "obsolete.txt")), "Repeat install left obsolete file");

                var marker = Path.Combine(target, "existing.txt");
                File.WriteAllText(marker, "existing");
                using (var invalid = InvalidPayload())
                {
                    try
                    {
                        InstallerCore.Install(invalid, extensions, false);
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
                        InstallerCore.Install(unsafePayload, extensions, false);
                        Assert(false, "Unsafe payload path was accepted");
                    }
                    catch (InvalidDataException)
                    {
                    }
                }
                Assert(!File.Exists(escapedPath), "Unsafe payload escaped the staging directory");
                Assert(File.ReadAllText(marker) == "existing", "Unsafe payload changed existing install");

                InstallerCore.Uninstall(extensions);
                Assert(!Directory.Exists(target), "Target remained after uninstall");
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
