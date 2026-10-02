using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using OVPNPanel.Theme;

namespace OVPNPanel.Core
{
    // MARK: - 支付辅助（对应 PlansView.swift 内的 PayOption / PendingPay / PayTargetOption 与相关自由函数）

    /// <summary>套餐购买 / 余额充值共用的支付辅助：支付方式、支付接口选项与行组件</summary>
    static class PlansPay
    {
        /// <summary>支付方式（易支付：alipay / wxpay / qqpay）</summary>
        public class Method
        {
            public string Id;
            public string Name;
            public string Icon;
            public Color Tint;

            public Method(string id, string name, string icon, Color tint)
            {
                Id = id;
                Name = name;
                Icon = icon;
                Tint = tint;
            }

            public static readonly List<Method> All = new List<Method>
            {
                new Method("alipay", "支付宝", "card", DS.IconColor.Cyan),
                new Method("wxpay", "微信支付", "message", DS.IconColor.Green),
                new Method("qqpay", "QQ 钱包", "coin", DS.IconColor.Teal),
            };
        }

        /// <summary>支付接口选项：管理后台配置的接口 + 「余额抵扣」选项</summary>
        public class Target
        {
            public string Id;        // "balance" 或 "channel:<id>"
            public string Name;
            public string Detail;
            public string Icon;
            public Color Tint;
            public bool Disabled;    // 不可选（如余额不足）
        }

        /// <summary>已确认的支付请求：支付方式弹窗关闭后再创建订单，避免与浏览器弹窗叠加冲突</summary>
        public class Pending
        {
            public PlanItem Plan;
            public string Method;
            /// <summary>所选支付接口（余额抵扣时为 null）</summary>
            public int? ChannelId;
            /// <summary>是否使用余额全额抵扣（此时不再携带支付方式与接口）</summary>
            public bool UseBalance;
        }

        /// <summary>构造支付接口选项列表（余额抵扣排在最后；余额不足时标记为不可选）</summary>
        public static List<Target> TargetOptions(int amountCents, int balanceCents, List<PaymentChannelItem> channels)
        {
            var list = new List<Target>();
            if (channels != null)
            {
                foreach (var channel in channels)
                {
                    var names = new List<string>();
                    var configured = channel.Methods ?? new List<string>();
                    foreach (var id in configured)
                    {
                        var match = Method.All.Find(m => m.Id == id);
                        if (match != null) names.Add(match.Name);
                    }
                    list.Add(new Target
                    {
                        Id = "channel:" + channel.Id,
                        Name = channel.Name,
                        Detail = names.Count == 0 ? "支持全部支付方式" : string.Join(" / ", names.ToArray()),
                        Icon = "card",
                        Tint = DS.IconColor.Cyan,
                        Disabled = false,
                    });
                }
            }
            if (amountCents > 0)
            {
                bool enough = balanceCents >= amountCents;
                list.Add(new Target
                {
                    Id = "balance",
                    Name = "余额抵扣",
                    Detail = enough
                        ? "使用账户余额全额支付，无需选择支付方式"
                        : "余额不足，请先充值后再抵扣",
                    Icon = "coin",
                    Tint = DS.IconColor.Green,
                    Disabled = !enough,
                });
            }
            return list;
        }

        /// <summary>某支付接口支持的支付方式（未配置方式时兜底展示全部标准方式）</summary>
        public static List<Method> MethodsForTarget(string target, List<PaymentChannelItem> channels)
        {
            var id = ChannelId(target);
            PaymentChannelItem channel = null;
            if (id.HasValue && channels != null)
            {
                foreach (var item in channels)
                {
                    if (item.Id == id.Value) { channel = item; break; }
                }
            }
            if (channel == null) return new List<Method>(Method.All);

            var allowed = channel.Methods ?? new List<string>();
            var list = new List<Method>();
            foreach (var option in Method.All)
            {
                if (allowed.Contains(option.Id)) list.Add(option);
            }
            return list.Count == 0 ? new List<Method>(Method.All) : list;
        }

        /// <summary>"channel:&lt;id&gt;" → id；其余（含 "balance"）返回 null</summary>
        public static int? ChannelId(string target)
        {
            const string prefix = "channel:";
            if (string.IsNullOrEmpty(target) || !target.StartsWith(prefix, StringComparison.Ordinal)) return null;
            int id;
            if (int.TryParse(target.Substring(prefix.Length), NumberStyles.Integer, CultureInfo.InvariantCulture, out id)) return id;
            return null;
        }

        public static string Symbol(PlansPayload payload)
        {
            if (payload != null && !string.IsNullOrEmpty(payload.CurrencySymbol)) return payload.CurrencySymbol;
            return "¥";
        }

        /// <summary>用系统默认浏览器打开支付页（对应 iOS 的内置浏览器 sheet）</summary>
        public static void OpenPayUrl(string url)
        {
            if (string.IsNullOrEmpty(url)) return;
            try
            {
                System.Diagnostics.Process.Start(url);
            }
            catch (Exception error)
            {
                AppState.Shared.Report(error);
            }
        }

        /// <summary>圆形单选标记（对应 iOS 的 checkmark.circle.fill / circle）</summary>
        public static UIElement SelectionMark(bool selected, double size = 18)
        {
            if (selected) return Ui.Icon("checkCircle", size, Ui.P.Primary, 2);
            return new Border
            {
                Width = size,
                Height = size,
                CornerRadius = new CornerRadius(size / 2),
                BorderBrush = Ui.B(Ui.Alpha(Ui.P.MutedForeground, 0.5)),
                BorderThickness = new Thickness(1.5),
                Background = Brushes.Transparent,
                VerticalAlignment = VerticalAlignment.Center,
            };
        }

