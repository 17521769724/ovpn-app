using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using OVPNPanel.Theme;

namespace OVPNPanel.Core
{
    /// <summary>
    /// 线路页（对应 iOS HomeView）：
    /// 选择服务器 → 选择线路 → 连接；连接中 / 已连接时整页切换为彩色泡泡圆环状态页。
    /// </summary>
    public class HomeView : Screen
    {
        // 选择流程
        LinesPayload _payload;
        bool _loading = true;
        int? _selectedNodeId;
        int? _selectedLineId;
        string _category = "全部";
        string _connectingFamily;
        bool _showServerPicker;
        bool _attemptActive;

        // 当前会话的实时网速与流量（每次重新连接都会重新计数）
        long _sessionRx;
        long _sessionTx;
        double _downSpeed;
        double _upSpeed;
        DateTime? _connectedSince;
        Sample _lastSample;
        System.Threading.CancellationTokenSource _statsCts;

        // 首次连接时保存登录密码
        LineConfig _pendingProfile;
        bool _savingPassword;
        TextFieldControl _passwordField;
        Grid _sheetButtonHost;

        // 生命周期
        bool _didInitialLoad;
        bool _vpnSubscribed;
        VpnStatus _lastStatus = VpnStatus.Invalid;
        DispatcherTimer _clockTimer;
        DispatcherTimer _liveTimer;

        // 连接状态页中的可变控件（就地刷新，避免整页重建打断圆环动画）
        readonly ConnectRing _ring = new ConnectRing(224);
        TextBlock _downValue;
        TextBlock _upValue;
        TextBlock _trafficTotal;
        TextBlock _trafficRx;
        TextBlock _trafficTx;

        sealed class Sample
        {
            public long Rx;
            public long Tx;
            public DateTime At;
        }

        public HomeView()
        {
            HidesHeader = true;
            Content = new Grid();
        }

        // MARK: - 生命周期

        public override void OnAppear()
        {
            if (!_vpnSubscribed)
            {
                VpnManager.Shared.Changed += OnVpnChanged;
                _vpnSubscribed = true;
            }
            _lastStatus = Vpn.Status;
            StartTimers();
            if (!_didInitialLoad)
            {
                _didInitialLoad = true;
                Ui.Fire(InitAsync);
            }
            Rebuild();
        }

        public override void Refresh()
        {
            Rebuild();
        }

        async System.Threading.Tasks.Task InitAsync()
        {
            await Vpn.Prepare();
            await Load(false);
            // 冷启动时隧道可能已建立：直接进入已连接状态（含计时与实时统计）
            if (Vpn.Status == VpnStatus.Connected)
            {
                if (SessionStart() == null) _connectedSince = DateTime.Now;
                StartStats();
            }
        }

        void StartTimers()
        {
            if (_clockTimer == null)
            {
                // 每秒心跳：驱动连接时长计时的刷新
                _clockTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
                _clockTimer.Tick += (s, e) => ClockTick();
                _clockTimer.Start();
            }
            if (_liveTimer == null)
            {
                // 服务器列表「实时」数据自动刷新（带宽 / 负载 / 在线数）
                _liveTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(10) };
                _liveTimer.Tick += (s, e) => LiveTick();
                _liveTimer.Start();
            }
        }

        void ClockTick()
        {
            if (SessionStart() == null || _ring == null) return;
            _ring.SetState(Vpn.Status, DurationText());
        }

        void LiveTick()
        {
            if (ConnectionActive() || _loading || _payload == null) return;
            Ui.Fire(() => Load(false));
        }

        // MARK: - 状态

        ServerNode SelectedNode()
        {
            if (!_selectedNodeId.HasValue || _payload == null) return null;
            foreach (var node in _payload.Nodes) if (node.Id == _selectedNodeId.Value) return node;
            return null;
        }

        VPNLine SelectedLine()
        {
            if (!_selectedLineId.HasValue || _payload == null) return null;
            foreach (var line in _payload.Lines) if (line.Id == _selectedLineId.Value) return line;
            return null;
        }

        List<string> Categories()
        {
            var list = new List<string> { "全部" };
            if (_payload == null) return list;
            if (_payload.Categories != null && _payload.Categories.Count > 0)
            {
                foreach (var name in _payload.Categories)
                    if (!string.IsNullOrEmpty(name) && !list.Contains(name)) list.Add(name);
                return list;
            }
            foreach (var line in _payload.Lines)
                if (!list.Contains(line.Category)) list.Add(line.Category);
            return list;
        }

        List<VPNLine> VisibleLines()
        {
            var result = new List<VPNLine>();
            if (_payload == null) return result;
            if (_category == "全部") return _payload.Lines;
            foreach (var line in _payload.Lines) if (line.Category == _category) result.Add(line);
            return result;
        }

        /// <summary>未选服务器，或用户主动点「更换服务器」时展示服务器列表</summary>
        bool ShowingServerPicker()
        {
            return SelectedNode() == null || _showServerPicker;
        }

        /// <summary>连接中 / 已连接 / 正在断开：整页切换为连接状态页</summary>
        bool ConnectionActive()
        {
            var status = Vpn.Status;
            return status == VpnStatus.Connecting || status == VpnStatus.Connected
                || status == VpnStatus.Reasserting || status == VpnStatus.Disconnecting;
        }

