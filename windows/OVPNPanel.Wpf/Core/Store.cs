using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace OVPNPanel.Core
{
    /// <summary>本地存储：主控地址 / 上次登录账号（对应 iOS UserDefaults）</summary>
    public static class LocalStore
    {
        static readonly string Dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "OVPNPanel");
        static readonly string File = Path.Combine(Dir, "settings.json");

        static Dictionary<string, object> _cache;

        static Dictionary<string, object> Load()
        {
            if (_cache != null) return _cache;
            try
            {
                if (System.IO.File.Exists(File))
                {
                    _cache = J.Dict(J.Parse(System.IO.File.ReadAllText(File, Encoding.UTF8)));
                }
            }
            catch { }
            if (_cache == null) _cache = new Dictionary<string, object>();
            return _cache;
        }

        static void Persist()
        {
            try
            {
                Directory.CreateDirectory(Dir);
                System.IO.File.WriteAllText(File, J.Serialize(_cache), Encoding.UTF8);
            }
            catch { }
        }

        static string Get(string key)
        {
            object value;
            return Load().TryGetValue(key, out value) && value != null ? Convert.ToString(value) : null;
        }

        static void Set(string key, string value)
        {
            var data = Load();
            if (value == null) data.Remove(key);
            else data[key] = value;
            Persist();
        }

        public static string MasterURL
        {
            get { return Get("ovpn.master.url"); }
            set { Set("ovpn.master.url", value); }
        }

        public static string LastAccount
        {
            get { return Get("ovpn.last.account"); }
            set { Set("ovpn.last.account", value); }
        }

        /// <summary>会话连接时间戳（用于重启后恢复连接时长）</summary>
        public static double SessionConnectedAt
        {
            get
            {
                double parsed;
                return double.TryParse(Get("ovpn.session.connectedAt"), out parsed) ? parsed : 0;
            }
            set { Set("ovpn.session.connectedAt", value > 0 ? value.ToString("R") : null); }
        }

        public static bool SessionLikelyOpen
        {
            get { return Get("ovpn.session.likelyOpen") == "1"; }
            set { Set("ovpn.session.likelyOpen", value ? "1" : null); }
        }

        /// <summary>OpenVPN 可执行文件路径（用户可手动指定；留空则自动探测）</summary>
        public static string OpenVpnPath
        {
            get { return Get("ovpn.openvpn.path"); }
            set { Set("ovpn.openvpn.path", value); }
        }
    }

    /// <summary>
    /// 令牌与凭据安全存储（对应 iOS Keychain）。
    /// Windows 端使用 DPAPI（当前用户范围）加密后落盘，密文无法被其他用户解密。
    /// </summary>
    public static class SecureStore
    {
        public const string TokenAccount = "app.token";
        /// <summary>连接 VPN 用的账号密码（登录成功后保存，连接时自动使用）</summary>
        public const string PasswordAccount = "vpn.password";

        static readonly string Dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "OVPNPanel", "secure");

        static string PathFor(string account)
        {
            var safe = Convert.ToBase64String(Encoding.UTF8.GetBytes(account))
                .Replace('/', '_').Replace('+', '-').Replace('=', '.');
            return Path.Combine(Dir, safe + ".bin");
        }

        public static void Save(string value, string account = TokenAccount)
        {
            try
            {
                Directory.CreateDirectory(Dir);
                var raw = Encoding.UTF8.GetBytes(value ?? "");
                var encrypted = ProtectedData.Protect(raw, null, DataProtectionScope.CurrentUser);
                System.IO.File.WriteAllBytes(PathFor(account), encrypted);
            }
            catch { }
        }

        public static string Load(string account = TokenAccount)
        {
            try
            {
                var path = PathFor(account);
                if (!System.IO.File.Exists(path)) return null;
                var encrypted = System.IO.File.ReadAllBytes(path);
                var raw = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(raw);
            }
            catch { return null; }
        }

        public static void Clear(string account = TokenAccount)
        {
            try
            {
                var path = PathFor(account);
                if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
            }
            catch { }
        }
    }
}