        /// <summary>小尺寸胶囊支付方式按钮</summary>
        public static Border MethodChip(Method option, bool selected, Action onClick)
        {
            var row = Ui.Stack(Orientation.Horizontal, 0);
            row.VerticalAlignment = VerticalAlignment.Center;
            row.AddRow(Ui.Icon(option.Icon, 12, selected ? Colors.White : Ui.P.SecondaryText, 2), 5);
            row.AddRow(Ui.Text(option.Name, 13, FontWeights.Medium, selected ? Colors.White : Ui.P.SecondaryText), 5);

            var chip = new Border
            {
                Height = 34,
                CornerRadius = new CornerRadius(17),
                Background = Ui.B(selected ? Ui.P.Primary : Ui.Alpha(Ui.P.Muted, 0.6)),
                Padding = new Thickness(12, 0, 12, 0),
                Child = new Grid { Children = { row } },
                SnapsToDevicePixels = true,
            };
            chip.Clickable(onClick, 0.96);
            return chip;
        }

        /// <summary>套餐页支付接口行（余额抵扣为其中一项，含不可选态）</summary>
        public static Border TargetRow(Target option, bool selected)
        {
            return BuildTargetRow(option, selected, true);
        }

        /// <summary>充值页支付接口行（充值场景无余额抵扣，不展示不可选态）</summary>
        public static Border RechargeTargetRow(Target option, bool selected)
        {
            return BuildTargetRow(option, selected, false);
        }

        static Border BuildTargetRow(Target option, bool selected, bool withDisabled)
        {
            var tile = Ui.IconTile(option.Icon, option.Disabled ? DS.IconColor.Slate : option.Tint);

            var texts = Ui.Stack(Orientation.Vertical, 0);
            texts.AddRow(Ui.Text(option.Name, DS.FontSize.Body, FontWeights.Normal,
                option.Disabled ? Ui.P.MutedForeground : Ui.P.Foreground), 2);
            var detail = Ui.Text(option.Detail, DS.FontSize.Caption, FontWeights.Normal,
                Ui.P.MutedForeground, TextWrapping.Wrap);
            detail.MaxHeight = 32;
            texts.AddRow(detail, 2);

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            Grid.SetColumn(tile, 0);
            grid.Children.Add(tile);

            var textsHost = new Border
            {
                Child = texts,
                Padding = new Thickness(10, 0, 8, 0),
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(textsHost, 1);
            grid.Children.Add(textsHost);

            var mark = SelectionMark(selected);
            ((FrameworkElement)mark).VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(mark, 2);
            grid.Children.Add(mark);

            var border = Ui.Box(grid,
                selected ? Ui.Alpha(Ui.P.Primary, 0.10) : Ui.P.Card,
                DS.Radius.Lg,
                selected ? Ui.P.Primary : Ui.P.Border,
                1,
                new Thickness(12, 10, 12, 10));
            if (withDisabled && option.Disabled) border.Opacity = 0.6;
            return border;
        }
    }

    // MARK: - 套餐购买（Tab 根页）

    public class PlansView : Screen
    {
        PlansPayload _payload;
        bool _loading = true;
        bool _inFlight;
        bool _paying;

        /// <summary>所选支付接口（"balance" 表示余额抵扣）</summary>
        string _payTarget = "";
        string _selectedMethod = "alipay";
        PlansPay.Pending _pendingPay;

        public PlansView()
        {
            HidesHeader = true;
            Content = Ui.ScrollPage(C.LoadingBlock("正在获取套餐…"));
        }

        public override void OnAppear()
        {
            Ui.Fire(Load);
        }

        // MARK: - 内容构建

        void Rebuild()
        {
            var body = Ui.Stack(Orientation.Vertical, 0);
            body.Margin = new Thickness(0, 12, 0, 24);

            body.AddRow(Ui.Text("套餐中心", DS.FontSize.Title, FontWeights.Bold, Ui.P.Foreground), DS.Size.GapLarge);

            if (_payload != null) body.AddRow(BuildOverview(_payload), DS.Size.GapLarge);
            if (_payload != null && !_payload.PurchaseEnabled)
                body.AddRow(C.BannerBar("站点当前已关闭购买功能", BannerKind.Warning), DS.Size.GapLarge);

            if (_loading && _payload == null)
            {
                body.AddRow(C.LoadingBlock("正在获取套餐…"), DS.Size.GapLarge);
            }
            else if (_payload == null || _payload.Plans.Count == 0)
            {
                body.AddRow(C.EmptyHint("tabPlans", "暂无可购买套餐", "请联系管理员配置套餐"), DS.Size.GapLarge);
            }
            else
            {
                foreach (var plan in _payload.Plans)
                    body.AddRow(PlanCard(plan), DS.Size.GapLarge);
            }

            Content = Ui.ScrollPage(body);
        }

        /// <summary>站点 / 账户概览（节点在线、等级、金币、余额）</summary>
        UIElement BuildOverview(PlansPayload payload)
        {
            int level = payload.User != null ? payload.User.Level : 0;
            int coins = payload.User != null ? payload.User.Coins : 0;
            int balanceCents = payload.User != null ? payload.User.BalanceCents : 0;
            var symbol = PlansPay.Symbol(payload);

            var head = Ui.Stack(Orientation.Horizontal, 0);
            head.AddRow(Ui.IconTile("server", DS.IconColor.Green), 10);
            var headTexts = Ui.Stack(Orientation.Vertical, 0);
            headTexts.AddRow(Ui.Caption("节点在线"), 2);
            headTexts.AddRow(Ui.Text(payload.NodeOnline + " / " + payload.NodeTotal + " 在线",
                DS.FontSize.Body, FontWeights.Medium, Ui.P.Foreground), 2);
            head.AddRow(headTexts, 10);

            var stats = StatRow(
                StatCell("账户等级", "Lv." + level, DS.IconColor.Cyan),
                StatCell("金币", coins.ToString(CultureInfo.InvariantCulture), DS.IconColor.Amber),
                StatCell("余额", Format.Money(balanceCents, symbol), DS.IconColor.Green));

            var stack = Ui.Stack(Orientation.Vertical, 0);
            stack.AddRow(head, 12);
            stack.AddRow(stats, 12);
            return C.Card(stack);
        }