        DateTime? SessionStart()
        {
            return Vpn.ConnectedAt ?? _connectedSince;
        }

        string DurationText()
        {
            var start = SessionStart();
            if (start == null) return "--:--";
            var span = DateTime.Now - start.Value;
            if (span.TotalSeconds < 0) span = TimeSpan.Zero;
            return Format.Duration(span);
        }

        // MARK: - 页面重建

        void Rebuild()
        {
            Ui.Post(RebuildNow);
        }

        void RebuildNow()
        {
            Content = ConnectionActive() ? BuildConnectionPage() : BuildSelectionPage();
        }

        // MARK: - 选择流程（服务器 → 线路）

        UIElement BuildSelectionPage()
        {
            bool showPicker = ShowingServerPicker();
            var content = Ui.Stack(Orientation.Vertical, DS.Size.GapLarge);
            content.Margin = new Thickness(0, 8, 0, 16);

            content.AddRow(PageTitle("线路连接"), DS.Size.GapLarge);
            content.AddRow(BuildStepHint(showPicker), DS.Size.GapLarge);

            if (_payload != null)
            {
                if (_payload.Quota == null || !_payload.Quota.Valid)
                {
                    var msg = (_payload.Quota != null && !string.IsNullOrEmpty(_payload.Quota.Reason))
                        ? _payload.Quota.Reason : "订阅状态异常，暂时无法连接";
                    content.AddRow(C.BannerBar(msg), DS.Size.GapLarge);
                }
                else
                {
                    var limit = "订阅正常｜限速 " + Format.Speed(_payload.SpeedLimitKbps) + "｜设备上限 "
                                + (_payload.DeviceLimit > 0 ? _payload.DeviceLimit + " 台" : "不限");
                    content.AddRow(C.BannerBar(limit, BannerKind.Success), DS.Size.GapLarge);
                }
            }

            if (_loading && _payload == null)
                content.AddRow(C.LoadingBlock("正在获取服务器与线路…"), DS.Size.GapLarge);
            else if (showPicker)
                content.AddRow(BuildServerSection(), DS.Size.GapLarge);
            else
                content.AddRow(BuildLineSection(), DS.Size.GapLarge);

            content.AddRow(new Grid { Height = 12 }, DS.Size.GapLarge);

            // 下拉刷新：重新选择线路，底部连接栏随之收起（对应 iOS .refreshable）
            var scroller = new RefreshableScrollViewer { Content = Ui.Centered(Ui.Page(content)) };
            scroller.OnRefresh = () => Ui.Fire(() => Load(true));
            UIElement scroll = scroller;
            var node = SelectedNode();
            var line = SelectedLine();
            if (node != null && line != null)
            {
                var grid = new Grid();
                grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
                grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                Grid.SetRow(scroll, 0);
                grid.Children.Add(scroll);
                var bar = BuildBottomBar(node, line);
                Grid.SetRow(bar, 1);
                grid.Children.Add(bar);
                return grid;
            }
            return scroll;
        }

        UIElement BuildStepHint(bool showPicker)
        {
            var row = Ui.Stack(Orientation.Horizontal, 8);
            row.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(StepBadge(showPicker ? "1" : "2", Ui.P.Primary));
            row.Children.Add(Ui.Caption(showPicker ? "第 1 步" : "第 2 步"));
            row.Children.Add(Ui.VLine(10));
            row.Children.Add(Ui.Caption(showPicker ? "选择服务器" : "选择线路并连接"));

            FrameworkElement right = null;
            if (_payload != null && _payload.Level > 0)
                right = C.StatusBadge("Lv." + _payload.Level, Ui.Alpha(DS.IconColor.Teal, 0.14), DS.IconColor.Teal);
            return Ui.Split(row, right);
        }

        // MARK: - 服务器列表

        UIElement BuildServerSection()
        {
            var stack = Ui.Stack(Orientation.Vertical, DS.Size.Gap);
            var count = _payload != null ? _payload.Nodes.Count : 0;
            FrameworkElement right = null;
            if (SelectedNode() != null)
            {
                right = Pill("返回线路", "chevronLeft", Ui.P.Primary,
                    Ui.B(Ui.Alpha(Ui.P.Primary, 0.14)), () =>
                    {
                        _showServerPicker = false;
                        _selectedLineId = null;
                        Rebuild();
                    });
            }
            stack.AddRow(Ui.Split(C.SectionHeader("选择服务器", "显示实时状态与负载，共 " + count + " 台"), right), DS.Size.Gap);

            var nodes = _payload != null ? _payload.Nodes : null;
            if (nodes != null && nodes.Count == 0)
            {
                stack.AddRow(C.EmptyHint("server", "暂无可用服务器", "请联系管理员添加节点"), DS.Size.Gap);
            }
            else if (nodes != null)
            {
                foreach (var node in nodes) stack.AddRow(BuildServerCard(node), DS.Size.Gap);
            }
            return stack;
        }

