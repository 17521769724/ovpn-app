using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OVPNPanel.Theme;

namespace OVPNPanel.Core
{
    /// <summary>
    /// 「我的」Tab 根页（对应 iOS ProfileView.swift）。
    /// 命令式构建：用户卡片 / 资产条 / 流量统计（近 7-15 天柱状图）/ 在线会话 / 功能入口列表。
    /// </summary>
    public class ProfileView : Screen
    {
        readonly StackPanel _body = Ui.Stack(Orientation.Vertical, 0);

        UserCenterPayload _center;
        TrafficPayload _traffic;
        bool _loading;
        bool _loaded;
        int _unreadCount;
        int _trafficDays = 15;
        bool _closingSessions;

        public ProfileView()
        {
            HidesHeader = true;
            Title = "个人中心";
            _body.Margin = new Thickness(0, 8, 0, 24);
            Content = Ui.ScrollPage(_body);
            Rebuild();
        }

        public override void OnAppear()
        {
            if (_loaded) return;
            _loaded = true;
            Ui.Fire(Load);
        }

        public override void Refresh()
        {
            Rebuild();
        }

        // MARK: - 数据加载

        async System.Threading.Tasks.Task Load()
        {
            if (_loading) return;
            _loading = true;
            try
            {
                try
                {
                    _center = await ApiClient.Shared.FetchUserCenter();
                }
                catch (Exception error)
                {
                    App.Report(error);
                }
                await LoadTraffic();
                try
                {
                    var announcements = await ApiClient.Shared.FetchAnnouncements();
                    _unreadCount = announcements.UnreadCount;
                }
                catch { /* 公告失败不影响主流程 */ }
            }
            finally
            {
                _loading = false;
            }
            Rebuild();
        }

        /// <summary>按当前选择（近 7 / 15 天）拉取流量统计；失败或被取消时保留上次数据</summary>
        async System.Threading.Tasks.Task LoadTraffic()
        {
            int days = _trafficDays;
            TrafficPayload value;
            try
            {
                value = await ApiClient.Shared.FetchTraffic(days);
            }
            catch
            {
                return;
            }
            if (days != _trafficDays) return;
            _traffic = value;
            Rebuild();
        }

        /// <summary>手动断开该账号在主控侧的全部在线会话（含系统断开后残留的记录）</summary>
        async System.Threading.Tasks.Task CloseAllSessions()
        {
            if (_closingSessions) return;
            _closingSessions = true;
            Rebuild();
            try
            {
                await ApiClient.Shared.CloseSessions();
                await Vpn.Disconnect();
                App.ShowToast("已断开全部在线会话", BannerKind.Success);
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _closingSessions = false;
            }
            await Load();
        }

        // MARK: - 页面重建

        void Rebuild()
        {
            var palette = Ui.P;
            _body.Children.Clear();
            Add(Ui.Text("个人中心", DS.FontSize.Title, FontWeights.Bold, palette.Foreground));
            Add(UserCard(palette));
            Add(AssetsStrip(palette));
            Add(TrafficCard(palette));
            Add(SessionCard(palette));
            Add(MenuCard(palette));
            Add(LogoutButton());
            Add(Footer(palette));
        }

        void Add(UIElement element)
        {
            _body.AddRow(element, DS.Size.GapLarge);
        }

        // MARK: - 账户资产（等级 / 金币 / 余额）