        static UIElement StatCell(string label, string value, Color color)
        {
            var texts = Ui.Stack(Orientation.Vertical, 0);
            texts.AddRow(Ui.Caption(label), 3);
            texts.AddRow(Ui.Text(value, DS.FontSize.Body, FontWeights.SemiBold, color), 3);
            return Ui.Box(texts, Ui.P.Muted, DS.Radius.Md, null, 0, new Thickness(10, 8, 10, 8));
        }

        static Grid StatRow(UIElement first, UIElement second, UIElement third)
        {
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            ((FrameworkElement)first).Margin = new Thickness(0, 0, 5, 0);
            ((FrameworkElement)second).Margin = new Thickness(5, 0, 5, 0);
            ((FrameworkElement)third).Margin = new Thickness(5, 0, 0, 0);
            Grid.SetColumn(first, 0); grid.Children.Add(first);
            Grid.SetColumn(second, 1); grid.Children.Add(second);
            Grid.SetColumn(third, 2); grid.Children.Add(third);
            return grid;
        }

        UIElement PlanCard(PlanItem plan)
        {
            var symbol = PlansPay.Symbol(_payload);

            // 标题行：图标 + 名称 / 当前套餐徽章 + 赠送等级徽章，右侧价格
            var titleArea = Ui.Stack(Orientation.Horizontal, 0);
            titleArea.AddRow(Ui.IconTile(plan.IsCurrent ? "checkCircle" : "gift",
                plan.IsCurrent ? DS.IconColor.Green : DS.IconColor.Teal), 10);

            var nameRow = Ui.Stack(Orientation.Horizontal, 0);
            nameRow.AddRow(Ui.Text(plan.Name, DS.FontSize.Section, FontWeights.SemiBold, Ui.P.Foreground), 6);
            if (plan.IsCurrent)
                nameRow.AddRow(C.StatusBadge("当前套餐", Ui.P.OnlineBg, Ui.P.OnlineText), 6);

            var titleTexts = Ui.Stack(Orientation.Vertical, 0);
            titleTexts.AddRow(nameRow, 4);
            titleTexts.AddRow(C.StatusBadge("赠 Lv." + plan.LevelValue,
                Ui.Alpha(DS.IconColor.Teal, 0.14), DS.IconColor.Teal), 4);
            titleArea.AddRow(titleTexts, 10);

            var price = Ui.Text(Format.Money(plan.PriceCents, symbol), 18, FontWeights.SemiBold, DS.IconColor.Orange);
            price.VerticalAlignment = VerticalAlignment.Top;

            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(titleArea, 0); header.Children.Add(titleArea);
            Grid.SetColumn(price, 1); header.Children.Add(price);

            var info = Ui.Stack(Orientation.Vertical, 0);
            info.AddRow(C.InfoRow("时长", plan.DurationDays + " 天"), 6);
            info.AddRow(C.InfoRow("流量", Format.Traffic(plan.TrafficBytes)), 6);
            info.AddRow(C.InfoRow("限速", Format.Speed(plan.SpeedLimitKbps)), 6);
            info.AddRow(C.InfoRow("设备数", plan.DeviceLimit > 0 ? plan.DeviceLimit + " 台" : "不限"), 6);
            info.AddRow(C.InfoRow("赠送等级", "Lv." + plan.LevelValue + " 等级"), 6);
            if (plan.BonusCoinsValue > 0)
                info.AddRow(C.InfoRow("赠送金币", plan.BonusCoinsValue + " 金币", DS.IconColor.Orange), 6);

            var body = Ui.Stack(Orientation.Vertical, 0);
            body.AddRow(header, 10);
            body.AddRow(info, 10);

            if (!string.IsNullOrEmpty(plan.Description))
            {
                var note = Ui.Stack(Orientation.Vertical, 0);
                note.Margin = new Thickness(0, 2, 0, 0);
                note.AddRow(Ui.Caption("备注"), 3);
                note.AddRow(Ui.Text(plan.Description, DS.FontSize.BodySmall, FontWeights.Normal,
                    Ui.P.SecondaryText, TextWrapping.Wrap), 3);
                body.AddRow(note, 10);
            }

            bool purchaseEnabled = _payload != null && _payload.PurchaseEnabled;
            if (plan.Exchangeable)
            {
                var redeem = C.Button("金币兑换 " + plan.CoinPriceValue,
                    () => Ui.Fire(() => RedeemWithCoins(plan)),
                    BtnStyle.Secondary, "coin", DS.Size.ButtonHeight, _paying);
                var buy = C.Button("立即购买", () => OpenPaymentSheet(plan),
                    BtnStyle.Primary, "card", DS.Size.ButtonHeight, _paying, !purchaseEnabled);
                body.AddRow(TwoButtons(redeem, buy), 10);
            }
            else
            {
                body.AddRow(C.Button("立即购买", () => OpenPaymentSheet(plan),
                    BtnStyle.Primary, "card", DS.Size.ButtonHeight, _paying, !purchaseEnabled), 10);
            }

            return C.Card(body);
        }

        static Grid TwoButtons(UIElement first, UIElement second)
        {
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            ((FrameworkElement)first).Margin = new Thickness(0, 0, 5, 0);
            ((FrameworkElement)second).Margin = new Thickness(5, 0, 0, 0);
            Grid.SetColumn(first, 0); grid.Children.Add(first);
            Grid.SetColumn(second, 1); grid.Children.Add(second);
            return grid;
        }

        // MARK: - 付款方式选择弹窗

        void OpenPaymentSheet(PlanItem plan)
        {
            EnsureTargetSelection(plan.PriceCents);

            var body = Ui.Stack(Orientation.Vertical, 0);
            Action refresh = null;
            refresh = () => PopulatePaymentSheet(body, plan, refresh);
            refresh();

            MainShell.PresentSheet("选择支付接口", body, OnPaymentSheetClosed);
        }

        /// <summary>弹窗关闭：若已确认支付请求，则开始创建订单（对应 iOS sheet onDismiss）</summary>
        void OnPaymentSheetClosed()
        {
            var pending = _pendingPay;
            if (pending == null) return;
            _pendingPay = null;
            Ui.Fire(() => Buy(pending));
        }