        UIElement BuildServerCard(ServerNode node)
        {
            bool isSelected = _selectedNodeId.HasValue && node.Id == _selectedNodeId.Value;
            bool online = node.Status == "online";

            var inner = Ui.Stack(Orientation.Vertical, 10);

            var left = Ui.Stack(Orientation.Horizontal, 10);
            left.Children.Add(Ui.IconTile(online ? "server" : "cloudOff",
                online ? DS.IconColor.Green : DS.IconColor.Slate));
            var texts = Ui.Stack(Orientation.Vertical, 3);
            var nameRow = Ui.Stack(Orientation.Horizontal, 6);
            nameRow.Children.Add(Ui.Text(node.Name, DS.FontSize.Section, FontWeights.SemiBold, Ui.P.Foreground));
            if (node.DcoEnabled)
                nameRow.Children.Add(C.StatusBadge("DCO", Ui.P.OnlineBg, Ui.P.OnlineText));
            texts.Children.Add(nameRow);
            if (!string.IsNullOrEmpty(node.Region)) texts.Children.Add(Ui.Caption(node.Region));
            left.Children.Add(texts);
            inner.AddRow(Ui.Split(left, C.NodeStatusBadge(node.Status)), 10);

            // 服务器离线时隐藏地址（避免暴露不可达的地址）
            var showAddress = online;
            if (showAddress && (node.DisplayIPv4 != null || node.DisplayIPv6 != null))
            {
                var address = Ui.Stack(Orientation.Vertical, 5);
                if (node.DisplayIPv4 != null) address.Children.Add(AddressRow("IPv4", node.DisplayIPv4, DS.IconColor.Green));
                if (node.DisplayIPv6 != null) address.Children.Add(AddressRow("IPv6", node.DisplayIPv6, DS.IconColor.Teal));
                inner.AddRow(Ui.Box(address, Ui.Alpha(Ui.P.Muted, 0.5), DS.Radius.Md, null, 0, new Thickness(10, 7, 10, 7)), 10);
            }

            inner.AddRow(Columns(0,
                MetricCell("在线人数", node.OnlineCount.ToString()),
                MetricCell("流量倍率", "×" + node.Ratio.ToString("F2", System.Globalization.CultureInfo.InvariantCulture)),
                MetricCell("等级要求", "Lv." + node.LevelRequired)), 10);

            var stats = Ui.Stack(Orientation.Vertical, 6);
            stats.Children.Add(C.StatBar("CPU", node.CpuUsage, "gear"));
            stats.Children.Add(C.StatBar("内存", node.MemUsage, "server"));
            stats.Children.Add(C.StatBar("磁盘", node.DiskUsage, "doc"));
            inner.AddRow(stats, 10);

            var footerLeft = Ui.Stack(Orientation.Horizontal, 7);
            footerLeft.Children.Add(Ui.Caption("实时"));
            footerLeft.Children.Add(Ui.Text("↑ " + Format.Bytes(node.RxRateValue) + "/s", DS.FontSize.Caption, FontWeights.Normal, DS.IconColor.Green));
            footerLeft.Children.Add(Ui.VLine(10));
            footerLeft.Children.Add(Ui.Text("↓ " + Format.Bytes(node.TxRateValue) + "/s", DS.FontSize.Caption, FontWeights.Normal, DS.IconColor.Teal));
            FrameworkElement footerRight = null;
            if (!node.Usable) footerRight = Ui.Text(node.UnusableReason, DS.FontSize.Caption, FontWeights.Normal, Ui.P.OfflineText);
            else if (isSelected) footerRight = Ui.Text("已选择", DS.FontSize.Caption, FontWeights.Normal, Ui.P.OnlineText);
            inner.AddRow(Ui.Split(footerLeft, footerRight), 10);

            var card = C.Card(inner, DS.Size.CardPadding, node.Usable ? (Color?)null : Ui.P.Muted);
            var grid = Overlay(card, isSelected ? Ui.P.Primary : (Color?)null, 1.5);
            grid.Opacity = node.Usable ? 1 : 0.8;
            if (node.Usable)
            {
                grid.Background = Brushes.Transparent;
                grid.Clickable(() =>
                {
                    _selectedNodeId = node.Id;
                    _selectedLineId = null;
                    _showServerPicker = false;
                    Rebuild();
                }, 0.98);
            }
            return grid;
        }

        // MARK: - 线路列表