        Border AssetsStrip(Palette palette)
        {
            var user = CurrentUser;

            var grid = new Grid { Margin = new Thickness(0, 14, 0, 14) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            double balance = user != null ? user.BalanceYuanValue : 0;

            var level = AssetCell("shield", DS.IconColor.Teal, "等级",
                "Lv." + (user != null ? user.LevelValue : 1));
            var coins = AssetCell("coin", DS.IconColor.Amber, "金币",
                (user != null ? user.CoinsValue : 0).ToString(CultureInfo.InvariantCulture));
            var balanceCell = AssetCell("card", DS.IconColor.Green, "余额",
                balance.ToString("F2", CultureInfo.InvariantCulture));

            Grid.SetColumn(level, 0); grid.Children.Add(level);
            Grid.SetColumn(AssetDivider(palette), 1); grid.Children.Add(AssetDivider(palette));
            Grid.SetColumn(coins, 2); grid.Children.Add(coins);
            Grid.SetColumn(AssetDivider(palette), 3); grid.Children.Add(AssetDivider(palette));
            Grid.SetColumn(balanceCell, 4); grid.Children.Add(balanceCell);

            return C.Card(grid, 0);
        }

        static UIElement AssetCell(string icon, Color color, string title, string value)
        {
            var glyph = Ui.Icon(icon, 17, color, 2);
            glyph.HorizontalAlignment = HorizontalAlignment.Center;
            var valueText = Ui.Text(value, 16, FontWeights.SemiBold, Ui.P.Foreground);
            valueText.HorizontalAlignment = HorizontalAlignment.Center;
            var titleText = Ui.Text(title, DS.FontSize.Caption, FontWeights.Normal, Ui.P.MutedForeground);
            titleText.HorizontalAlignment = HorizontalAlignment.Center;

            var stack = Ui.Stack(Orientation.Vertical, 5, glyph, valueText, titleText);
            stack.HorizontalAlignment = HorizontalAlignment.Stretch;
            stack.VerticalAlignment = VerticalAlignment.Center;
            return stack;
        }

        static UIElement AssetDivider(Palette palette)
        {
            return new Border
            {
                Width = 1,
                Height = 34,
                Background = Ui.B(palette.Border),
                VerticalAlignment = VerticalAlignment.Center,
            };
        }

        // MARK: - 用户卡片（渐变底：主题色示意，作为页面视觉焦点）

        Border UserCard(Palette palette)
        {
            var user = CurrentUser;

            var avatarText = Ui.Text(Initial(user), 20, FontWeights.SemiBold, Colors.White);
            avatarText.HorizontalAlignment = HorizontalAlignment.Center;
            avatarText.TextAlignment = TextAlignment.Center;
            var avatar = new Border
            {
                Width = 48,
                Height = 48,
                CornerRadius = new CornerRadius(24),
                Background = new LinearGradientBrush(DS.IconColor.Green, DS.IconColor.Teal, 45),
                Child = new Grid { Children = { avatarText } },
                VerticalAlignment = VerticalAlignment.Center,
            };

            var name = Ui.Text(user != null && !string.IsNullOrEmpty(user.Username) ? user.Username : "-",
                DS.FontSize.Section, FontWeights.SemiBold, palette.Foreground);
            var email = Ui.Text(EmailText(user), DS.FontSize.Caption, FontWeights.Normal, palette.SecondaryText);
            var nameStack = Ui.Stack(Orientation.Vertical, 3, name, email);
            nameStack.VerticalAlignment = VerticalAlignment.Center;

            var headerLeft = Ui.Stack(Orientation.Horizontal, 12, avatar, nameStack);

            // 数据未就绪时先占位，避免加载完成后整块插入导致布局跳动
            Border badge;
            if (_center != null)
            {
                bool valid = _center.Quota != null && _center.Quota.Valid;
                badge = C.StatusBadge(valid ? "正常" : "受限",
                    valid ? palette.OnlineBg : palette.OfflineBg,
                    valid ? palette.OnlineText : palette.OfflineText);
            }
            else
            {
                badge = C.StatusBadge("同步中", palette.Muted, palette.MutedForeground);
            }

            var header = Ui.Split(headerLeft, badge);

            var info = Ui.Stack(Orientation.Vertical, 6,
                C.InfoRow("当前套餐", _center != null && _center.Plan != null ? _center.Plan.Name : "—"),
                C.InfoRow("到期时间", _center == null ? "—" : Format.DateOnly(user != null ? user.PlanExpiresAt : null)),
                C.InfoRow("限速", _center == null ? "—" : Format.Speed(user != null ? user.SpeedLimitKbps : 0)),
                C.InfoRow("设备上限", _center == null ? "—"
                    : ((user != null ? user.DeviceLimit : 0) > 0 ? (user != null ? user.DeviceLimit : 0) + " 台" : "不限")));

            UIElement banner = null;
            if (_center != null && _center.Quota != null && !_center.Quota.Valid)
                banner = C.BannerBar(_center.Quota.Reason);

            var content = Ui.Stack(Orientation.Vertical, 12, header, banner, info);
            content.Margin = new Thickness(DS.Size.CardPadding);

            var layers = new Grid();
            layers.Children.Add(new Border { Background = Ui.B(palette.Card) });
            var gradient = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(1, 1) };
            gradient.GradientStops.Add(new GradientStop(Ui.Alpha(palette.Primary, palette.Dark ? 0.24 : 0.14), 0));
            gradient.GradientStops.Add(new GradientStop(Ui.Alpha(DS.Brand.Teal, palette.Dark ? 0.10 : 0.06), 0.55));
            gradient.GradientStops.Add(new GradientStop(Colors.Transparent, 1));
            layers.Children.Add(new Border { Background = gradient });
            layers.Children.Add(content);

            return new Border
            {
                CornerRadius = new CornerRadius(DS.Radius.Xl),
                BorderBrush = Ui.B(Ui.Alpha(palette.Primary, 0.20)),
                BorderThickness = new Thickness(1),
                ClipToBounds = true,
                Child = layers,
            };
        }

