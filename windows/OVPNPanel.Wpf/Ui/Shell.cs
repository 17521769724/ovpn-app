using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using OVPNPanel.Theme;

namespace OVPNPanel.Core
{
    /// <summary>页面基类：每个页面自行绘制内容，由 NavHost 负责堆栈与头部导航</summary>
    public abstract class Screen : UserControl
    {
        /// <summary>push 到导航栈后显示的标题（返回栏使用）</summary>
        public string Title = "";
        /// <summary>是否隐藏系统返回栏（根页面自带大标题）</summary>
        public bool HidesHeader = true;

        public NavHost NavHost;

        public virtual void OnAppear() { }
        public virtual void Refresh() { }
        /// <summary>返回键处理；返回 true 表示已消费</summary>
        public virtual bool OnBack() { return false; }

        protected void Push(Screen screen)
        {
            if (NavHost != null) NavHost.Push(screen);
        }

        protected void Pop()
        {
            if (NavHost != null) NavHost.Pop();
        }

        protected static AppState App { get { return AppState.Shared; } }
        protected static VpnManager Vpn { get { return VpnManager.Shared; } }
    }

    /// <summary>导航容器：支持 push / pop，并为非根页面绘制统一返回栏</summary>
    public class NavHost : Grid
    {
        readonly List<Screen> _stack = new List<Screen>();
        readonly Grid _host = new Grid();

        public NavHost()
        {
            Children.Add(_host);
        }

        public Screen Top { get { return _stack.Count > 0 ? _stack[_stack.Count - 1] : null; } }
        public bool CanPop { get { return _stack.Count > 1; } }

        public void SetRoot(Screen screen)
        {
            _stack.Clear();
            _stack.Add(screen);
            screen.NavHost = this;
            Show(screen, false);
            screen.OnAppear();
        }

        public void Push(Screen screen)
        {
            if (Top != null) Top.Refresh();
            _stack.Add(screen);
            screen.NavHost = this;
            Show(screen, true);
            screen.OnAppear();
        }

        public void Pop()
        {
            if (!CanPop) return;
            var leaving = _stack[_stack.Count - 1];
            _stack.RemoveAt(_stack.Count - 1);
            var next = Top;
            Show(next, true, true);
            next.OnAppear();
            GC.KeepAlive(leaving);
        }

        void Show(Screen screen, bool animated, bool backwards = false)
        {
            _host.Children.Clear();
            var page = new Grid();
            if (!screen.HidesHeader)
            {
                page.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                page.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
                var header = BuildHeader(screen);
                Grid.SetRow(header, 0);
                page.Children.Add(header);
                Grid.SetRow(screen, 1);
            }
            page.Children.Add(screen);
            _host.Children.Add(page);

            if (!animated) return;
            var translate = new TranslateTransform(backwards ? -32 : 40, 0);
            page.RenderTransform = translate;
            page.Opacity = 0;
            translate.BeginAnimation(TranslateTransform.XProperty,
                new DoubleAnimation(0, TimeSpan.FromMilliseconds(220)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
            page.BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(200)));
        }

        UIElement BuildHeader(Screen screen)
        {
            var back = Ui.Icon("chevronLeft", 18, Ui.P.Primary, 2.2);
            var backSurface = new PressSurface { Width = 44, Height = 44, Child = new Grid { Children = { back } } };
            backSurface.Clicked += Pop;

            var title = Ui.Text(screen.Title, 16, FontWeights.SemiBold, Ui.P.Foreground);
            title.HorizontalAlignment = HorizontalAlignment.Center;
            title.VerticalAlignment = VerticalAlignment.Center;

            var grid = new Grid { Height = 48, Background = Ui.B(Ui.P.Background) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetColumn(backSurface, 0); grid.Children.Add(backSurface);
            Grid.SetColumn(title, 1); grid.Children.Add(title);
            var line = new Rectangle { Height = 1, Fill = Ui.B(Ui.P.Border), VerticalAlignment = VerticalAlignment.Bottom };
            Grid.SetColumn(line, 0); Grid.SetColumnSpan(line, 2); grid.Children.Add(line);
            return grid;
        }
    }

    /// <summary>应用外壳：阶段路由（配置 / 登录 / 主界面）+ 自定义底部导航 + 全局横幅</summary>
    public class MainShell : Grid
    {
        public static MainShell Current;

