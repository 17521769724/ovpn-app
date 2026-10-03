using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;

namespace OVPNPanel.Core
{
    /// <summary>隧道连接状态（与 iOS / Android 端语义一致）</summary>
    public enum VpnStatus { Invalid, Disconnected, Connecting, Connected, Reasserting, Disconnecting }

    /// <summary>
    /// OpenVPN 隧道管理（对应 iOS VPNManager / Android VpnBridge）。
    ///
    /// Windows 端通过系统已安装的 openvpn.exe 建立隧道：
    /// 把主控下发的 .ovpn 写入临时目录，再用 `--auth-user-pass` 传入账号密码后拉起进程，
    /// 通过解析进程输出与退出事件维护与移动端完全一致的状态机。
    /// </summary>
    public sealed class VpnManager
    {
        public static readonly VpnManager Shared = new VpnManager();

        const int ManagementPort = 25340;

        VpnStatus _status = VpnStatus.Disconnected;
        string _lastError;
        DateTime? _connectedAt;
        string _activeServerName = "";
        string _activeLineName = "";
        int _activeNodeId;
        bool _observing;

        Process _process;
        string _workDir;
        readonly object _lock = new object();
        DateTime _lastSessionCleanupAt = DateTime.MinValue;

        public event Action Changed;

        VpnManager() { }

        public VpnStatus Status { get { return _status; } }
        public string LastError { get { return _lastError; } }
        public DateTime? ConnectedAt { get { return _connectedAt; } }
        public string ActiveServerName { get { return _activeServerName; } }
        public string ActiveLineName { get { return _activeLineName; } }
        public int ActiveNodeId { get { return _activeNodeId; } }
        public bool IsConnected { get { return _status == VpnStatus.Connected; } }
        public bool IsBusy
        {
            get
            {
                return _status == VpnStatus.Connecting || _status == VpnStatus.Disconnecting
                    || _status == VpnStatus.Reasserting;
            }
        }

        public string StatusText
        {
            get
            {
                switch (_status)
                {
                    case VpnStatus.Connected: return "已连接";
                    case VpnStatus.Connecting: return "连接中…";
                    case VpnStatus.Disconnecting: return "正在断开…";
                    case VpnStatus.Reasserting: return "正在重连…";
                    case VpnStatus.Invalid: return "不可用";
                    default: return "未连接";
                }
            }
        }

        void Raise() { var handler = Changed; if (handler != null) Ui.Post(handler); }

        public void StartObserving()
        {
            if (_observing) return;
            _observing = true;
        }

        /// <summary>首次进入线路页时调用（对齐 iOS prepare）</summary>
        public Task Prepare()
        {
            StartObserving();
            SyncStatus();
            return Task.FromResult(0);
        }

        /// <summary>回到前台 / 冷启动时同步状态，并补偿清理遗留的主控在线会话</summary>
        public async Task RefreshStatus()
        {
            StartObserving();
            SyncStatus();
            if (_status == VpnStatus.Disconnected || _status == VpnStatus.Invalid)
            {
                await CleanupRemoteSessions(false).ConfigureAwait(false);
            }
        }

        void SyncStatus()
        {
            var previous = _status;
            if (_process == null || _process.HasExited)
            {
                _status = VpnStatus.Disconnected;
            }

            if (_status == VpnStatus.Connected)
            {
                LocalStore.SessionLikelyOpen = true;
                var stored = LocalStore.SessionConnectedAt;
                if (_connectedAt == null)
                {
                    _connectedAt = stored > 0
                        ? (DateTime?)DateTimeOffset.FromUnixTimeSeconds((long)stored).LocalDateTime
                        : DateTime.Now;
                    LocalStore.SessionConnectedAt = ((DateTimeOffset)_connectedAt.Value).ToUnixTimeSeconds();
                }
            }
            else if (_status == VpnStatus.Disconnected || _status == VpnStatus.Invalid)
            {
                _connectedAt = null;
                LocalStore.SessionConnectedAt = 0;
            }

            var wasActive = previous == VpnStatus.Connected || previous == VpnStatus.Disconnecting
                || previous == VpnStatus.Reasserting;
            if ((_status == VpnStatus.Disconnected || _status == VpnStatus.Invalid) && wasActive)
            {
                Task.Run(async () => await CleanupRemoteSessions(true).ConfigureAwait(false));
            }
            Raise();
        }

        /// <summary>关闭主控侧在线会话（节流 30s；force 时忽略节流）</summary>
        async Task CleanupRemoteSessions(bool force)
        {
            if (!LocalStore.SessionLikelyOpen) return;
            if (!force && (DateTime.Now - _lastSessionCleanupAt).TotalSeconds < 30) return;
            _lastSessionCleanupAt = DateTime.Now;
            try { await ApiClient.Shared.CloseSessions().ConfigureAwait(false); } catch { }
            LocalStore.SessionLikelyOpen = false;
        }