        // MARK: - 流量（纯绿色统计）

        Border TrafficCard(Palette palette)
        {
            var headerLeft = Ui.Stack(Orientation.Horizontal, 10,
                Ui.IconTile("chart", DS.Traffic.BarStrong),
                C.SectionHeader("流量使用"));
            var tabs = new SegmentedTabs(new[] { "近7天", "近15天" }, _trafficDays == 7 ? 0 : 1);
            tabs.SelectionChanged += OnTrafficRangeChanged;
            var header = Ui.Split(headerLeft, tabs);

            long used = _center != null && _center.Traffic != null ? _center.Traffic.UsedBytes : 0;
            long limit = _center != null && _center.Traffic != null ? _center.Traffic.LimitBytes : 0;
            double percent = _center != null && _center.Traffic != null ? _center.Traffic.Percent : 0;

            var usedText = Ui.Text(_center == null ? "—" : Format.Bytes(used), 22, FontWeights.SemiBold, DS.Traffic.BarStrong);
            var limitText = Ui.Text(limit > 0 ? "/ " + Format.Bytes(limit) : "/ 不限量",
                DS.FontSize.BodySmall, FontWeights.Normal, palette.SecondaryText);
            var amountLeft = Ui.Stack(Orientation.Horizontal, 5, usedText, limitText);
            amountLeft.VerticalAlignment = VerticalAlignment.Bottom;

            FrameworkElement percentText = null;
            if (limit > 0)
                percentText = Ui.Text(percent.ToString("F1", CultureInfo.InvariantCulture) + "%",
                    DS.FontSize.Section, FontWeights.SemiBold, DS.Traffic.BarStrong);

            var amount = Ui.Split(amountLeft, percentText);

            UIElement chart = _traffic != null && _traffic.Days != null && _traffic.Days.Count > 0
                ? (UIElement)new TrafficBars(_traffic.Days)
                : new TrafficBarsPlaceholder();

            var totalText = Ui.Text(_traffic != null ? "合计 " + Format.Bytes(_traffic.TotalBytes) : "合计 —",
                DS.FontSize.Caption, FontWeights.Normal, palette.SecondaryText);
            var legend = Ui.Stack(Orientation.Horizontal, 10,
                Legend(DS.Traffic.Bar, "上传"),
                Legend(DS.Traffic.BarSoft, "下载"));
            var footer = Ui.Split(totalText, legend);

            var body = Ui.Stack(Orientation.Vertical, 12, header, amount, ProgressBar(percent, palette), chart, footer);
            return C.Card(body);
        }

        static UIElement Legend(Color color, string title)
        {
            var swatch = new Border { Width = 10, Height = 10, CornerRadius = new CornerRadius(2), Background = Ui.B(color) };
            var label = Ui.Text(title, DS.FontSize.Caption, FontWeights.Normal, DS.IconColor.Slate);
            return Ui.Stack(Orientation.Horizontal, 4, swatch, label);
        }

        static Grid ProgressBar(double percent, Palette palette)
        {
            var track = new Border
            {
                CornerRadius = new CornerRadius(4),
                Background = Ui.B(palette.TrafficTracker),
            };
            var fill = new Border
            {
                CornerRadius = new CornerRadius(4),
                HorizontalAlignment = HorizontalAlignment.Left,
                Background = new LinearGradientBrush(DS.Traffic.Bar, DS.Traffic.BarStrong, 0),
            };
            var grid = new Grid { Height = 8.0 };
            grid.Children.Add(track);
            grid.Children.Add(fill);
            double ratio = Math.Max(0, Math.Min(1, percent / 100.0));
            grid.SizeChanged += (s, e) => { fill.Width = grid.ActualWidth * ratio; };
            return grid;
        }

        void OnTrafficRangeChanged(int index)
        {
            _trafficDays = index == 0 ? 7 : 15;
            Ui.Fire(LoadTraffic);
        }

        // MARK: - 在线会话

