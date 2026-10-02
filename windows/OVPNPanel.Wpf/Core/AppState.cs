using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Threading;
using System.Threading.Tasks;
using OVPNPanel.Theme;

namespace OVPNPanel.Core
{
    public enum AppPhase { Setup, Auth, Main }

    public class ToastMessage
    {
        public string Text;
        public BannerKind Kind;

        public ToastMessage(string text, BannerKind kind) { Text = text; Kind = kind; }
    }

    /// <summary>启动参数（仅供 CI 自动化界面检查 / 本地调试，正常启动不生效）</summary>
    public static class LaunchArgs
    {
        static readonly string[] Args = Environment.GetCommandLineArgs();

        public static string Value(string key)
        {
            for (int i = 0; i < Args.Length - 1; i++)
            {
                if (Args[i] == key) return Args[i + 1];
            }
            return null;
        }

        /// <summary>启动后直接展示的 Tab（0 线路 / 1 套餐 / 2 邀请 / 3 我的）</summary>
        public static int StartTab
        {
            get
            {
                int value;
                if (!int.TryParse(Value("-startTab"), out value)) return 0;
                return Math.Max(0, Math.Min(3, value));
            }
        }

        public static string ScrollTo => Value("-scrollTo");
    }

    /// <summary>全局应用状态：主控地址、登录态、用户信息、全局横幅提示</summary>
    public sealed class AppState : INotifyPropertyChanged
    {
        public static readonly AppState Shared = new AppState();

        AppPhase _phase = AppPhase.Setup;
        string _masterURL = "";
        AppUser _user;
        ToastMessage _toast;
        bool _busy;

        readonly ApiClient _api = ApiClient.Shared;
        CancellationTokenSource _toastCts;
        CancellationTokenSource _pollCts;
        string _lastNoticeKey;

        public event PropertyChangedEventHandler PropertyChanged;
        /// <summary>整体状态变化（供命令式构建的界面刷新）</summary>
        public event Action StateChanged;

        AppState()
        {
            Restore();
            ApplyLaunchOverrides();
        }

        public AppPhase Phase
        {
            get { return _phase; }
            private set { if (_phase != value) { _phase = value; Notify("Phase"); Raise(); } }
        }

        public string MasterURL
        {
            get { return _masterURL; }
            private set { if (_masterURL != value) { _masterURL = value; Notify("MasterURL"); Raise(); } }
        }

        public AppUser User
        {
            get { return _user; }
            private set { _user = value; Notify("User"); Raise(); }
        }

        public ToastMessage Toast
        {
            get { return _toast; }
            private set { _toast = value; Notify("Toast"); Raise(); }
        }

        public bool Busy
        {
            get { return _busy; }
            set { if (_busy != value) { _busy = value; Notify("Busy"); Raise(); } }
        }

        void Notify(string name)
        {
            var handler = PropertyChanged;
            if (handler != null) handler(this, new PropertyChangedEventArgs(name));
        }

        void Raise()
        {
            var handler = StateChanged;
            if (handler != null) handler();
        }

        // MARK: - 启动恢复

        void Restore()
        {
            var saved = LocalStore.MasterURL;
            if (!string.IsNullOrEmpty(saved))
            {
                _masterURL = saved;
                _api.SetBaseURL(saved);
                var token = SecureStore.Load();
                if (!string.IsNullOrEmpty(token))
                {
                    _api.SetToken(token);
                    _phase = AppPhase.Main;
                    Task.Run(async () => { await RefreshUser().ConfigureAwait(false); });
                    StartStatusPolling();
                }
                else
                {
                    _phase = AppPhase.Auth;
                }
            }
            else
            {
                _phase = AppPhase.Setup;
            }
        }

        void ApplyLaunchOverrides()
        {
            // 界面检查模式：-demo 直接进入主界面并注入演示数据（仅供 CI 截图 / 本地调试）
            if (LaunchArgs.Value("-demo") != null)
            {
                _masterURL = "http://127.0.0.1:9";
                _api.SetBaseURL(_masterURL);
                _user = DemoUser();
                _phase = AppPhase.Main;
                return;
            }

            var rawURL = LaunchArgs.Value("-masterURL");
            if (string.IsNullOrEmpty(rawURL)) return;
            var normalized = Normalize(rawURL);
            _masterURL = normalized;
            LocalStore.MasterURL = normalized;
            _api.SetBaseURL(normalized);
            _phase = AppPhase.Auth;
            var credentials = LaunchArgs.Value("-autoLogin");
            if (credentials != null)
            {
                var parts = credentials.Split(new[] { ':' }, 2);
                if (parts.Length == 2)
                {
                    Task.Run(async () =>
                    {
                        try { await Login(parts[0], parts[1]).ConfigureAwait(false); } catch { }
                    });
                }
            }
        }

        /// <summary>演示数据（仅 -demo 界面检查模式使用）</summary>
        static AppUser DemoUser()
        {
            return new AppUser
            {
                Id = 1,
                Username = "demo-user",
                Email = "demo@example.com",
                Role = "user",
                Status = "active",
                PlanId = 1,
                PlanName = "标准套餐",
                PlanExpiresAt = "2027-12-31T23:59:59Z",
                TrafficLimitBytes = 107374182400L,
                TrafficUsedBytes = 32212254720L,
                RemainBytes = 75161927680L,
                SpeedLimitKbps = 102400,
                DeviceLimit = 3,
                Level = 2,
                Coins = 1280,
                BalanceCents = 5600,
                BalanceYuan = 56.0,
            };
        }