        /// <summary>解析「服务器 ｜ 线路」标题（兼容旧版本 " · " 分隔）</summary>
        void ApplyTitle(string title)
        {
            if (string.IsNullOrEmpty(title)) return;
            var parts = title.Split(new[] { " ｜ " }, StringSplitOptions.None);
            if (parts.Length < 2) parts = title.Split(new[] { " · " }, StringSplitOptions.None);
            _activeServerName = parts[0];
            _activeLineName = parts.Length > 1 ? parts[1] : "";
        }

        // MARK: - 连接 / 断开

        /// <summary>使用主控下发的 .ovpn 配置建立连接</summary>
        public async Task Connect(LineConfig profile, string username, string password)
        {
            if (_process != null && !_process.HasExited) return;

            _lastError = null;
            _activeServerName = profile.NodeName;
            _activeLineName = profile.LineName;
            _activeNodeId = profile.NodeId;

            var exe = LocateOpenVpn();
            if (exe == null)
            {
                _status = VpnStatus.Disconnected;
                Raise();
                throw new InvalidOperationException(
                    "内置 OpenVPN 内核不可用，且系统未安装 OpenVPN，请重新下载客户端或安装 OpenVPN 后重试");
            }

            _status = VpnStatus.Connecting;
            Raise();

            try
            {
                _workDir = Path.Combine(Path.GetTempPath(), "OVPNPanel-" + Guid.NewGuid().ToString("N").Substring(0, 8));
                Directory.CreateDirectory(_workDir);

                var authFile = Path.Combine(_workDir, "auth.txt");
                File.WriteAllText(authFile, (username ?? "") + "\r\n" + (password ?? "") + "\r\n", new UTF8Encoding(false));

                var configFile = Path.Combine(_workDir, "profile.ovpn");
                var content = profile.Content ?? "";
                if (content.IndexOf("auth-user-pass", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    content += "\r\nauth-user-pass \"" + authFile + "\"\r\n";
                }
                File.WriteAllText(configFile, content, new UTF8Encoding(false));

                var startInfo = new ProcessStartInfo
                {
                    FileName = exe,
                    Arguments = "--config \"" + configFile + "\" --auth-user-pass \"" + authFile + "\""
                                + " --auth-nocache" + DriverArgument(exe),
                    WorkingDirectory = _workDir,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                };

                var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
                process.OutputDataReceived += (s, e) => HandleLine(e.Data);
                process.ErrorDataReceived += (s, e) => HandleLine(e.Data);
                process.Exited += (s, e) => HandleExited();
                _process = process;

                if (!process.Start())
                {
                    throw new InvalidOperationException("无法启动 OpenVPN 进程");
                }
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
            }
            catch (Exception error)
            {
                _lastError = error.Message;
                _status = VpnStatus.Disconnected;
                Raise();
                throw;
            }

            LocalStore.SessionLikelyOpen = true;
            await Task.FromResult(0).ConfigureAwait(false);
        }

        void HandleLine(string line)
        {
            if (string.IsNullOrEmpty(line)) return;
            if (line.IndexOf("Initialization Sequence Completed", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                Ui.Post(() =>
                {
                    _status = VpnStatus.Connected;
                    _connectedAt = DateTime.Now;
                    LocalStore.SessionConnectedAt = ((DateTimeOffset)_connectedAt.Value).ToUnixTimeSeconds();
                    LocalStore.SessionLikelyOpen = true;
                    Raise();
                });
            }
            else if (line.IndexOf("AUTH_FAILED", StringComparison.OrdinalIgnoreCase) >= 0
                     || line.IndexOf("Options error", StringComparison.OrdinalIgnoreCase) >= 0
                     || line.IndexOf("Cannot open", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                _lastError = line.Trim();
                Ui.Post(Raise);
            }
            else if (line.IndexOf("SIGUSR1", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                Ui.Post(() => { _status = VpnStatus.Reasserting; Raise(); });
            }
        }

        void HandleExited()
        {
            Ui.Post(() =>
            {
                var wasActive = _status == VpnStatus.Connected || _status == VpnStatus.Reasserting
                    || _status == VpnStatus.Disconnecting;
                _process = null;
                _status = VpnStatus.Disconnected;
                _connectedAt = null;
                LocalStore.SessionConnectedAt = 0;
                _activeServerName = "";
                _activeLineName = "";
                _activeNodeId = 0;
                try { if (!string.IsNullOrEmpty(_workDir) && Directory.Exists(_workDir)) Directory.Delete(_workDir, true); }
                catch { }
                Raise();
                if (wasActive) Task.Run(async () => await CleanupRemoteSessions(true).ConfigureAwait(false));
            });
        }

        /// <summary>断开连接（保留配置，便于下次快速连接）</summary>
        public async Task Disconnect()
        {
            var process = _process;
            if (process == null || process.HasExited)
            {
                _status = VpnStatus.Disconnected;
                Raise();
                return;
            }
            _status = VpnStatus.Disconnecting;
            Raise();
            try
            {
                process.Kill();
                await Task.Run(() => process.WaitForExit(5000)).ConfigureAwait(false);
            }
            catch { }
            await Task.Delay(120).ConfigureAwait(false);
            SyncStatus();
        }

        // MARK: - 内置 OpenVPN 2.6 内核（随 EXE 打包，开箱即用）

        /// <summary>内置内核解包目录：%LOCALAPPDATA%\OVPNPanel\openvpn（bin / driver 子目录）</summary>
        static string BundledDir
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "OVPNPanel", "openvpn");
            }
        }

        static string BundledExe { get { return Path.Combine(BundledDir, "bin", "openvpn.exe"); } }

        /// <summary>
        /// 把随 EXE 打包的 OpenVPN 2.6 内核（嵌入资源 openvpn.zip）解包到本地目录。
        /// 返回 openvpn.exe 完整路径；未内置内核（如自编译调试版）时返回 null。
        /// </summary>
        public static string EnsureBundledOpenVpn()
        {
            try
            {
                if (File.Exists(BundledExe)) return BundledExe;

                var assembly = Assembly.GetExecutingAssembly();
                using (var stream = assembly.GetManifestResourceStream("OVPNPanel.openvpn.zip"))
                {
                    if (stream == null) return null;

                    var root = Path.GetFullPath(BundledDir);
                    Directory.CreateDirectory(root);
                    using (var archive = new ZipArchive(stream, ZipArchiveMode.Read))
                    {
                        foreach (var entry in archive.Entries)
                        {
                            if (string.IsNullOrEmpty(entry.Name)) continue; // 目录项
                            var target = Path.GetFullPath(Path.Combine(root, entry.FullName));
                            // 防目录穿越（zip 内路径异常时直接跳过）
                            if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) continue;
                            var parent = Path.GetDirectoryName(target);
                            if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
                            entry.ExtractToFile(target, true);
                        }
                    }
                }
                return File.Exists(BundledExe) ? BundledExe : null;
            }
            catch
            {
                // 解包失败（磁盘权限等）：静默回退到「程序目录 / 系统安装 / PATH」
                return null;
            }
        }