        UIElement BuildLineSection()
        {
            var stack = Ui.Stack(Orientation.Vertical, DS.Size.Gap);

            var node = SelectedNode();
            if (node != null)
            {
                var left = Ui.Stack(Orientation.Horizontal, 10);
                left.Children.Add(Ui.IconTile("server", DS.IconColor.Green, 38));
                var texts = Ui.Stack(Orientation.Vertical, 3);
                texts.Children.Add(Ui.Text(node.Name, DS.FontSize.Section, FontWeights.SemiBold, Ui.P.Foreground));
                if (node.Status == "online")
                {
                    var address = Ui.Stack(Orientation.Horizontal, 6);
                    if (node.DisplayIPv4 != null) address.Children.Add(Ui.Caption(node.DisplayIPv4));
                    if (node.DisplayIPv4 != null && node.DisplayIPv6 != null) address.Children.Add(Ui.VLine(9));
                    if (node.DisplayIPv6 != null) address.Children.Add(Ui.Caption(node.DisplayIPv6));
                    if (address.Children.Count > 0) texts.Children.Add(address);
                }
                left.Children.Add(texts);

                var change = Pill("更换", "refresh", Colors.White, Ui.P.AccentGradient, () =>
                {
                    _showServerPicker = true;
                    _selectedLineId = null;
                    Rebuild();
                });
                stack.AddRow(Ui.Box(Ui.Split(left, change), Ui.Alpha(Ui.P.Muted, 0.5), DS.Radius.Xl, null, 0, new Thickness(10)), DS.Size.Gap);
            }

            var categories = Categories();
            if (categories.Count > 1)
            {
                var grid = new Grid();
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                var leftChips = Ui.Stack(Orientation.Horizontal, 8);
                leftChips.VerticalAlignment = VerticalAlignment.Center;
                leftChips.Children.Add(C.Chip("全部", _category == "全部", () => { _category = "全部"; Rebuild(); }));
                leftChips.Children.Add(Ui.VLine(16));
                Grid.SetColumn(leftChips, 0);
                grid.Children.Add(leftChips);

                var inner = Ui.Stack(Orientation.Horizontal, 8);
                inner.Margin = new Thickness(1, 0, 1, 0);
                for (int i = 1; i < categories.Count; i++)
                {
                    var item = categories[i];
                    inner.Children.Add(C.Chip(item, item == _category, () => { _category = item; Rebuild(); }));
                }
                var scroller = new ScrollViewer
                {
                    HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                    VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
                    Content = inner,
                    Focusable = false,
                    Margin = new Thickness(8, 0, 0, 0),
                    VerticalAlignment = VerticalAlignment.Center,
                };
                Grid.SetColumn(scroller, 1);
                grid.Children.Add(scroller);
                stack.AddRow(grid, DS.Size.Gap);
            }

            var subtitle = (node != null && node.SupportsIPv6)
                ? "该服务器支持 IPv6，选好路线后可分别用 IPv4 / IPv6 连接"
                : "点击线路卡片后使用底部「连接」按钮";
            stack.AddRow(C.SectionHeader("选择线路", subtitle), DS.Size.Gap);

            var lines = VisibleLines();
            if (lines.Count == 0)
            {
                stack.AddRow(C.EmptyHint("globe", "暂无可用的线路", "线路正在维护或尚未配置"), DS.Size.Gap);
            }
            else
            {
                foreach (var line in lines) stack.AddRow(BuildLineCard(line), DS.Size.Gap);
            }
            return stack;
        }

        UIElement BuildLineCard(VPNLine line)
        {
            bool isSelected = _selectedLineId.HasValue && line.Id == _selectedLineId.Value;
            bool isUDP = (line.Protocol ?? "").ToLowerInvariant() == "udp";
            var accent = isUDP ? DS.IconColor.Amber : DS.IconColor.TealDeep;

            var inner = Ui.Stack(Orientation.Vertical, 8);

            var top = Ui.Stack(Orientation.Horizontal, 10);
            top.Children.Add(Ui.IconTile(isUDP ? "bolt" : "shield", accent));
            top.Children.Add(Ui.Text(line.Name, DS.FontSize.Section, FontWeights.SemiBold, Ui.P.Foreground));
            inner.AddRow(Ui.Split(top, C.StatusBadge(line.ProtocolUpper, Ui.Alpha(accent, 0.14), accent)), 8);

            if (!string.IsNullOrEmpty(line.Remark))
                inner.AddRow(Ui.Text(line.Remark, DS.FontSize.Caption, FontWeights.Normal, Ui.P.SecondaryText, TextWrapping.Wrap), 8);

            inner.AddRow(Ui.Split(
                Ui.Caption("协议 / 端口"),
                Ui.Text(line.ProtocolUpper + " " + line.Port, DS.FontSize.Section, FontWeights.SemiBold, Ui.P.Foreground)), 8);

            var node = SelectedNode();
            inner.AddRow(Ui.Split(
                Ui.Caption("服务器"),
                Ui.Text(node != null ? node.Name : "-", DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.Foreground)), 8);

            var card = C.Card(inner);
            var grid = Overlay(card, isSelected ? Ui.P.Primary : (Color?)null, 1.5);
            grid.Background = Brushes.Transparent;
            grid.Clickable(() => { _selectedLineId = line.Id; Rebuild(); }, 0.98);
            return grid;
        }

        // MARK: - 底部连接栏