        readonly AppState _state = AppState.Shared;
        readonly Grid _root = new Grid();
        readonly ToastHost _toast;
        readonly SheetHost _sheet;
        readonly AlertHost _alert;

        AppPhase _builtPhase = (AppPhase)(-1);
        Navigation _setup;
        Navigation _auth;
        TabsView _tabs;

        public MainShell()
        {
            Current = this;
            Background = Ui.B(Ui.P.Background);
            Children.Add(_root);

            _sheet = new SheetHost();
            Children.Add(_sheet);

            _alert = new AlertHost();
            Children.Add(_alert);

            _toast = new ToastHost(_state)
            {
                VerticalAlignment = VerticalAlignment.Top,
                HorizontalAlignment = HorizontalAlignment.Stretch,
            };
            Children.Add(_toast);

            _state.StateChanged += OnStateChanged;
            VpnManager.Shared.Changed += OnVpnChanged;
            OVPNPanel.Program.Trace("shell:pre-build");
            Build();
            OVPNPanel.Program.Trace("shell:built");
        }

        public SheetHost Sheet { get { return _sheet; } }
        public AlertHost Alert { get { return _alert; } }

        /// <summary>从任意位置弹出底部浮层（对应 iOS 的 .sheet）</summary>
        public static void PresentSheet(string title, UIElement content, Action onClose = null)
        {
            var shell = Current;
            if (shell != null) shell._sheet.Present(title, content, onClose);
        }

        /// <summary>居中确认框（对应 iOS 的 .alert）</summary>
        public static void PresentAlert(string title, string message, string confirmText,
            Action onConfirm, bool destructive = false, string cancelText = "取消")
        {
            var shell = Current;
            if (shell != null) shell._alert.Present(title, message, confirmText, onConfirm, destructive, cancelText);
        }


        void OnStateChanged()
        {
            if (_state.Phase != _builtPhase) Build();
            else RefreshVisible();
        }

        void OnVpnChanged()
        {
            RefreshVisible();
        }

        void RefreshVisible()
        {
            var top = _tabs != null ? _tabs.CurrentTop : null;
            if (top != null) top.Refresh();
        }

        void Build()
        {
            _builtPhase = _state.Phase;
            _root.Children.Clear();
            switch (_state.Phase)
            {
                case AppPhase.Setup:
                    if (_setup == null) _setup = new Navigation(() => new SetupView());
                    _root.Children.Add(_setup);
                    _setup.Top.Refresh();
                    break;
                case AppPhase.Auth:
                    if (_auth == null) _auth = new Navigation(() => new LoginView());
                    _root.Children.Add(_auth);
                    _auth.Top.Refresh();
                    break;
                default:
                    if (_tabs == null) _tabs = new TabsView();
                    _root.Children.Add(_tabs);
                    _tabs.RefreshCurrent();
                    break;
            }
        }

        /// <summary>返回键：先关浮层，再逐级返回</summary>
        public void HandleBack()
        {
            if (_alert.IsOpen) { _alert.Dismiss(); return; }
            if (_sheet.IsOpen) { _sheet.Dismiss(); return; }
            if (_tabs != null && _state.Phase == AppPhase.Main && _tabs.CanPop) { _tabs.Pop(); return; }
        }
    }

    /// <summary>单页导航（用于配置页 / 登录页这类内部也会 push 的场景）</summary>
    public class Navigation : Grid
    {
        readonly NavHost _host = new NavHost();
        readonly Func<Screen> _factory;
        Screen _root;

        public Navigation(Func<Screen> factory)
        {
            _factory = factory;
            Children.Add(_host);
            _root = factory();
            _host.SetRoot(_root);
        }

        public Screen Top { get { return _host.Top; } }
    }

    /// <summary>主界面：底部四个 Tab，各自维护独立导航栈</summary>
    public class TabsView : Grid
    {
        readonly Grid _content = new Grid();
        readonly Dictionary<int, NavHost> _hosts = new Dictionary<int, NavHost>();
        readonly List<Border> _tabSurfaces = new List<Border>();
        readonly List<Path> _tabIcons = new List<Path>();
        readonly List<TextBlock> _tabLabels = new List<TextBlock>();
        readonly StackPanel _tabBar;
        int _current = LaunchArgs.StartTab;

        static readonly string[] Titles = { "线路", "套餐", "邀请", "我的" };
        static readonly string[] IconNames = { "tabLines", "tabPlans", "tabInvite", "tabProfile" };
        static readonly Color[] Colors = { DS.IconColor.Green, DS.IconColor.Teal, DS.IconColor.Lime, DS.IconColor.Cyan };