        Border SessionCard(Palette palette)
        {
            var stack = Ui.Stack(Orientation.Vertical, 10);
            stack.Children.Add(Ui.Stack(Orientation.Horizontal, 10,
                Ui.IconTile("globe", DS.IconColor.Cyan),
                C.SectionHeader("在线会话", "当前账号的连接")));

            var sessions = _center != null && _center.OnlineSessions != null
                ? _center.OnlineSessions
                : new List<OnlineSession>();

            if (sessions.Count == 0)
            {
                var empty = Ui.Text("当前没有在线连接", DS.FontSize.BodySmall, FontWeights.Normal, palette.SecondaryText);
                empty.Margin = new Thickness(0, 6, 0, 6);
                stack.Children.Add(empty);
            }
            else
            {
                for (int i = 0; i < sessions.Count; i++)
                {
                    var session = sessions[i];
                    var nameRow = Ui.Split(
                        Ui.Text(string.IsNullOrEmpty(session.NodeName) ? "节点" : session.NodeName,
                            DS.FontSize.BodySmall, FontWeights.Normal, palette.Foreground),
                        Ui.Text(Format.DateTimeText(session.ConnectedAt), DS.FontSize.Caption,
                            FontWeights.Normal, palette.MutedForeground));

                    var item = Ui.Stack(Orientation.Vertical, 6, nameRow,
                        C.InfoRow("虚拟 IP", string.IsNullOrEmpty(session.VirtualIp) ? "-" : session.VirtualIp),
                        C.InfoRow("流量", "↑ " + Format.Bytes(session.RxBytes) + " / ↓ " + Format.Bytes(session.TxBytes)));
                    item.Margin = new Thickness(0, 6, 0, 6);
                    stack.Children.Add(item);

                    if (i < sessions.Count - 1)
                        stack.Children.Add(new Border { Height = 1, Background = Ui.B(palette.Border) });
                }

                // 本机未连接时，这些会话多半是系统断开后留下的残留记录，提供手动兜底清理
                if (!Vpn.IsConnected)
                {
                    stack.Children.Add(new Border { Height = 1, Background = Ui.B(palette.Border) });

                    var label = Ui.Text("断开其它设备 / 清理残留会话", DS.FontSize.Caption,
                        FontWeights.Normal, palette.MutedForeground);
                    var button = C.Button("全部断开", () => Ui.Fire(CloseAllSessions), BtnStyle.Secondary, "close",
                        DS.Size.ButtonHeightSmall, _closingSessions, _closingSessions);
                    button.Width = 108;

                    var row = Ui.Split(label, button);
                    row.Margin = new Thickness(0, 8, 0, 0);
                    stack.Children.Add(row);
                }
            }

            return C.Card(stack);
        }

        // MARK: - 功能入口

        Border MenuCard(Palette palette)
        {
            var rows = new List<UIElement>();
            rows.Add(C.MenuRow("megaphone", DS.IconColor.Rose, "公告", null,
                _unreadCount > 0 ? _unreadCount.ToString(CultureInfo.InvariantCulture) : null,
                () => Push(new AnnouncementsView())));
            rows.Add(C.MenuRow("ticket", DS.IconColor.Amber, "激活码", null, null,
                () => Push(new ActivationView())));
            rows.Add(C.MenuRow("card", DS.IconColor.Green, "余额充值", "充值后可在购买套餐时全额抵扣", null,
                () => Push(new RechargeView())));
            rows.Add(C.MenuRow("coin", DS.IconColor.Orange, "金币记录", null, null,
                () => Push(new CoinsView())));
            rows.Add(C.MenuRow("message", DS.IconColor.Cyan, "问题反馈", null, null,
                () => Push(new FeedbackView())));
            rows.Add(C.MenuRow("doc", DS.IconColor.Cyan, "我的订单", null, null,
                () => Push(new OrdersView())));
            rows.Add(C.MenuRow("gear", DS.IconColor.Slate, "账号设置", null, null,
                () => Push(new AccountSettingsView())));
            return C.MenuGroup(C.MenuList(rows.ToArray()));
        }

        UIElement LogoutButton()
        {
            var button = C.Button("退出登录", ConfirmLogout, BtnStyle.Destructive, "logout");
            button.Margin = new Thickness(0, 4, 0, 0);
            return button;
        }

        void ConfirmLogout()
        {
            MainShell.PresentAlert("退出登录？", "", "退出", () => App.Logout(), true, "取消");
        }

        UIElement Footer(Palette palette)
        {
            var versionText = Ui.Text("客户端 " + VersionText(), DS.FontSize.Caption,
                FontWeights.Normal, palette.MutedForeground);
            var master = Ui.Text(App.MasterURL, DS.FontSize.Caption, FontWeights.Normal, palette.MutedForeground);
            master.MaxWidth = 190;
            var row = Ui.Stack(Orientation.Horizontal, 8, versionText, Ui.VLine(10), master);
            row.HorizontalAlignment = HorizontalAlignment.Center;
            row.Margin = new Thickness(0, 4, 0, 0);
            return row;
        }