        void PopulatePaymentSheet(StackPanel body, PlanItem plan, Action refresh)
        {
            var channels = Channels();
            int balanceCents = _payload != null && _payload.User != null ? _payload.User.BalanceCents : 0;
            var options = PlansPay.TargetOptions(plan.PriceCents, balanceCents, channels);
            var methods = PlansPay.MethodsForTarget(_payTarget, channels);
            bool useBalance = _payTarget == "balance";
            bool balanceEnough = plan.PriceCents > 0 && balanceCents >= plan.PriceCents;
            bool canPay = useBalance ? balanceEnough : (!string.IsNullOrEmpty(_payTarget) && methods.Count > 0);
            var symbol = PlansPay.Symbol(_payload);

            body.Children.Clear();

            var header = Ui.Stack(Orientation.Vertical, 0);
            header.AddRow(Ui.Text("选择支付接口", DS.FontSize.Section, FontWeights.SemiBold, Ui.P.Foreground), 4);
            header.AddRow(Ui.Text(plan.Name + " · 应付 " + Format.Money(plan.PriceCents, symbol),
                DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.MutedForeground, TextWrapping.Wrap), 4);
            body.AddRow(header, DS.Size.Gap);

            var optionList = Ui.Stack(Orientation.Vertical, 0);
            foreach (var option in options)
            {
                var captured = option;
                var row = PlansPay.TargetRow(captured, _payTarget == captured.Id);
                if (!captured.Disabled)
                {
                    row.Clickable(() =>
                    {
                        _payTarget = captured.Id;
                        var available = PlansPay.MethodsForTarget(captured.Id, channels);
                        if (!available.Exists(m => m.Id == _selectedMethod))
                            _selectedMethod = available.Count > 0 ? available[0].Id : "alipay";
                        refresh();
                    }, 0.98);
                }
                optionList.AddRow(row, 8);
            }
            body.AddRow(optionList, DS.Size.Gap);

            if (options.Count == 0)
                body.AddRow(C.BannerBar("站点暂未配置支付接口，请联系管理员完成支付", BannerKind.Warning), DS.Size.Gap);

            if (useBalance)
            {
                body.AddRow(Ui.Text("将使用账户余额全额支付 " + Format.Money(plan.PriceCents, symbol) + "，确认后立即开通套餐",
                    DS.FontSize.Caption, FontWeights.Normal, Ui.P.MutedForeground, TextWrapping.Wrap), DS.Size.Gap);
            }
            else if (methods.Count > 0)
            {
                var methodBlock = Ui.Stack(Orientation.Vertical, 0);
                methodBlock.AddRow(Ui.Text("支付方式", DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.SecondaryText), 8);
                var methodRow = Ui.Stack(Orientation.Horizontal, 0);
                foreach (var option in methods)
                {
                    var captured = option;
                    methodRow.AddRow(PlansPay.MethodChip(captured, _selectedMethod == captured.Id, () =>
                    {
                        _selectedMethod = captured.Id;
                        refresh();
                    }), 8);
                }
                methodBlock.AddRow(methodRow, 8);
                body.AddRow(methodBlock, DS.Size.Gap);
            }

            if (balanceCents > 0 && !balanceEnough)
            {
                body.AddRow(Ui.Text("账户余额 ¥" + (balanceCents / 100.0).ToString("F2", CultureInfo.InvariantCulture)
                    + "，不足以全额抵扣本套餐，可先到「我的 → 余额充值」充值后再使用",
                    DS.FontSize.Caption, FontWeights.Normal, Ui.P.MutedForeground, TextWrapping.Wrap), DS.Size.Gap);
            }

            var payTitle = _paying ? "正在创建订单…" : "支付 " + Format.Money(plan.PriceCents, symbol);
            body.AddRow(C.Button(payTitle, () =>
            {
                if (!canPay) return;
                _pendingPay = new PlansPay.Pending
                {
                    Plan = plan,
                    Method = _selectedMethod,
                    ChannelId = useBalance ? (int?)null : PlansPay.ChannelId(_payTarget),
                    UseBalance = useBalance,
                };
                var shell = MainShell.Current;
                if (shell != null) shell.Sheet.Dismiss();
            }, BtnStyle.Primary, "card", DS.Size.ButtonHeight, _paying, _paying || !canPay), DS.Size.Gap);

            body.AddRow(Ui.Text(
                useBalance ? "确认后将直接从账户余额扣款并开通套餐" : "点击支付后将打开系统浏览器，在支付页面完成付款",
                DS.FontSize.Caption, FontWeights.Normal, Ui.P.MutedForeground, TextWrapping.Wrap), DS.Size.Gap);
        }

        /// <summary>默认选中第一个可用接口（没有接口时退回余额抵扣）</summary>
        void EnsureTargetSelection(int amountCents)
        {
            var channels = Channels();
            int balanceCents = _payload != null && _payload.User != null ? _payload.User.BalanceCents : 0;
            var options = PlansPay.TargetOptions(amountCents, balanceCents, channels);

            bool contains = false;
            foreach (var option in options)
            {
                if (!option.Disabled && option.Id == _payTarget) contains = true;
            }
            if (!contains)
            {
                string fallback = "";
                foreach (var option in options)
                {
                    if (!option.Disabled) { fallback = option.Id; break; }
                }
                _payTarget = fallback;
            }

            var methods = PlansPay.MethodsForTarget(_payTarget, channels);
            if (!methods.Exists(m => m.Id == _selectedMethod))
                _selectedMethod = methods.Count > 0 ? methods[0].Id : "alipay";
        }

        List<PaymentChannelItem> Channels()
        {
            if (_payload != null && _payload.PaymentChannels != null) return _payload.PaymentChannels;
            return new List<PaymentChannelItem>();
        }

        // MARK: - 网络