        UIElement BuildBottomBar(ServerNode node, VPNLine line)
        {
            var stack = Ui.Stack(Orientation.Vertical, 8);

            var infoRow = Ui.Stack(Orientation.Horizontal, 8);
            infoRow.Children.Add(Ui.Text(node.Name, DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.SecondaryText));
            infoRow.Children.Add(Ui.VLine(10));
            infoRow.Children.Add(Ui.Text(line.Name, DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.SecondaryText));
            stack.AddRow(Ui.Split(infoRow, Ui.Caption(line.ProtocolUpper + " " + line.Port)), 8);

            var buttons = new Grid();
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            if (node.SupportsIPv6)
            {
                var v4 = C.Button("IPv4 连接", () => Ui.Fire(() => Connect("v4")), BtnStyle.Primary, "globe",
                    DS.Size.ButtonHeight, _connectingFamily == "v4", !node.SupportsIPv4 || _connectingFamily == "v6");
                var v6 = C.Button("IPv6 连接", () => Ui.Fire(() => Connect("v6")), BtnStyle.Accent, "globe",
                    DS.Size.ButtonHeight, _connectingFamily == "v6", !node.SupportsIPv6 || _connectingFamily == "v4");
                v4.Margin = new Thickness(0, 0, 5, 0);
                v6.Margin = new Thickness(5, 0, 0, 0);
                Grid.SetColumn(v4, 0); buttons.Children.Add(v4);
                Grid.SetColumn(v6, 1); buttons.Children.Add(v6);
            }
            else
            {
                var single = C.Button(_connectingFamily == "v4" ? "正在准备线路…" : "连接",
                    () => Ui.Fire(() => Connect("v4")), BtnStyle.Primary, "bolt",
                    DS.Size.ButtonHeight, _connectingFamily == "v4", false);
                Grid.SetColumn(single, 0);
                Grid.SetColumnSpan(single, 2);
                buttons.Children.Add(single);
            }
            stack.AddRow(buttons, 8);

            stack.Margin = new Thickness(DS.Size.PagePadding, 10, DS.Size.PagePadding, 8);
            var wrap = new Border { Child = stack, Background = Ui.B(Ui.P.Background) };
            var container = new Grid { Children = { wrap } };
            container.Children.Add(new Rectangle
            {
                Height = 1,
                Fill = Ui.B(Ui.P.Border),
                VerticalAlignment = VerticalAlignment.Top,
            });
            return Ui.Centered(container);
        }

        // MARK: - 连接状态页

        UIElement BuildConnectionPage()
        {
            var content = Ui.Stack(Orientation.Vertical, 18);
            content.Margin = new Thickness(0, 0, 0, 24);

            content.AddRow(PageTitle("线路连接"), 18);

            _ring.SetState(Vpn.Status, DurationText());
            var ringWrap = new Grid { Children = { _ring } };
            ringWrap.Margin = new Thickness(0, 12, 0, 0);
            content.AddRow(ringWrap, 18);

            content.AddRow(Columns(DS.Size.Gap, BuildSpeedTile(), BuildTrafficTile()), 18);
            content.AddRow(BuildInfoPanel(), 18);

            if (Vpn.Status == VpnStatus.Connected)
            {
                content.AddRow(C.Button("断开连接", () => Ui.Fire(Disconnect), BtnStyle.Destructive, "power"), 18);
            }
            else if (Vpn.Status == VpnStatus.Connecting || Vpn.Status == VpnStatus.Reasserting)
            {
                content.AddRow(C.Button("取消连接", () => Ui.Fire(Disconnect), BtnStyle.Outline, "close"), 18);
            }
            else if (Vpn.Status == VpnStatus.Disconnecting)
            {
                content.AddRow(C.Button("正在断开…", null, BtnStyle.Outline, "power", DS.Size.ButtonHeight, true, true), 18);
            }

            content.AddRow(new Grid { Height = 16 }, 18);
            return Ui.ScrollPage(content);
        }

        UIElement BuildSpeedTile()
        {
            var inner = Ui.Stack(Orientation.Vertical, 8);

            var head = Ui.Stack(Orientation.Horizontal, 6);
            head.Children.Add(Ui.Icon("chart", 12, DS.IconColor.Green, 2));
            head.Children.Add(Ui.Caption("实时网速"));
            inner.AddRow(head, 8);

            var down = Ui.Stack(Orientation.Horizontal, 4);
            down.Children.Add(Ui.Icon("chevronDown", 13, DS.IconColor.Green, 2.4));
            _downValue = Ui.Text(Format.SpeedValue(_downSpeed), 18, FontWeights.SemiBold, Ui.P.Foreground);
            down.Children.Add(_downValue);
            inner.AddRow(down, 8);

            var up = Ui.Stack(Orientation.Horizontal, 4);
            up.Children.Add(Ui.Icon("chevronUp", 13, DS.IconColor.Teal, 2.4));
            _upValue = Ui.Text(Format.SpeedValue(_upSpeed), 15, FontWeights.Medium, Ui.P.SecondaryText);
            up.Children.Add(_upValue);
            inner.AddRow(up, 8);

            return C.Card(inner, 14);
        }

        UIElement BuildTrafficTile()
        {
            var inner = Ui.Stack(Orientation.Vertical, 8);

            var head = Ui.Stack(Orientation.Horizontal, 6);
            head.Children.Add(Ui.Icon("chart", 12, DS.IconColor.Cyan, 2));
            head.Children.Add(Ui.Caption("本次流量"));
            inner.AddRow(head, 8);

            _trafficTotal = Ui.Text(Format.Bytes(_sessionTx + _sessionRx), 18, FontWeights.SemiBold, Ui.P.Foreground);
            inner.AddRow(_trafficTotal, 8);

            var row = Ui.Stack(Orientation.Horizontal, 6);
            _trafficRx = Ui.Text("↑ " + Format.Bytes(_sessionRx), 12, FontWeights.Medium, DS.IconColor.Green);
            _trafficTx = Ui.Text("↓ " + Format.Bytes(_sessionTx), 12, FontWeights.Medium, DS.IconColor.Teal);
            row.Children.Add(_trafficRx);
            row.Children.Add(Ui.VLine(9));
            row.Children.Add(_trafficTx);
            inner.AddRow(row, 8);

            return C.Card(inner, 14);
        }