        public TabsView()
        {
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            Grid.SetRow(_content, 0);
            Children.Add(_content);

            _tabBar = Ui.Stack(Orientation.Horizontal, 0);
            _tabBar.Background = Ui.B(Ui.P.Background);
            var barBorder = new Border { Child = _tabBar };
            var line = new Rectangle { Height = 1, Fill = Ui.B(Ui.P.Border), VerticalAlignment = VerticalAlignment.Top };
            var barGrid = new Grid { Children = { barBorder, line } };
            Grid.SetRow(barGrid, 1);
            Children.Add(barGrid);

            BuildTabs();
            Select(_current, false);
        }

        void BuildTabs()
        {
            var palette = Ui.P;
            for (int i = 0; i < Titles.Length; i++)
            {
                int index = i;
                var icon = Ui.Icon(IconNames[i], 19, palette.MutedForeground, 1.8);
                icon.HorizontalAlignment = HorizontalAlignment.Center;
                var label = Ui.Text(Titles[i], 11, FontWeights.Normal, palette.MutedForeground);
                label.HorizontalAlignment = HorizontalAlignment.Center;
                label.Margin = new Thickness(0, 3, 0, 0);

                var stack = Ui.Stack(Orientation.Vertical, 0, icon, label);
                stack.HorizontalAlignment = HorizontalAlignment.Center;
                stack.VerticalAlignment = VerticalAlignment.Center;

                var surface = new PressSurface
                {
                    Child = stack,
                    Height = DS.Size.TabBarHeight,
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    Width = DS.Size.ContentMaxWidth / 4.0,
                };
                surface.Clicked += () => Select(index, true);
                _tabSurfaces.Add(surface);
                _tabIcons.Add(icon);
                _tabLabels.Add(label);
                _tabBar.Children.Add(surface);
            }
        }

        public Screen CurrentTop
        {
            get
            {
                NavHost host;
                return _hosts.TryGetValue(_current, out host) ? host.Top : null;
            }
        }

        public bool CanPop
        {
            get
            {
                NavHost host;
                return _hosts.TryGetValue(_current, out host) && host.CanPop;
            }
        }

        public void Pop()
        {
            NavHost host;
            if (_hosts.TryGetValue(_current, out host)) host.Pop();
        }

        public void RefreshCurrent()
        {
            var top = CurrentTop;
            if (top != null) top.Refresh();
        }

        void Select(int index, bool animated)
        {
            _current = index;
            var palette = Ui.P;
            for (int i = 0; i < _tabSurfaces.Count; i++)
            {
                bool active = i == index;
                _tabIcons[i].Stroke = Ui.B(active ? Colors[i] : palette.MutedForeground);
                _tabIcons[i].StrokeThickness = active ? 2.2 : 1.8;
                _tabLabels[i].Foreground = Ui.B(active ? palette.Foreground : palette.MutedForeground);
                _tabLabels[i].FontWeight = active ? FontWeights.SemiBold : FontWeights.Normal;
                var scale = active ? 1.06 : 1.0;
                if (animated)
                {
                    var transform = _tabIcons[i].RenderTransform as ScaleTransform ?? new ScaleTransform(1, 1);
                    _tabIcons[i].RenderTransformOrigin = new Point(0.5, 0.5);
                    _tabIcons[i].RenderTransform = transform;
                    Ui.Animate(transform, ScaleTransform.ScaleXProperty, scale, TimeSpan.FromMilliseconds(180));
                    Ui.Animate(transform, ScaleTransform.ScaleYProperty, scale, TimeSpan.FromMilliseconds(180));
                }
            }

            _content.Children.Clear();
            NavHost host;
            if (!_hosts.TryGetValue(index, out host))
            {
                host = new NavHost();
                host.SetRoot(CreateRoot(index));
                _hosts[index] = host;
            }
            _content.Children.Add(host);
            var top = host.Top;
            top.OnAppear();
            top.Refresh();

            if (animated)
            {
                host.Opacity = 0;
                host.BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(160)));
            }
        }

        static Screen CreateRoot(int index)
        {
            switch (index)
            {
                case 0: return new HomeView();
                case 1: return new PlansView();
                case 2: return new InviteView();
                default: return new ProfileView();
            }
        }
    }
}