        async System.Threading.Tasks.Task Load()
        {
            if (_inFlight) return;
            _inFlight = true;
            _loading = true;
            Rebuild();
            try
            {
                _payload = await ApiClient.Shared.FetchPlans();
            }
            catch (Exception error)
            {
                if (ApiException.From(error).IsCancelled) return;
                App.Report(error);
            }
            finally
            {
                _inFlight = false;
                _loading = false;
                Rebuild();
            }
        }

        async System.Threading.Tasks.Task Buy(PlansPay.Pending pending)
        {
            _paying = true;
            Rebuild();
            try
            {
                var result = await ApiClient.Shared.CreateOrder(pending.Plan.Id, pending.Method, false,
                    pending.UseBalance, pending.ChannelId);
                if (result.PaidValue)
                {
                    App.ShowToast(string.IsNullOrEmpty(result.Message) ? "支付成功" : result.Message, BannerKind.Success);
                    await App.RefreshUser();
                    await Load();
                }
                else if (string.IsNullOrEmpty(result.PayUrl))
                {
                    App.ShowToast(string.IsNullOrEmpty(result.Message) ? "订单已创建，请联系管理员完成支付" : result.Message,
                        BannerKind.Warning);
                }
                else
                {
                    PlansPay.OpenPayUrl(result.PayUrl);
                    App.ShowToast("订单已创建，请在 10 分钟内完成支付", BannerKind.Info);
                    MainShell.PresentAlert("已完成支付？", "请在浏览器中完成支付后返回，点击「已支付」立即刷新套餐状态。",
                        "已支付", () => Ui.Fire(RefreshAfterPay), false, "未支付");
                }
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _paying = false;
                Rebuild();
            }
        }

        async System.Threading.Tasks.Task RefreshAfterPay()
        {
            await App.RefreshUser();
            await Load();
        }

        /// <summary>金币全额兑换（主控直接发货）</summary>
        async System.Threading.Tasks.Task RedeemWithCoins(PlanItem plan)
        {
            if (plan.CoinPriceValue <= 0) return;
            int coins = _payload != null && _payload.User != null ? _payload.User.Coins : 0;
            if (coins < plan.CoinPriceValue)
            {
                App.ShowToast("金币不足，需要 " + plan.CoinPriceValue + " 金币", BannerKind.Warning);
                return;
            }

            _paying = true;
            Rebuild();
            try
            {
                var result = await ApiClient.Shared.CreateOrder(plan.Id, "coins", true);
                App.ShowToast(string.IsNullOrEmpty(result.Message) ? "兑换成功" : result.Message, BannerKind.Success);
                await App.RefreshUser();
                await Load();
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _paying = false;
                Rebuild();
            }
        }
    }

    // MARK: - 我的订单（10 分钟支付窗口 + 继续支付 + 取消）

    public class OrdersView : Screen
    {
        OrdersPayload _payload;
        bool _loading = true;
        bool _inFlight;
        int? _busyId;
        DateTime _now = DateTime.Now;
        bool _refreshedExpired;
        readonly DispatcherTimer _ticker = new DispatcherTimer();

        public OrdersView()
        {
            HidesHeader = false;
            Title = "我的订单";
            Content = Ui.ScrollPage(C.LoadingBlock("正在获取订单…"));

            _ticker.Interval = TimeSpan.FromSeconds(1);
            _ticker.Tick += (s, e) => OnTick();
            IsVisibleChanged += (s, e) => { if (IsVisible) StartTicker(); else StopTicker(); };
        }

        public override void OnAppear()
        {
            _now = DateTime.Now;
            StartTicker();
            Ui.Fire(Load);
        }

        void StartTicker() { if (!_ticker.IsEnabled) _ticker.Start(); }
        void StopTicker() { _ticker.Stop(); }

        /// <summary>每秒刷新：更新倒计时；有 pending 订单过期时自动刷新一次列表</summary>
        void OnTick()
        {
            _now = DateTime.Now;
            if (_payload == null) return;

            bool hasPending = false;
            foreach (var order in _payload.Orders)
            {
                if (order.Status == "pending") { hasPending = true; break; }
            }
            if (!hasPending) return;

            if (!_refreshedExpired)
            {
                foreach (var order in _payload.Orders)
                {
                    if (order.Status == "pending" && RemainingSeconds(order) <= 1)
                    {
                        _refreshedExpired = true;
                        Ui.Fire(Load);
                        break;
                    }
                }
            }
            Rebuild();
        }

        // MARK: - 内容构建

        void Rebuild()
        {
            var body = Ui.Stack(Orientation.Vertical, 0);
            body.Margin = new Thickness(0, 16, 0, 16);

            if (_loading && _payload == null)
            {
                body.AddRow(C.LoadingBlock("正在获取订单…"), DS.Size.Gap);
            }
            else if (_payload == null || _payload.Orders.Count == 0)
            {
                body.AddRow(C.EmptyHint("doc", "暂无订单"), DS.Size.Gap);
            }
            else
            {
                foreach (var order in _payload.Orders)
                    body.AddRow(OrderCard(order), DS.Size.Gap);
            }

            Content = Ui.ScrollPage(body);
        }