        UIElement BuildInfoPanel()
        {
            var stack = Ui.Stack(Orientation.Vertical, 0);
            stack.Children.Add(InfoLine("server", "当前服务器",
                string.IsNullOrEmpty(Vpn.ActiveServerName) ? "-" : Vpn.ActiveServerName, null));
            stack.Children.Add(Divider());
            stack.Children.Add(InfoLine("globe", "当前路线",
                string.IsNullOrEmpty(Vpn.ActiveLineName) ? "-" : Vpn.ActiveLineName, null));
            stack.Children.Add(Divider());
            stack.Children.Add(InfoLine("refresh", "连接状态", Vpn.StatusText,
                Vpn.Status == VpnStatus.Connected ? Ui.P.OnlineText : Ui.P.WarningText));

            var box = Ui.Box(stack, Ui.P.Card, DS.Radius.Xl, Ui.P.Border, 1, new Thickness(0));
            return box;
        }

        UIElement InfoLine(string icon, string label, string value, Color? valueColor)
        {
            var glyph = Ui.Icon(icon, 13, Ui.P.Primary, 2);
            var glyphBox = Ui.Box(glyph, Ui.Alpha(Ui.P.Primary, 0.10), DS.Radius.Sm, null, 0, new Thickness(0));
            glyphBox.Width = 26;
            glyphBox.Height = 26;
            var row = Ui.Stack(Orientation.Horizontal, 10);
            row.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(glyphBox);
            row.Children.Add(Ui.Text(label, DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.MutedForeground));
            row.Margin = new Thickness(14, 11, 14, 11);
            return Ui.Split(row, Ui.Text(value, DS.FontSize.Section, FontWeights.SemiBold,
                valueColor.HasValue ? valueColor.Value : Ui.P.SecondaryText));
        }

        UIElement Divider()
        {
            return new Rectangle
            {
                Height = 1,
                Fill = Ui.B(Ui.P.Border),
                Margin = new Thickness(50, 0, 0, 0),
            };
        }

        // MARK: - 密码输入（首次连接时保存登录密码）

        void ShowPasswordSheet()
        {
            _passwordField = C.TextField("登录密码", "请输入登录密码", "", true);
            _sheetButtonHost = new Grid();
            BuildSheetButton();

            var body = Ui.Stack(Orientation.Vertical, 14);
            body.Margin = new Thickness(0, 4, 0, 4);
            body.Children.Add(C.BannerBar("连接需要账号密码认证，密码仅保存在本机钥匙串，不会上传。", BannerKind.Info));
            body.Children.Add(C.ReadOnlyField("账号", App.User != null ? App.User.Username : ""));
            body.Children.Add(_passwordField);
            body.Children.Add(_sheetButtonHost);

            MainShell.PresentSheet("输入连接密码", body, () =>
            {
                _pendingProfile = null;
                if (_passwordField != null) _passwordField.Value = "";
            });
        }

        void BuildSheetButton()
        {
            if (_sheetButtonHost == null) return;
            _sheetButtonHost.Children.Clear();
            _sheetButtonHost.Children.Add(C.Button("保存并连接", () => Ui.Fire(ConfirmPasswordAndConnect),
                BtnStyle.Primary, "bolt", DS.Size.ButtonHeight, _savingPassword, _savingPassword));
        }

        async System.Threading.Tasks.Task ConfirmPasswordAndConnect()
        {
            var profile = _pendingProfile;
            if (profile == null) return;
            var password = _passwordField != null ? (_passwordField.Value ?? "") : "";
            if (password.Length == 0)
            {
                App.ShowToast("请输入登录密码", BannerKind.Warning);
                return;
            }
            _savingPassword = true;
            BuildSheetButton();
            SecureStore.Save(password, SecureStore.PasswordAccount);
            _pendingProfile = null;
            DismissSheet();
            try
            {
                await StartTunnel(profile, password);
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _savingPassword = false;
            }
        }

        static void DismissSheet()
        {
            var shell = MainShell.Current;
            if (shell != null) shell.Sheet.Dismiss();
        }

        // MARK: - 数据与动作

        /// <summary>加载服务器与线路；clearSelection=true 时清空已选线路（底部连接栏随之收起）</summary>
        async System.Threading.Tasks.Task Load(bool clearSelection)
        {
            _loading = true;
            try
            {
                var payload = await ApiClient.Shared.FetchLines();
                _payload = payload;
                if (clearSelection) _selectedLineId = null;
                if (_selectedNodeId.HasValue && !payload.Nodes.Exists(n => n.Id == _selectedNodeId.Value))
                {
                    _selectedNodeId = null;
                    _selectedLineId = null;
                }
                if (_selectedLineId.HasValue && !payload.Lines.Exists(l => l.Id == _selectedLineId.Value))
                {
                    _selectedLineId = null;
                }
            }
            catch (Exception error)
            {
                // 下拉刷新取消请求时静默处理，避免弹出「已取消」错误
                if (ApiException.From(error).IsCancelled) return;
                App.Report(error);
            }
            finally
            {
                _loading = false;
                Rebuild();
            }
        }