        // MARK: - 辅助

        AppUser CurrentUser
        {
            get { return _center != null && _center.User != null ? _center.User : App.User; }
        }

        static string Initial(AppUser user)
        {
            var name = user != null ? user.Username : null;
            if (string.IsNullOrEmpty(name)) return "U";
            return name.Substring(0, 1).ToUpperInvariant();
        }

        static string EmailText(AppUser user)
        {
            if (user == null || string.IsNullOrEmpty(user.Email)) return "未绑定邮箱";
            return user.Email;
        }

        static string VersionText()
        {
            var version = typeof(ProfileView).Assembly.GetName().Version;
            if (version == null) return "v1.0.0 (Build 1)";
            return "v" + version.Major + "." + version.Minor + "." + version.Build
                + " (Build " + version.Revision + ")";
        }
    }

    /// <summary>流量柱状图占位：保持与真实图表相同的高度与排布，避免加载完成后页面跳动</summary>
    class TrafficBarsPlaceholder : Grid
    {
        public TrafficBarsPlaceholder(double height = 90)
        {
            Height = height;
            var palette = Ui.P;
            for (int i = 0; i < 15; i++)
            {
                ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                var column = new Grid { Margin = new Thickness(1.5, 0, 1.5, 0) };
                column.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
                column.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

                var bars = new StackPanel { Orientation = Orientation.Vertical, VerticalAlignment = VerticalAlignment.Bottom };
                bars.Children.Add(new Border
                {
                    Height = 4,
                    CornerRadius = new CornerRadius(2),
                    Background = Ui.B(Ui.Alpha(palette.TrafficTracker, 0.7)),
                });
                Grid.SetRow(bars, 0);
                column.Children.Add(bars);

                var label = Ui.Text("--", 9, FontWeights.Normal, Ui.Alpha(palette.MutedForeground, 0.5));
                label.HorizontalAlignment = HorizontalAlignment.Center;
                Grid.SetRow(label, 1);
                column.Children.Add(label);

                Grid.SetColumn(column, i);
                Children.Add(column);
            }
        }
    }

    /// <summary>流量柱状图（纯绿色，与 Web 端配色对齐）：上段为上传、下段为下载，底部为日期标签</summary>
    public class TrafficBars : Grid
    {
        public TrafficBars(List<TrafficDay> days, double height = 90)
        {
            Height = height;
            var palette = Ui.P;

            long max = 1;
            if (days != null)
            {
                foreach (var day in days)
                    if (day.TotalBytes > max) max = day.TotalBytes;
            }

            int count = days != null ? days.Count : 0;
            double barArea = Math.Max(20, height - 14);

            for (int i = 0; i < count; i++)
            {
                ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                var day = days[i];

                var column = new Grid { Margin = new Thickness(1.5, 0, 1.5, 0) };
                column.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
                column.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

                double total = (double)day.TotalBytes / max;
                double barHeight = Math.Max(2, barArea * total);
                double rxRatio = day.TotalBytes > 0
                    ? (double)day.RxBytes / Math.Max(day.TotalBytes, 1)
                    : 0.5;
                double topHeight = Math.Max(1, barHeight * (1 - rxRatio));
                double bottomHeight = Math.Max(1, barHeight * rxRatio);

                var bars = new StackPanel { Orientation = Orientation.Vertical, VerticalAlignment = VerticalAlignment.Bottom };
                bars.Children.Add(new Border
                {
                    Height = topHeight,
                    CornerRadius = new CornerRadius(2),
                    Background = Ui.B(DS.Traffic.Bar),
                });
                bars.Children.Add(new Border
                {
                    Height = bottomHeight,
                    CornerRadius = new CornerRadius(2),
                    Background = Ui.B(DS.Traffic.BarSoft),
                    Margin = new Thickness(0, 1, 0, 0),
                });
                Grid.SetRow(bars, 0);
                column.Children.Add(bars);

                var label = Ui.Text(DaySuffix(day.Day), 9, FontWeights.Normal, palette.MutedForeground);
                label.HorizontalAlignment = HorizontalAlignment.Center;
                Grid.SetRow(label, 1);
                column.Children.Add(label);

                Grid.SetColumn(column, i);
                Children.Add(column);
            }
        }

        static string DaySuffix(string day)
        {
            if (string.IsNullOrEmpty(day)) return "";
            return day.Length <= 2 ? day : day.Substring(day.Length - 2);
        }
    }
}
