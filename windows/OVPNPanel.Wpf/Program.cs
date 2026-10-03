using System;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Microsoft.Win32;
using OVPNPanel.Core;
using OVPNPanel.Theme;

namespace OVPNPanel
{
    public static class Program
    {
        [STAThread]
        public static void Main()
        {
            AppDomain.CurrentDomain.UnhandledException += (s, e) => LogCrash(e.ExceptionObject as Exception);
            try
            {
                Trace("main:enter");
                AppTheme.Apply(IsSystemDark());
                Trace("main:theme");
                var app = new Application
                {
                    ShutdownMode = ShutdownMode.OnMainWindowClose,
                };
                app.DispatcherUnhandledException += (s, e) =>
                {
                    LogCrash(e.Exception);
                    e.Handled = true;
                };
                Ui.Post(() => { });
                Trace("main:window");
                app.Run(new MainWindow());
                Trace("main:exit");
            }
            catch (Exception error)
            {
                LogCrash(error);
                throw;
            }
        }

        /// <summary>启动阶段埋点（配合 crash.log 定位启动异常）</summary>
        internal static void Trace(string message)
        {
            try
            {
                var path = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "trace.log");
                System.IO.File.AppendAllText(path, DateTime.Now.ToString("HH:mm:ss.fff") + " " + message + Environment.NewLine);
            }
            catch { }
        }

        /// <summary>崩溃日志（CI / 用户排障用）：写入程序目录下的 crash.log</summary>
        internal static void LogCrash(Exception error)
        {
            try
            {
                var path = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "crash.log");
                System.IO.File.AppendAllText(path,
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + Environment.NewLine
                    + (error == null ? "(unknown)" : error.ToString()) + Environment.NewLine + Environment.NewLine);
            }
            catch { }
        }

        /// <summary>读取 Windows 应用主题（Win7 无此设置时按亮色处理）</summary>
        static bool IsSystemDark()
        {
            var forced = LaunchArgs.Value("-theme");
            if (forced == "dark") return true;
            if (forced == "light") return false;
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                {
                    if (key == null) return false;
                    var value = key.GetValue("AppsUseLightTheme");
                    if (value == null) return false;
                    return Convert.ToInt32(value) == 0;
                }
            }
            catch { return false; }
        }
    }

    /// <summary>主窗口：桌面版式（左侧导航 + 居中内容列），配色与功能与移动端保持一致</summary>
    public class MainWindow : Window
    {
        readonly MainShell _shell;

        public MainWindow()
        {
            Title = "OVPN 面板";
            Width = DS.Size.WindowWidth;
            Height = DS.Size.WindowHeight;
            MinWidth = 860;
            MinHeight = 640;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = Ui.B(AppTheme.Palette.Background);
            UseLayoutRounding = true;
            SnapsToDevicePixels = true;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);

            _shell = new MainShell();
            OVPNPanel.Program.Trace("window:shell-built");
            Content = _shell;

            ApplyWindowSizeOverride();
            PreviewKeyDown += OnPreviewKeyDown;
            OVPNPanel.Program.Trace("window:ready");
        }

        /// <summary>CI 截图用：-shot &lt;路径&gt; 时把窗口内容渲染为 PNG 后退出</summary>
        protected override void OnContentRendered(EventArgs e)
        {
            base.OnContentRendered(e);
            var shot = LaunchArgs.Value("-shot");
            if (string.IsNullOrEmpty(shot)) return;
            int delay = 2000;
            int parsed;
            if (int.TryParse(LaunchArgs.Value("-shotDelay"), out parsed) && parsed > 0) delay = parsed;
            var timer = new System.Windows.Threading.DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(delay),
            };
            timer.Tick += (s, args) =>
            {
                timer.Stop();
                CaptureTo(shot);
                Application.Current.Shutdown();
            };
            timer.Start();
        }

        void CaptureTo(string path)
        {
            try
            {
                int w = (int)Math.Ceiling(ActualWidth);
                int h = (int)Math.Ceiling(ActualHeight);
                if (w <= 0 || h <= 0) return;
                var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap(
                    w, h, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(this);
                var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
                encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
                using (var stream = System.IO.File.Create(path))
                {
                    encoder.Save(stream);
                }
                OVPNPanel.Program.Trace("window:shot " + path);
            }
            catch (Exception error)
            {
                OVPNPanel.Program.LogCrash(error);
            }
        }

        /// <summary>CI 截图用：-winSize 420,700 指定窗口尺寸（正常启动不生效）</summary>
        void ApplyWindowSizeOverride()
        {
            var raw = LaunchArgs.Value("-winSize");
            if (string.IsNullOrEmpty(raw)) return;
            var parts = raw.Split(',', 'x', 'X');
            double width, height;
            if (parts.Length == 2
                && double.TryParse(parts[0], out width)
                && double.TryParse(parts[1], out height))
            {
                Width = width;
                Height = height;
            }
        }

        void OnPreviewKeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape || e.Key == Key.Back)
            {
                _shell.HandleBack();
                e.Handled = true;
            }
        }
    }
}