        async System.Threading.Tasks.Task Connect(string family)
        {
            var node = SelectedNode();
            var line = SelectedLine();
            if (node == null || line == null) return;
            if (_connectingFamily != null) return;
            if (_payload == null || _payload.Quota == null || !_payload.Quota.Valid)
            {
                var reason = (_payload != null && _payload.Quota != null && !string.IsNullOrEmpty(_payload.Quota.Reason))
                    ? _payload.Quota.Reason : "当前订阅状态不可用";
                App.ShowToast(reason, BannerKind.Warning);
                return;
            }

            // 连接前先检查账号状态：被拉黑 / 封禁 / 到期 / 超流量直接拦截
            try
            {
                var status = await ApiClient.Shared.FetchUserStatus();
                if (status.Notice != null)
                {
                    bool isBlock = status.Notice.Code == "blocked" || status.Notice.Code == "banned";
                    App.ShowToast(status.Notice.Message, isBlock ? BannerKind.Error : BannerKind.Warning);
                    return;
                }
            }
            catch { /* 与 iOS try? 一致：状态查询失败不阻断连接 */ }

            _connectingFamily = family;
            Rebuild();
            try
            {
                var config = await ApiClient.Shared.FetchLineConfig(line.Id, node.Id, family);
                var saved = SecureStore.Load(SecureStore.PasswordAccount) ?? "";
                if (saved.Length == 0)
                {
                    _pendingProfile = config;
                    ShowPasswordSheet();
                    return;
                }
                await StartTunnel(config, saved);
            }
            catch (Exception error)
            {
                if (ApiException.From(error).IsCancelled) return;
                App.Report(error);
            }
            finally
            {
                _connectingFamily = null;
                Rebuild();
            }
        }

        async System.Threading.Tasks.Task StartTunnel(LineConfig profile, string password)
        {
            var username = App.User != null ? App.User.Username : null;
            if (string.IsNullOrEmpty(username)) throw new ApiException("登录状态异常，请重新登录");
            _attemptActive = true;
            try
            {
                await Vpn.Connect(profile, username, password);
            }
            catch
            {
                _attemptActive = false;
                throw;
            }
        }

        async System.Threading.Tasks.Task Disconnect()
        {
            _attemptActive = false;
            await Vpn.Disconnect();
            StopStats();
            App.ShowToast("已断开连接", BannerKind.Info);
            try { await ApiClient.Shared.CloseSessions(); } catch { }
        }

        /// <summary>监听隧道状态：只有真正连接成功才进入「已连接」；失败则回到选择页并提示</summary>
        void OnVpnChanged()
        {
            var status = Vpn.Status;
            if (status != _lastStatus)
            {
                HandleStatusChange(status);
                _lastStatus = status;
            }
            Rebuild();
        }

        void HandleStatusChange(VpnStatus status)
        {
            if (status == VpnStatus.Connected)
            {
                _connectingFamily = null;
                if (_attemptActive)
                {
                    _attemptActive = false;
                    var name = Vpn.ActiveServerName;
                    App.ShowToast(string.IsNullOrEmpty(name) ? "已连接" : "已连接到 " + name, BannerKind.Success);
                    ResetSessionStats();
                }
                if (SessionStart() == null) _connectedSince = DateTime.Now;
                StartStats();
            }
            else if (status == VpnStatus.Disconnected)
            {
                if (_attemptActive)
                {
                    _attemptActive = false;
                    _connectingFamily = null;
                    App.ShowToast("连接失败，请检查账号状态或稍后重试", BannerKind.Error);
                    // 立即拉取账号状态，若存在具体异常则用更精确的提示覆盖
                    Ui.Fire(() => App.CheckStatusNow());
                }
                StopStats();
                _connectedSince = null;
            }
        }

        // MARK: - 当前会话的实时网速与流量

        void ResetSessionStats()
        {
            _sessionRx = 0;
            _sessionTx = 0;
            _downSpeed = 0;
            _upSpeed = 0;
            _lastSample = null;
            UpdateStatsUi();
        }

        void StartStats()
        {
            StopStats();
            var cts = new System.Threading.CancellationTokenSource();
            _statsCts = cts;
            Ui.Fire(async () =>
            {
                while (!cts.IsCancellationRequested)
                {
                    await SampleStats();
                    try { await System.Threading.Tasks.Task.Delay(2000, cts.Token); }
                    catch { break; }
                }
            });
        }

        void StopStats()
        {
            if (_statsCts != null) { _statsCts.Cancel(); _statsCts = null; }
        }