        /// <summary>
        /// 附加驱动参数：内置内核自带 wintun.dll 时优先使用 Wintun 虚拟网卡
        /// （免安装内核驱动，首次连接无需任何额外操作；不可用时回退系统 TAP 驱动）。
        /// </summary>
        static string DriverArgument(string exe)
        {
            try
            {
                var dir = Path.GetDirectoryName(exe);
                if (!string.IsNullOrEmpty(dir) && File.Exists(Path.Combine(dir, "wintun.dll")))
                {
                    return " --windows-driver wintun";
                }
            }
            catch { }
            return "";
        }

        // MARK: - openvpn.exe 定位

        /// <summary>按「用户指定 → 内置内核 → 程序目录 → 常见安装目录 → PATH」顺序探测</summary>
        public static string LocateOpenVpn()
        {
            var configured = LocalStore.OpenVpnPath;
            if (!string.IsNullOrEmpty(configured) && File.Exists(configured)) return configured;

            var bundled = EnsureBundledOpenVpn();
            if (!string.IsNullOrEmpty(bundled)) return bundled;

            var candidates = new List<string>();
            var appDir = AppDomain.CurrentDomain.BaseDirectory;
            candidates.Add(Path.Combine(appDir, "openvpn.exe"));
            candidates.Add(Path.Combine(appDir, "openvpn", "openvpn.exe"));

            var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            candidates.Add(Path.Combine(programFiles, "OpenVPN", "bin", "openvpn.exe"));
            candidates.Add(Path.Combine(programFilesX86, "OpenVPN", "bin", "openvpn.exe"));

            foreach (var candidate in candidates)
            {
                try { if (File.Exists(candidate)) return candidate; } catch { }
            }

            var path = Environment.GetEnvironmentVariable("PATH") ?? "";
            foreach (var dir in path.Split(';'))
            {
                if (string.IsNullOrWhiteSpace(dir)) continue;
                try
                {
                    var candidate = Path.Combine(dir.Trim(), "openvpn.exe");
                    if (File.Exists(candidate)) return candidate;
                }
                catch { }
            }
            return null;
        }
    }
}