        UIElement OrderCard(OrderItem order)
        {
            int remaining = RemainingSeconds(order);
            var body = Ui.Stack(Orientation.Vertical, 0);

            var head = new Grid();
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var tile = Ui.IconTile(OrderIcon(order), OrderColor(order));
            Grid.SetColumn(tile, 0);
            head.Children.Add(tile);

            var name = Ui.Text(string.IsNullOrEmpty(order.PlanName) ? "套餐" : order.PlanName,
                DS.FontSize.Section, FontWeights.SemiBold, Ui.P.Foreground);
            name.Margin = new Thickness(10, 0, 0, 0);
            name.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(name, 1);
            head.Children.Add(name);

            var badge = C.StatusBadge(order.StatusText, StatusBackground(order), StatusForeground(order));
            Grid.SetColumn(badge, 2);
            head.Children.Add(badge);
            body.AddRow(head, 8);

            body.AddRow(C.InfoRow("订单号", order.OrderNo), 8);
            body.AddRow(C.InfoRow("金额", Format.Money(order.AmountCents)), 8);
            body.AddRow(C.InfoRow("创建时间", Format.DateTimeText(order.CreatedAt)), 8);
            if (!string.IsNullOrEmpty(order.PaidAt))
                body.AddRow(C.InfoRow("支付时间", Format.DateTimeText(order.PaidAt)), 8);

            if (order.Status == "pending")
            {
                var countdown = new Grid();
                countdown.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                countdown.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                var label = Ui.Text("剩余支付时间", DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.MutedForeground);
                Grid.SetColumn(label, 0);
                countdown.Children.Add(label);

                TextBlock value;
                if (remaining > 0)
                    value = Ui.Text(Format.Countdown(remaining), DS.FontSize.BodySmall, FontWeights.SemiBold, DS.IconColor.Amber);
                else
                    value = Ui.Text("已过期", DS.FontSize.BodySmall, FontWeights.SemiBold, Ui.P.OfflineText);
                value.FontFamily = new FontFamily("Consolas, Segoe UI");
                value.HorizontalAlignment = HorizontalAlignment.Right;
                Grid.SetColumn(value, 1);
                countdown.Children.Add(value);
                body.AddRow(countdown, 8);

                body.AddRow(OrderActions(order, remaining), 8);
            }

            return C.Card(body);
        }

        UIElement OrderActions(OrderItem order, int remaining)
        {
            var grid = new Grid();
            if (remaining > 0)
            {
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                var pay = PayButton(order);
                pay.Margin = new Thickness(0, 0, 5, 0);
                var cancel = CancelButton(order);
                cancel.Margin = new Thickness(5, 0, 0, 0);
                Grid.SetColumn(pay, 0); grid.Children.Add(pay);
                Grid.SetColumn(cancel, 1); grid.Children.Add(cancel);
            }
            else
            {
                grid.Children.Add(CancelButton(order));
            }
            return grid;
        }

        Border PayButton(OrderItem order)
        {
            var row = Ui.Stack(Orientation.Horizontal, 0);
            row.HorizontalAlignment = HorizontalAlignment.Center;
            row.VerticalAlignment = VerticalAlignment.Center;
            if (_busyId == order.Id) row.AddRow(C.Spinner(14, Colors.White), 6);
            else row.AddRow(Ui.Icon("card", 13, Colors.White, 2), 6);
            row.AddRow(Ui.Text("继续支付", DS.FontSize.BodySmall, FontWeights.Medium, Colors.White), 6);

            var border = new Border
            {
                Height = 38,
                CornerRadius = new CornerRadius(DS.Radius.Lg),
                Background = Ui.B(DS.IconColor.Green),
                Child = new Grid { Children = { row } },
                SnapsToDevicePixels = true,
            };
            if (_busyId == null) border.Clickable(() => Ui.Fire(() => Pay(order)), 0.97);
            else border.Opacity = 0.7;
            return border;
        }

        Border CancelButton(OrderItem order)
        {
            var border = new Border
            {
                Height = 38,
                CornerRadius = new CornerRadius(DS.Radius.Lg),
                Background = Ui.B(Ui.P.Card),
                BorderBrush = Ui.B(Ui.P.Border),
                BorderThickness = new Thickness(1),
                Child = new Grid { Children = { Ui.Text("取消订单", DS.FontSize.BodySmall, FontWeights.Medium, Ui.P.Foreground) } },
                SnapsToDevicePixels = true,
            };
            if (_busyId == null) border.Clickable(() => Ui.Fire(() => Cancel(order)), 0.97);
            else border.Opacity = 0.7;
            return border;
        }

        // MARK: - 状态映射

        static string OrderIcon(OrderItem order)
        {
            switch (order.Status)
            {
                case "paid": return "checkCircle";
                case "pending": return "clock";
                case "cancelled": return "close";
                case "expired": return "clock";
                case "refunded": return "refresh";
                default: return "doc";
            }
        }

        static Color OrderColor(OrderItem order)
        {
            switch (order.Status)
            {
                case "paid": return DS.IconColor.Green;
                case "pending": return DS.IconColor.Amber;
                case "cancelled":
                case "expired": return DS.IconColor.Slate;
                default: return DS.IconColor.Cyan;
            }
        }

        static Color StatusBackground(OrderItem order)
        {
            switch (order.Status)
            {
                case "paid": return Ui.P.OnlineBg;
                case "pending": return Ui.P.WarningBg;
                default: return Ui.P.Muted;
            }
        }

        static Color StatusForeground(OrderItem order)
        {
            switch (order.Status)
            {
                case "paid": return Ui.P.OnlineText;
                case "pending": return Ui.P.WarningText;
                default: return Ui.P.MutedForeground;
            }
        }

        /// <summary>按当前时间实时计算剩余秒数（每秒刷新）</summary>
        int RemainingSeconds(OrderItem order)
        {
            if (order.Status != "pending" || string.IsNullOrEmpty(order.ExpiresAt)) return 0;
            var date = Format.Parse(order.ExpiresAt);
            if (date == null) return 0;
            return Math.Max(0, (int)Math.Round((date.Value - _now).TotalSeconds));
        }

        // MARK: - 网络

        async System.Threading.Tasks.Task Load()
        {
            if (_inFlight) return;
            _inFlight = true;
            _loading = true;
            Rebuild();
            try
            {
                _payload = await ApiClient.Shared.FetchOrders();
                _refreshedExpired = false;
            }
            catch (Exception error)
            {
                if (ApiException.From(error).IsCancelled) return;
                App.Report(error);
            }
            finally
            {
                _inFlight = false;
                _loading = false;
                Rebuild();
            }
        }