        async System.Threading.Tasks.Task SampleStats()
        {
            if (Vpn.Status != VpnStatus.Connected) return;

            UserCenterPayload center;
            try { center = await ApiClient.Shared.FetchUserCenter(); }
            catch { return; }

            // 绑定到当前连接的服务器，避免连到别的节点时统计串台
            OnlineSession session = null;
            foreach (var item in center.OnlineSessions)
                if (item.NodeId == Vpn.ActiveNodeId) { session = item; break; }
            if (session == null && center.OnlineSessions.Count > 0) session = center.OnlineSessions[0];
            if (session == null) return;

            // 从主控会话时间恢复计时（例如在系统设置里连接后回到 App）
            if (_connectedSince == null)
            {
                var started = Format.Parse(session.ConnectedAt);
                if (started.HasValue) _connectedSince = started;
            }

            var rx = session.RxBytes;
            var tx = session.TxBytes;
            _sessionRx = rx;
            _sessionTx = tx;

            var now = DateTime.Now;
            if (_lastSample != null)
            {
                var elapsed = (now - _lastSample.At).TotalSeconds;
                if (elapsed > 0.5)
                {
                    double downDelta = Math.Max(0, tx - _lastSample.Tx);
                    double upDelta = Math.Max(0, rx - _lastSample.Rx);
                    // 指数平滑，避免读数跳动
                    _downSpeed = _downSpeed * 0.4 + (downDelta / elapsed) * 0.6;
                    _upSpeed = _upSpeed * 0.4 + (upDelta / elapsed) * 0.6;
                }
            }
            _lastSample = new Sample { Rx = rx, Tx = tx, At = now };

            Ui.Post(UpdateStatsUi);
        }

        void UpdateStatsUi()
        {
            if (_downValue != null) _downValue.Text = Format.SpeedValue(_downSpeed);
            if (_upValue != null) _upValue.Text = Format.SpeedValue(_upSpeed);
            if (_trafficTotal != null) _trafficTotal.Text = Format.Bytes(_sessionTx + _sessionRx);
            if (_trafficRx != null) _trafficRx.Text = "↑ " + Format.Bytes(_sessionRx);
            if (_trafficTx != null) _trafficTx.Text = "↓ " + Format.Bytes(_sessionTx);
        }

        // MARK: - 构造辅助

        static TextBlock PageTitle(string text)
        {
            var title = Ui.Text(text, 28, FontWeights.Bold, Ui.P.Foreground);
            title.Margin = new Thickness(0, 4, 0, 0);
            return title;
        }

        static Border StepBadge(string number, Color color)
        {
            var label = Ui.Text(number, 10, FontWeights.Bold, Colors.White);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            return new Border
            {
                Width = 14,
                Height = 14,
                CornerRadius = new CornerRadius(7),
                Background = Ui.B(color),
                VerticalAlignment = VerticalAlignment.Center,
                Child = new Grid { Children = { label } },
            };
        }

        static Border Pill(string title, string icon, Color foreground, Brush background, Action action)
        {
            var row = Ui.Stack(Orientation.Horizontal, 4);
            row.VerticalAlignment = VerticalAlignment.Center;
            if (!string.IsNullOrEmpty(icon)) row.Children.Add(Ui.Icon(icon, 11, foreground, 2));
            row.Children.Add(Ui.Text(title, 13, FontWeights.SemiBold, foreground));
            var border = new Border
            {
                Height = DS.Size.ButtonHeightSmall,
                CornerRadius = new CornerRadius(DS.Size.ButtonHeightSmall / 2),
                Background = background,
                Padding = new Thickness(12, 0, 12, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Child = new Grid { Children = { row } },
            };
            border.Clickable(action);
            return border;
        }

        static UIElement AddressRow(string label, string value, Color color)
        {
            var tag = Ui.Text(label, 10, FontWeights.SemiBold, color);
            tag.Margin = new Thickness(6, 0, 6, 0);
            var tagBox = new Border
            {
                Height = 16,
                CornerRadius = new CornerRadius(4),
                Background = Ui.B(Ui.Alpha(color, 0.14)),
                Child = new Grid { Children = { tag } },
            };
            var text = Ui.Text(value, 12, FontWeights.Normal, Ui.P.SecondaryText);
            text.FontFamily = new FontFamily("Consolas, Segoe UI");
            var row = Ui.Stack(Orientation.Horizontal, 8, tagBox, text);
            return row;
        }

        static UIElement MetricCell(string title, string value)
        {
            var stack = Ui.Stack(Orientation.Vertical, 2);
            stack.Children.Add(Ui.Caption(title));
            stack.Children.Add(Ui.Text(value, DS.FontSize.Section, FontWeights.SemiBold, Ui.P.Foreground));
            stack.HorizontalAlignment = HorizontalAlignment.Left;
            return stack;
        }

        static Grid Columns(double gap, params UIElement[] items)
        {
            var grid = new Grid();
            for (int i = 0; i < items.Length; i++)
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            for (int i = 0; i < items.Length; i++)
            {
                if (items[i] == null) continue;
                var element = (FrameworkElement)items[i];
                double left = i > 0 ? gap / 2 : 0;
                double right = i < items.Length - 1 ? gap / 2 : 0;
                element.Margin = new Thickness(element.Margin.Left + left, element.Margin.Top,
                    element.Margin.Right + right, element.Margin.Bottom);
                Grid.SetColumn(element, i);
                grid.Children.Add(element);
            }
            return grid;
        }

        static Grid Overlay(Border card, Color? stroke, double thickness)
        {
            var grid = new Grid();
            grid.Children.Add(card);
            if (stroke.HasValue)
            {
                grid.Children.Add(new Border
                {
                    CornerRadius = new CornerRadius(DS.Radius.Xl),
                    BorderBrush = Ui.B(stroke.Value),
                    BorderThickness = new Thickness(thickness),
                    IsHitTestVisible = false,
                });
            }
            return grid;
        }
    }
}