        // MARK: - 主控配置

        /// <summary>校验并保存主控地址（可达即视为合法主控）</summary>
        public async Task ConfigureMaster(string url)
        {
            var normalized = Normalize(url);
            await _api.ProbeAsync(normalized).ConfigureAwait(false);
            MasterURL = normalized;
            LocalStore.MasterURL = normalized;
            _api.SetBaseURL(normalized);
            Phase = AppPhase.Auth;
        }

        public static string Normalize(string url)
        {
            var value = (url ?? "").Trim();
            var lower = value.ToLowerInvariant();
            if (!lower.StartsWith("http://") && !lower.StartsWith("https://")) value = "http://" + value;
            while (value.EndsWith("/")) value = value.Substring(0, value.Length - 1);
            return value;
        }

        // MARK: - 登录 / 注册

        public async Task Login(string account, string password)
        {
            var result = await _api.Login(account, password).ConfigureAwait(false);
            ApplyAuth(result);
            LocalStore.LastAccount = account;
            SecureStore.Save(password, SecureStore.PasswordAccount);
        }

        public async Task Register(string username, string password, string email,
            string captchaToken, string captchaInput)
        {
            var result = await _api.Register(username, password, email, captchaToken, captchaInput).ConfigureAwait(false);
            ApplyAuth(result);
            LocalStore.LastAccount = username;
            SecureStore.Save(password, SecureStore.PasswordAccount);
        }

        void ApplyAuth(AuthResult result)
        {
            _api.SetToken(result.Token);
            SecureStore.Save(result.Token);
            User = result.User;
            Phase = AppPhase.Main;
            StartStatusPolling();
        }

        public async Task RefreshUser()
        {
            try
            {
                var center = await _api.FetchUserCenter().ConfigureAwait(false);
                User = center.User;
            }
            catch (ApiException error)
            {
                if (error.Message != null && error.Message.Contains("未登录")) Logout();
            }
        }

        public void Logout()
        {
            StopStatusPolling();
            _api.SetToken(null);
            SecureStore.Clear();
            User = null;
            Phase = AppPhase.Auth;
            DismissToast();
        }

        /// <summary>切换主控（回到配置页）</summary>
        public void ResetMaster()
        {
            Logout();
            LocalStore.MasterURL = null;
            MasterURL = "";
            Phase = AppPhase.Setup;
        }

        // MARK: - 账号异常状态轮询

        void StartStatusPolling()
        {
            StopStatusPolling();
            _lastNoticeKey = null;
            var cts = new CancellationTokenSource();
            _pollCts = cts;
            Task.Run(async () =>
            {
                while (!cts.IsCancellationRequested)
                {
                    await PollStatus().ConfigureAwait(false);
                    try { await Task.Delay(8000, cts.Token).ConfigureAwait(false); }
                    catch { break; }
                }
            });
        }

        void StopStatusPolling()
        {
            if (_pollCts != null) { _pollCts.Cancel(); _pollCts = null; }
        }

        /// <summary>立即检查一次（连接失败、下单后等需要即时反馈的场景）</summary>
        public Task CheckStatusNow()
        {
            return PollStatus();
        }

        async Task PollStatus()
        {
            if (Phase != AppPhase.Main) return;
            UserStatusPayload payload;
            try { payload = await _api.FetchUserStatus().ConfigureAwait(false); }
            catch { return; }

            var notice = payload.Notice;
            if (notice == null)
            {
                _lastNoticeKey = null;
                return;
            }
            if (notice.Key == _lastNoticeKey) return;
            _lastNoticeKey = notice.Key;

            var kind = (notice.Code == "blocked" || notice.Code == "banned"
                        || notice.Code == "expired" || notice.Code == "over_quota")
                ? BannerKind.Error : BannerKind.Warning;
            ShowToast(notice.Message, kind);

            if (notice.Code == "blocked" || notice.Code == "banned")
            {
                VpnManager.Shared.Disconnect().Wait(3000);
            }
            if (payload.Quota == null || !payload.Quota.Valid) await RefreshUser().ConfigureAwait(false);
        }

        // MARK: - 全局横幅提示

        public void ShowToast(string message, BannerKind kind = BannerKind.Info)
        {
            var value = (message ?? "").Trim();
            if (value.Length == 0) return;
            Ui.Post(() =>
            {
                if (_toastCts != null) { _toastCts.Cancel(); _toastCts = null; }
                Toast = new ToastMessage(value, kind);
                var cts = new CancellationTokenSource();
                _toastCts = cts;
                var duration = kind == BannerKind.Error ? 3600 : 2600;
                Task.Run(async () =>
                {
                    try
                    {
                        await Task.Delay(duration, cts.Token).ConfigureAwait(false);
                        Ui.Post(() => { if (_toastCts == cts) DismissToast(); });
                    }
                    catch { }
                });
            });
        }

        /// <summary>统一错误上报：取消类错误静默忽略，其余以红色横幅提示</summary>
        public void Report(Exception error)
        {
            var apiError = ApiException.From(error);
            if (apiError.IsCancelled) return;
            ShowToast(apiError.Message, BannerKind.Error);
        }

        public void DismissToast()
        {
            if (_toastCts != null) { _toastCts.Cancel(); _toastCts = null; }
            Toast = null;
        }
    }
}