        /// <summary>继续支付（复用原订单，10 分钟内有效）</summary>
        async System.Threading.Tasks.Task Pay(OrderItem order)
        {
            _busyId = order.Id;
            Rebuild();
            try
            {
                var result = await ApiClient.Shared.PayOrder(order.Id);
                if (string.IsNullOrEmpty(result.PayUrl))
                {
                    App.ShowToast(string.IsNullOrEmpty(result.Message) ? "订单已创建，请联系管理员完成支付" : result.Message,
                        BannerKind.Warning);
                }
                else
                {
                    PlansPay.OpenPayUrl(result.PayUrl);
                    App.ShowToast("订单已创建，请在 10 分钟内完成支付", BannerKind.Info);
                    MainShell.PresentAlert("已完成支付？", "请在浏览器中完成支付后返回，点击「已支付」立即刷新订单状态。",
                        "已支付", () => Ui.Fire(RefreshAfterPay), false, "未支付");
                }
            }
            catch (Exception error)
            {
                App.Report(error);
                await Load();
            }
            finally
            {
                _busyId = null;
                Rebuild();
            }
        }

        async System.Threading.Tasks.Task RefreshAfterPay()
        {
            await App.RefreshUser();
            await Load();
        }

        async System.Threading.Tasks.Task Cancel(OrderItem order)
        {
            _busyId = order.Id;
            Rebuild();
            try
            {
                await ApiClient.Shared.CancelOrder(order.Id);
                App.ShowToast("订单已取消", BannerKind.Success);
                await Load();
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _busyId = null;
                Rebuild();
            }
        }
    }

    // MARK: - 余额充值

    public class RechargeView : Screen
    {
        static readonly double[] QuickAmounts = { 10, 30, 50, 100, 200, 500 };

        PlansPayload _payload;
        bool _loading = true;
        bool _inFlight;
        string _amountText = "30";
        string _payTarget = "";
        string _selectedMethod = "alipay";
        bool _paying;
        bool _syncing;

        TextFieldControl _amountField;
        WrapPanel _quickPanel;
        Grid _interfaceHost;
        Grid _buttonHost;

        public RechargeView()
        {
            HidesHeader = false;
            Title = "余额充值";
            Content = Ui.ScrollPage(C.LoadingBlock("正在获取充值信息…"));
        }

        public override void OnAppear()
        {
            Ui.Fire(Load);
        }

        double AmountYuan
        {
            get
            {
                var text = (_amountText ?? "").Trim();
                double value;
                if (double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value)) return value;
                return 0;
            }
        }

        // MARK: - 内容构建

        void RebuildAll()
        {
            var body = Ui.Stack(Orientation.Vertical, 0);
            body.Margin = new Thickness(0, 8, 0, 24);

            if (_loading && _payload == null)
            {
                body.AddRow(C.LoadingBlock("正在获取充值信息…"), DS.Size.GapLarge);
            }
            else
            {
                body.AddRow(BuildBalanceCard(), DS.Size.GapLarge);

                _quickPanel = new WrapPanel { Margin = new Thickness(0, 10, 0, 0) };
                _amountField = C.TextField("充值金额（元）", "请输入充值金额（最少 1 元）", _amountText, false, OnAmountChanged);
                body.AddRow(BuildAmountCard(), DS.Size.GapLarge);

                _interfaceHost = new Grid();
                var interfaceCard = Ui.Stack(Orientation.Vertical, 0);
                interfaceCard.AddRow(Ui.Text("支付接口", DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.SecondaryText), DS.Size.Gap);
                interfaceCard.AddRow(_interfaceHost, DS.Size.Gap);
                body.AddRow(C.Card(interfaceCard), DS.Size.GapLarge);
                PopulateInterface();

                _buttonHost = new Grid();
                body.AddRow(_buttonHost, DS.Size.GapLarge);
                PopulateButton();

                body.AddRow(Ui.Text("充值成功后余额将实时到账，可在购买套餐时选择「余额抵扣」全额支付",
                    DS.FontSize.Caption, FontWeights.Normal, Ui.P.MutedForeground, TextWrapping.Wrap), DS.Size.GapLarge);
            }

            Content = Ui.ScrollPage(body);
        }

        UIElement BuildBalanceCard()
        {
            int balanceCents = _payload != null && _payload.User != null ? _payload.User.BalanceCents : 0;

            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var tile = Ui.IconTile("coin", DS.IconColor.Green, 40);
            Grid.SetColumn(tile, 0); row.Children.Add(tile);

            var texts = Ui.Stack(Orientation.Vertical, 0);
            texts.AddRow(Ui.Caption("账户余额"), 3);
            var money = Ui.Text(Format.Money(balanceCents, PlansPay.Symbol(_payload)), 20, FontWeights.SemiBold, Ui.P.Foreground);
            money.FontFamily = new FontFamily("Consolas, Segoe UI");
            texts.AddRow(money, 3);
            var textsHost = new Border { Child = texts, Padding = new Thickness(12, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(textsHost, 1); row.Children.Add(textsHost);

            var badge = C.StatusBadge("可用于抵扣套餐", Ui.P.OnlineBg, Ui.P.OnlineText);
            Grid.SetColumn(badge, 2); row.Children.Add(badge);

            return C.Card(row);
        }

        UIElement BuildAmountCard()
        {
            var stack = Ui.Stack(Orientation.Vertical, 0);
            stack.AddRow(_amountField, 10);
            stack.AddRow(_quickPanel, 10);
            PopulateQuick();
            return C.Card(stack);
        }

        /// <summary>快捷金额：金额与单位同一行展示，一行放不下时整块自动换行</summary>
        void PopulateQuick()
        {
            if (_quickPanel == null) return;
            _quickPanel.Children.Clear();
            foreach (var amount in QuickAmounts)
            {
                var text = amount.ToString("F0", CultureInfo.InvariantCulture);
                bool selected = _amountText == text;

                var label = Ui.Text(text + " 元", 13, FontWeights.Medium,
                    selected ? Colors.White : Ui.P.SecondaryText);
                label.Margin = new Thickness(12, 0, 12, 0);

                var chip = new Border
                {
                    Height = 32,
                    CornerRadius = new CornerRadius(16),
                    Background = Ui.B(selected ? Ui.P.Primary : Ui.Alpha(Ui.P.Muted, 0.6)),
                    Child = new Grid { Children = { label } },
                    Margin = new Thickness(0, 0, 8, 8),
                    SnapsToDevicePixels = true,
                };
                var captured = text;
                chip.Clickable(() => ApplyQuick(captured), 0.96);
                _quickPanel.Children.Add(chip);
            }
        }

        void PopulateInterface()
        {
            if (_interfaceHost == null) return;
            _interfaceHost.Children.Clear();

            var channels = Channels();
            var options = PlansPay.TargetOptions(0, 0, channels);
            var methods = PlansPay.MethodsForTarget(_payTarget, channels);

            var stack = Ui.Stack(Orientation.Vertical, 0);
            if (options.Count == 0)
            {
                stack.AddRow(C.BannerBar("站点暂未配置支付接口，请联系管理员完成充值", BannerKind.Warning), DS.Size.Gap);
            }
            else
            {
                var list = Ui.Stack(Orientation.Vertical, 0);
                foreach (var option in options)
                {
                    var captured = option;
                    var row = PlansPay.RechargeTargetRow(captured, _payTarget == captured.Id);
                    row.Clickable(() => SelectTarget(captured.Id), 0.98);
                    list.AddRow(row, 8);
                }
                stack.AddRow(list, DS.Size.Gap);
            }

            if (methods.Count > 0 && !string.IsNullOrEmpty(_payTarget))
            {
                var methodBlock = Ui.Stack(Orientation.Vertical, 0);
                var methodLabel = Ui.Text("支付方式", DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.SecondaryText);
                methodLabel.Margin = new Thickness(0, 2, 0, 0);
                methodBlock.AddRow(methodLabel, 8);

                var row = Ui.Stack(Orientation.Horizontal, 0);
                foreach (var option in methods)
                {
                    var captured = option;
                    row.AddRow(PlansPay.MethodChip(captured, _selectedMethod == captured.Id,
                        () => SelectMethod(captured.Id)), 8);
                }
                methodBlock.AddRow(row, 8);
                stack.AddRow(methodBlock, DS.Size.Gap);
            }

            _interfaceHost.Children.Add(stack);
        }

        void PopulateButton()
        {
            if (_buttonHost == null) return;
            _buttonHost.Children.Clear();

            double amount = AmountYuan;
            var title = _paying
                ? "正在创建订单…"
                : "去支付 " + Format.Money((int)Math.Round(amount * 100), PlansPay.Symbol(_payload));
            bool disabled = _paying || amount < 1 || string.IsNullOrEmpty(_payTarget);
            _buttonHost.Children.Add(C.Button(title, () => Ui.Fire(Recharge), BtnStyle.Primary, "card",
                DS.Size.ButtonHeight, _paying, disabled));
        }

        // MARK: - 交互

        void OnAmountChanged(string text)
        {
            _amountText = text;
            if (_syncing) return;
            PopulateQuick();
            PopulateButton();
        }

        void ApplyQuick(string text)
        {
            _amountText = text;
            _syncing = true;
            if (_amountField != null) _amountField.Value = text;
            _syncing = false;
            PopulateQuick();
            PopulateButton();
        }

        void SelectTarget(string id)
        {
            _payTarget = id;
            var available = PlansPay.MethodsForTarget(id, Channels());
            if (!available.Exists(m => m.Id == _selectedMethod))
                _selectedMethod = available.Count > 0 ? available[0].Id : "alipay";
            PopulateInterface();
            PopulateButton();
        }

        void SelectMethod(string id)
        {
            _selectedMethod = id;
            PopulateInterface();
        }

        void EnsureTargetSelection()
        {
            var channels = Channels();
            var options = PlansPay.TargetOptions(0, 0, channels);

            bool contains = false;
            foreach (var option in options)
            {
                if (option.Id == _payTarget) contains = true;
            }
            if (!contains) _payTarget = options.Count > 0 ? options[0].Id : "";

            var methods = PlansPay.MethodsForTarget(_payTarget, channels);
            if (!methods.Exists(m => m.Id == _selectedMethod))
                _selectedMethod = methods.Count > 0 ? methods[0].Id : "alipay";
        }

        List<PaymentChannelItem> Channels()
        {
            if (_payload != null && _payload.PaymentChannels != null) return _payload.PaymentChannels;
            return new List<PaymentChannelItem>();
        }

        // MARK: - 网络

        async System.Threading.Tasks.Task Load()
        {
            if (_inFlight) return;
            _inFlight = true;
            _loading = true;
            RebuildAll();
            try
            {
                _payload = await ApiClient.Shared.FetchPlans();
                EnsureTargetSelection();
            }
            catch (Exception error)
            {
                if (ApiException.From(error).IsCancelled) return;
                App.Report(error);
            }
            finally
            {
                _inFlight = false;
                _loading = false;
                RebuildAll();
            }
        }

        async System.Threading.Tasks.Task Recharge()
        {
            double amount = AmountYuan;
            if (amount < 1)
            {
                App.ShowToast("单次充值金额不得少于 1 元", BannerKind.Warning);
                return;
            }
            if (string.IsNullOrEmpty(_payTarget))
            {
                App.ShowToast("请选择支付接口", BannerKind.Warning);
                return;
            }

            _paying = true;
            PopulateButton();
            try
            {
                var result = await ApiClient.Shared.RechargeBalance(amount, _selectedMethod, PlansPay.ChannelId(_payTarget));
                if (string.IsNullOrEmpty(result.PayUrl))
                {
                    App.ShowToast(string.IsNullOrEmpty(result.Message) ? "订单已创建，请联系管理员完成支付" : result.Message,
                        BannerKind.Warning);
                }
                else
                {
                    PlansPay.OpenPayUrl(result.PayUrl);
                    App.ShowToast("订单已创建，请在 10 分钟内完成支付", BannerKind.Info);
                    MainShell.PresentAlert("已完成支付？", "请在浏览器中完成支付后返回，点击「已支付」立即刷新余额。",
                        "已支付", () => Ui.Fire(RefreshAfterPay), false, "未支付");
                }
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _paying = false;
                PopulateButton();
            }
        }

        async System.Threading.Tasks.Task RefreshAfterPay()
        {
            await App.RefreshUser();
            await Load();
        }
    }
}
