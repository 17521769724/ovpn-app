using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using OVPNPanel.Theme;

namespace OVPNPanel.Core
{
    // MARK: - 公告

    /// <summary>公告列表：置顶 / 未读标记，点击卡片标记已读（对应 iOS AnnouncementsView）</summary>
    public class AnnouncementsView : Screen
    {
        readonly Grid _host = new Grid();
        readonly HashSet<int> _expanded = new HashSet<int>();
        AnnouncementsPayload _payload;
        bool _loading = true;
        bool _loaded;

        public AnnouncementsView()
        {
            HidesHeader = false;
            Title = "公告";
            _host.Margin = new Thickness(0, DS.Size.Gap, 0, 24);
            Content = Ui.ScrollPage(_host);
            Rebuild();
        }

        public override void OnAppear()
        {
            if (_loaded) return;
            _loaded = true;
            Ui.Fire(Load);
        }

        void Rebuild()
        {
            _host.Children.Clear();
            var stack = Ui.Stack(Orientation.Vertical, DS.Size.Gap);

            var items = _payload != null ? _payload.Announcements : new List<Announcement>();
            if (_loading && _payload == null)
            {
                stack.AddRow(C.LoadingBlock("正在获取公告…"), DS.Size.Gap);
            }
            else if (items.Count == 0)
            {
                stack.AddRow(C.EmptyHint("megaphone", "暂无公告"), DS.Size.Gap);
            }
            else
            {
                if (_payload.UnreadCount > 0)
                    stack.AddRow(C.BannerBar("有 " + _payload.UnreadCount + " 条未读公告", BannerKind.Warning), DS.Size.Gap);
                for (int i = 0; i < items.Count; i++)
                    stack.AddRow(AnnouncementCard(items[i]), DS.Size.Gap);
            }

            _host.Children.Add(stack);
        }

        UIElement AnnouncementCard(Announcement item)
        {
            var palette = Ui.P;
            bool expanded = _expanded.Contains(item.Id);

            var head = new Grid();
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            if (item.IsTop)
            {
                var badge = C.StatusBadge("置顶", palette.Muted, palette.Foreground);
                badge.Margin = new Thickness(0, 0, 6, 0);
                Grid.SetColumn(badge, 0);
                head.Children.Add(badge);
            }

            var title = Ui.Text(item.Title, DS.FontSize.Section, FontWeights.SemiBold, palette.Foreground, TextWrapping.Wrap);
            title.Margin = new Thickness(0, 0, 8, 0);
            Grid.SetColumn(title, 1);
            head.Children.Add(title);

            if (!item.Read)
            {
                var dot = new Border
                {
                    Width = 7,
                    Height = 7,
                    CornerRadius = new CornerRadius(4),
                    Background = Ui.B(palette.Destructive),
                    VerticalAlignment = VerticalAlignment.Center,
                };
                Grid.SetColumn(dot, 2);
                head.Children.Add(dot);
            }

            var body = Ui.Text(item.Content, DS.FontSize.BodySmall, FontWeights.Normal,
                palette.MutedForeground, TextWrapping.Wrap);
            body.LineHeight = 18;
            if (!expanded) body.MaxHeight = 54;

            var toggle = Ui.Text(expanded ? "收起" : "展开", DS.FontSize.Caption, FontWeights.Normal, palette.Foreground);
            toggle.Padding = new Thickness(8, 2, 0, 2);
            toggle.Clickable(() =>
            {
                if (_expanded.Contains(item.Id)) _expanded.Remove(item.Id);
                else _expanded.Add(item.Id);
                Rebuild();
            }, 0.95);

            var foot = Ui.Split(Ui.Caption(Format.DateTimeText(item.CreatedAt)), toggle);

            var card = C.Card(Ui.Stack(Orientation.Vertical, 8, head, body, foot));
            card.Clickable(() => Ui.Fire(() => MarkRead(item.Id)));
            return card;
        }

        async Task Load()
        {
            _loading = true;
            try
            {
                _payload = await ApiClient.Shared.FetchAnnouncements();
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _loading = false;
                Rebuild();
            }
        }

        async Task MarkRead(int id)
        {
            if (_payload == null || _payload.UnreadIds == null || !_payload.UnreadIds.Contains(id)) return;
            try { await ApiClient.Shared.MarkAnnouncementsRead(new List<int> { id }); }
            catch { }
            await Load();
        }
    }

    // MARK: - 激活码

    /// <summary>激活码：输入 / 预览 / 兑换 + 兑换记录（对应 iOS ActivationView）</summary>
    public class ActivationView : Screen
    {
        readonly Grid _host = new Grid();
        readonly TextFieldControl _codeField;
        readonly List<ActivationRecord> _records = new List<ActivationRecord>();
        ActivationRedeemResult _result;
        bool _submitting;
        bool _loaded;

        public ActivationView()
        {
            HidesHeader = false;
            Title = "激活码";
            _codeField = C.TextField("激活码", "OVPN-XXXX-XXXX-XXXX", "");
            _host.Margin = new Thickness(0, DS.Size.Gap, 0, 24);
            Content = Ui.ScrollPage(_host);
            Rebuild();
        }

        public override void OnAppear()
        {
            if (_loaded) return;
            _loaded = true;
            Ui.Fire(Load);
        }

        void Rebuild()
        {
            _host.Children.Clear();
            var palette = Ui.P;
            var stack = Ui.Stack(Orientation.Vertical, DS.Size.GapLarge);

            // 兑换输入卡片
            var form = Ui.Stack(Orientation.Vertical, 12);
            form.Children.Add(Ui.Stack(Orientation.Horizontal, 10,
                Ui.IconTile("ticket", DS.IconColor.Amber),
                C.SectionHeader("兑换激活码", "输入管理员发放的激活码")));
            form.Children.Add(_codeField);
            form.Children.Add(C.Button("立即兑换", () => Ui.Fire(Redeem), BtnStyle.Primary, "ticket",
                DS.Size.ButtonHeight, _submitting, _submitting));
            stack.AddRow(C.Card(form), DS.Size.GapLarge);

            // 兑换结果
            if (_result != null)
            {
                var result = Ui.Stack(Orientation.Vertical, 8);
                result.Children.Add(C.SectionHeader(_result.Extend ? "已叠加到当前套餐" : "兑换成功"));
                result.AddRow(C.InfoRow("套餐", _result.PlanName), 8);
                result.AddRow(C.InfoRow("时长", _result.DurationDays + " 天"), 8);
                result.AddRow(C.InfoRow("流量", Format.Traffic(_result.TrafficBytes)), 8);
                result.AddRow(C.InfoRow("到期时间", Format.DateOnly(_result.ExpiresAt)), 8);
                stack.AddRow(C.Card(result), DS.Size.GapLarge);
            }

            // 兑换记录卡片
            var records = Ui.Stack(Orientation.Vertical, 10);
            records.Children.Add(C.SectionHeader("兑换记录"));
            if (_records.Count == 0)
            {
                records.AddRow(Ui.Text("暂无兑换记录", DS.FontSize.BodySmall, FontWeights.Normal,
                    palette.MutedForeground), 10);
            }
            else
            {
                for (int i = 0; i < _records.Count; i++)
                    records.AddRow(RecordRow(_records[i]), 10);
            }
            stack.AddRow(C.Card(records), DS.Size.GapLarge);

            _host.Children.Add(stack);
        }

        UIElement RecordRow(ActivationRecord record)
        {
            var palette = Ui.P;
            var row = Ui.Stack(Orientation.Vertical, 5);

            var codeText = Ui.Text(record.Code, 12, FontWeights.Normal, palette.Foreground);
            codeText.FontFamily = new FontFamily("Consolas, Cascadia Mono, Courier New");
            row.Children.Add(Ui.Split(codeText, Ui.Caption(Format.DateTimeText(record.UsedAt))));
            row.AddRow(C.InfoRow("套餐", record.PlanName), 5);
            row.AddRow(C.InfoRow("时长", record.DurationDays + " 天"), 5);
            row.Margin = new Thickness(0, 5, 0, 5);
            return row;
        }

        async Task Load()
        {
            try { _records.Clear(); _records.AddRange(await ApiClient.Shared.FetchActivationRecords()); }
            catch { }
            Rebuild();
        }

        async Task Redeem()
        {
            var value = (_codeField.Value ?? "").Trim();
            if (value.Length == 0)
            {
                App.ShowToast("请输入激活码", BannerKind.Warning);
                return;
            }
            _submitting = true;
            _result = null;
            Rebuild();
            try
            {
                var preview = await ApiClient.Shared.PreviewActivation(value);
                if (preview == null || !preview.Valid)
                {
                    App.ShowToast(preview == null ? "激活码无效" : preview.Message, BannerKind.Error);
                    return;
                }
                var redeemResult = await ApiClient.Shared.RedeemActivation(value);
                _result = redeemResult;
                App.ShowToast("兑换成功：" + redeemResult.PlanName, BannerKind.Success);
                _codeField.Value = "";
                await Load();
                await App.RefreshUser();
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _submitting = false;
                Rebuild();
            }
        }
    }

    // MARK: - 金币记录

    /// <summary>金币记录：只展示金币余额与流水（对应 iOS CoinsView）</summary>
    public class CoinsView : Screen
    {
        readonly Grid _host = new Grid();
        CoinsPayload _payload;
        bool _loading = true;
        bool _loaded;

        public CoinsView()
        {
            HidesHeader = false;
            Title = "金币记录";
            _host.Margin = new Thickness(0, 8, 0, 24);
            Content = Ui.ScrollPage(_host);
            Rebuild();
        }

        public override void OnAppear()
        {
            if (_loaded) return;
            _loaded = true;
            Ui.Fire(Load);
        }

        void Rebuild()
        {
            _host.Children.Clear();
            var stack = Ui.Stack(Orientation.Vertical, DS.Size.GapLarge);
            stack.AddRow(BalanceCard(), DS.Size.GapLarge);
            stack.AddRow(LogsCard(), DS.Size.GapLarge);
            _host.Children.Add(stack);
        }

        UIElement BalanceCard()
        {
            var palette = Ui.P;
            var inner = Ui.Stack(Orientation.Vertical, 12);

            var left = Ui.Stack(Orientation.Vertical, 4);
            left.Children.Add(Ui.Text("我的金币", DS.FontSize.Caption, FontWeights.Normal, palette.MutedForeground));
            var number = Ui.Text((_payload != null ? _payload.Coins : 0).ToString(), 28, FontWeights.SemiBold, DS.IconColor.Orange);
            number.TextAlignment = TextAlignment.Left;
            left.Children.Add(number);

            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(left, 0);
            row.Children.Add(left);
            var icon = Ui.Icon("coin", 32, DS.IconColor.Orange, 1.8);
            icon.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(icon, 1);
            row.Children.Add(icon);
            inner.Children.Add(row);

            if (_payload != null && _payload.CoinExchangeEnabled)
                inner.AddRow(C.BannerBar("金币可在「套餐中心」兑换支持的套餐", BannerKind.Info), 12);

            return C.Card(inner);
        }

        UIElement LogsCard()
        {
            var palette = Ui.P;
            var inner = Ui.Stack(Orientation.Vertical, 10);
            inner.Children.Add(Ui.Stack(Orientation.Horizontal, 10,
                Ui.IconTile("list", DS.IconColor.Teal),
                C.SectionHeader("金币流水")));

            var logs = _payload != null ? _payload.Logs : new List<CoinLog>();
            if (_loading && _payload == null)
            {
                inner.AddRow(C.LoadingBlock(), 10);
            }
            else if (logs.Count == 0)
            {
                var empty = Ui.Text("暂无流水记录", DS.FontSize.BodySmall, FontWeights.Normal, palette.MutedForeground);
                empty.Margin = new Thickness(0, 4, 0, 4);
                inner.AddRow(empty, 10);
            }
            else
            {
                for (int i = 0; i < logs.Count; i++)
                {
                    if (i > 0)
                        inner.AddRow(new Rectangle { Height = 1, Fill = Ui.B(palette.Border) }, 10);
                    inner.AddRow(LogRow(logs[i]), 10);
                }
            }

            return C.Card(inner);
        }

        UIElement LogRow(CoinLog log)
        {
            var palette = Ui.P;
            bool positive = log.Amount >= 0;

            var arrow = Ui.Icon(positive ? "chevronDown" : "chevronUp", 15,
                positive ? palette.OnlineText : DS.IconColor.Orange, 2);
            arrow.VerticalAlignment = VerticalAlignment.Center;

            var texts = Ui.Stack(Orientation.Vertical, 2);
            var reason = Ui.Text(string.IsNullOrEmpty(log.Reason) ? "金币变动" : log.Reason,
                DS.FontSize.BodySmall, FontWeights.Normal, palette.Foreground, TextWrapping.Wrap);
            reason.MaxHeight = 36;
            texts.Children.Add(reason);
            texts.Children.Add(Ui.Caption(Format.DateTimeText(log.CreatedAt)));

            var right = Ui.Stack(Orientation.Vertical, 2);
            var amount = Ui.Text(positive ? "+" + log.Amount : log.Amount.ToString(),
                DS.FontSize.Body, FontWeights.SemiBold, positive ? palette.OnlineText : palette.OfflineText);
            amount.HorizontalAlignment = HorizontalAlignment.Right;
            right.Children.Add(amount);
            var balance = Ui.Caption("余额 " + log.Balance);
            balance.HorizontalAlignment = HorizontalAlignment.Right;
            right.Children.Add(balance);

            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(arrow, 0);
            row.Children.Add(arrow);
            Grid.SetColumn(texts, 1);
            texts.Margin = new Thickness(10, 0, 8, 0);
            row.Children.Add(texts);
            Grid.SetColumn(right, 2);
            right.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(right);
            row.Margin = new Thickness(0, 8, 0, 8);
            return row;
        }

        async Task Load()
        {
            _loading = true;
            try
            {
                _payload = await ApiClient.Shared.FetchCoins();
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _loading = false;
                Rebuild();
            }
        }
    }

    // MARK: - 反馈

    /// <summary>问题反馈：提交表单 + 我的反馈列表（对应 iOS FeedbackView）</summary>
    public class FeedbackView : Screen
    {
        readonly Grid _host = new Grid();
        readonly TextFieldControl _titleField;
        readonly TextFieldControl _contactField;
        readonly TextBox _contentBox;
        readonly List<FeedbackItem> _items = new List<FeedbackItem>();
        string _content = "";
        bool _submitting;
        bool _loaded;

        public FeedbackView()
        {
            HidesHeader = false;
            Title = "问题反馈";
            var palette = Ui.P;
            _titleField = C.TextField("标题", "简要描述（选填）", "");
            _contactField = C.TextField("联系方式", "邮箱 / Telegram（选填）", "");
            _contentBox = new TextBox
            {
                AcceptsReturn = true,
                TextWrapping = TextWrapping.Wrap,
                Height = 110,
                FontSize = DS.FontSize.Body,
                Padding = new Thickness(8),
                Background = Ui.B(palette.Background),
                Foreground = Ui.B(palette.Foreground),
                BorderThickness = new Thickness(0),
                VerticalContentAlignment = VerticalAlignment.Top,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            };
            _contentBox.TextChanged += (s, e) => { _content = _contentBox.Text ?? ""; };

            _host.Margin = new Thickness(0, DS.Size.Gap, 0, 24);
            Content = Ui.ScrollPage(_host);
            Rebuild();
        }

        public override void OnAppear()
        {
            if (_loaded) return;
            _loaded = true;
            Ui.Fire(Load);
        }

        void Rebuild()
        {
            _host.Children.Clear();
            var palette = Ui.P;
            var stack = Ui.Stack(Orientation.Vertical, DS.Size.GapLarge);
            stack.AddRow(SubmitCard(), DS.Size.GapLarge);
            stack.AddRow(ListCard(), DS.Size.GapLarge);
            _host.Children.Add(stack);
        }

        UIElement SubmitCard()
        {
            var palette = Ui.P;
            var form = Ui.Stack(Orientation.Vertical, 12);
            form.Children.Add(Ui.Stack(Orientation.Horizontal, 10,
                Ui.IconTile("message", DS.IconColor.Cyan),
                C.SectionHeader("提交反馈", "线路问题、建议都可以告诉我们")));
            form.Children.Add(_titleField);

            var contentBlock = Ui.Stack(Orientation.Vertical, 6);
            contentBlock.Children.Add(Ui.Text("内容", DS.FontSize.BodySmall, FontWeights.Normal, palette.MutedForeground));
            var wrapper = new Border
            {
                Height = 110,
                CornerRadius = new CornerRadius(DS.Radius.Lg),
                Background = Ui.B(palette.Background),
                BorderBrush = Ui.B(palette.Border),
                BorderThickness = new Thickness(1),
                ClipToBounds = true,
                Child = _contentBox,
            };
            contentBlock.Children.Add(wrapper);
            form.Children.Add(contentBlock);

            form.Children.Add(_contactField);
            form.Children.Add(C.Button("提交反馈", () => Ui.Fire(Submit), BtnStyle.Primary, "message",
                DS.Size.ButtonHeight, _submitting, _submitting));
            return C.Card(form);
        }

        UIElement ListCard()
        {
            var palette = Ui.P;
            var inner = Ui.Stack(Orientation.Vertical, 10);
            inner.Children.Add(Ui.Stack(Orientation.Horizontal, 10,
                Ui.IconTile("message", DS.IconColor.Teal),
                C.SectionHeader("我的反馈")));

            if (_items.Count == 0)
            {
                inner.AddRow(Ui.Text("暂无反馈记录", DS.FontSize.BodySmall, FontWeights.Normal, palette.MutedForeground), 10);
            }
            else
            {
                for (int i = 0; i < _items.Count; i++)
                    inner.AddRow(FeedbackRow(_items[i]), 10);
            }
            return C.Card(inner);
        }

        UIElement FeedbackRow(FeedbackItem item)
        {
            var palette = Ui.P;
            var row = Ui.Stack(Orientation.Vertical, 6);
            row.Margin = new Thickness(0, 6, 0, 6);

            var title = Ui.Text(string.IsNullOrEmpty(item.Title) ? "反馈 #" + item.Id : item.Title,
                DS.FontSize.BodySmall, FontWeights.Normal, palette.Foreground, TextWrapping.Wrap);
            title.Margin = new Thickness(0, 0, 8, 0);
            var badge = C.StatusBadge(item.StatusText,
                item.Status == "handled" ? palette.OnlineBg : palette.Muted,
                item.Status == "handled" ? palette.OnlineText : palette.MutedForeground);
            row.Children.Add(Ui.Split(title, badge));

            var content = Ui.Text(item.Content, DS.FontSize.Caption, FontWeights.Normal,
                palette.MutedForeground, TextWrapping.Wrap);
            content.LineHeight = 17;
            content.MaxHeight = 51;
            row.AddRow(content, 6);

            if (!string.IsNullOrEmpty(item.Reply))
                row.AddRow(Ui.Text("回复：" + item.Reply, DS.FontSize.Caption, FontWeights.Normal,
                    palette.Foreground, TextWrapping.Wrap), 6);

            row.AddRow(Ui.Caption(Format.DateTimeText(item.CreatedAt)), 6);
            return row;
        }

        async Task Load()
        {
            try { _items.Clear(); _items.AddRange(await ApiClient.Shared.FetchFeedback()); }
            catch { }
            Rebuild();
        }

        async Task Submit()
        {
            var content = (_content ?? "").Trim();
            if (content.Length < 5)
            {
                App.ShowToast("请填写反馈内容（至少 5 个字）", BannerKind.Warning);
                return;
            }
            _submitting = true;
            Rebuild();
            try
            {
                await ApiClient.Shared.SubmitFeedback(null, _titleField.Value ?? "", _content, _contactField.Value ?? "");
                App.ShowToast("提交成功，管理员会尽快处理", BannerKind.Success);
                _titleField.Value = "";
                _contentBox.Text = "";
                _content = "";
                _contactField.Value = "";
                await Load();
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _submitting = false;
                Rebuild();
            }
        }
    }

    // MARK: - 邀请（独立 Tab）

    /// <summary>邀请好友：邀请码 / 邀请链接 / 奖励规则 / 我的金币（对应 iOS InviteView）</summary>
    public class InviteView : Screen
    {
        readonly Grid _host = new Grid();
        CoinsPayload _payload;
        bool _copiedCode;
        bool _copiedLink;

        public InviteView()
        {
            HidesHeader = true;
            Title = "邀请好友";
            _host.Margin = new Thickness(0, 8, 0, 28);
            Content = Ui.ScrollPage(_host);
            Rebuild();
        }

        public override void OnAppear()
        {
            Ui.Fire(Load);
        }

        void Rebuild()
        {
            _host.Children.Clear();
            var stack = Ui.Stack(Orientation.Vertical, DS.Size.GapLarge);
            stack.AddRow(LargeTitle("邀请好友"), DS.Size.GapLarge);
            stack.AddRow(Hero(), DS.Size.GapLarge);

            if (_payload != null && !_payload.InviteEnabled)
            {
                stack.AddRow(C.BannerBar("站点当前已关闭邀请奖励", BannerKind.Warning), DS.Size.GapLarge);
            }
            else
            {
                stack.AddRow(CodeCard(), DS.Size.GapLarge);
                stack.AddRow(RewardCard(), DS.Size.GapLarge);
                stack.AddRow(C.BannerBar("好友注册成功后，奖励金币会自动到账，可在「套餐」页使用金币兑换套餐。", BannerKind.Info), DS.Size.GapLarge);
            }

            _host.Children.Add(stack);
        }

        static TextBlock LargeTitle(string text)
        {
            return Ui.Text(text, 24, FontWeights.Bold, Ui.P.Foreground);
        }

        UIElement Hero()
        {
            var inner = Ui.Stack(Orientation.Vertical, 10);
            inner.Children.Add(Ui.Icon("person", 26, Colors.White, 2));
            inner.Children.Add(Ui.Text("邀请好友得金币", 20, FontWeights.Bold, Colors.White));
            inner.Children.Add(Ui.Text("好友通过你的邀请码注册，双方均可获得金币奖励，金币可用于兑换套餐。",
                DS.FontSize.Caption, FontWeights.Normal, Ui.Alpha(Colors.White, 0.9), TextWrapping.Wrap));

            var capsuleRow = Ui.Stack(Orientation.Horizontal, 6);
            capsuleRow.Children.Add(Ui.Icon("coin", 13, Colors.White, 2));
            capsuleRow.Children.Add(Ui.Text("我的金币 " + (_payload != null ? _payload.Coins : 0),
                13, FontWeights.SemiBold, Colors.White));
            var capsule = new Border
            {
                CornerRadius = new CornerRadius(99),
                Background = Ui.B(Ui.Alpha(Colors.White, 0.18)),
                Padding = new Thickness(10, 5, 10, 5),
                Child = capsuleRow,
                HorizontalAlignment = HorizontalAlignment.Left,
            };
            inner.Children.Add(capsule);
            inner.Margin = new Thickness(18);

            return new Border
            {
                CornerRadius = new CornerRadius(DS.Radius.Xxl),
                Background = new LinearGradientBrush(DS.Brand.Green, DS.Brand.TealDeep,
                    new Point(0, 0), new Point(1, 1)),
                Child = inner,
            };
        }

        UIElement CodeCard()
        {
            var palette = Ui.P;
            string code = _payload != null ? _payload.InviteCode : "";
            string url = _payload != null ? _payload.InviteUrl : "";
            bool codeEmpty = string.IsNullOrEmpty(code);
            bool urlEmpty = string.IsNullOrEmpty(url);

            var inner = Ui.Stack(Orientation.Vertical, 12);
            inner.Children.Add(Ui.Stack(Orientation.Horizontal, 10,
                Ui.IconTile("ticket", DS.IconColor.Teal),
                C.SectionHeader("我的邀请码", "分享给好友即可参与")));

            // 邀请码 + 复制
            var codeText = Ui.Text(codeEmpty ? "------" : code, 20, FontWeights.Bold, palette.Foreground);
            codeText.FontFamily = new FontFamily("Consolas, Cascadia Mono, Courier New");
            codeText.VerticalAlignment = VerticalAlignment.Center;
            var copyCode = C.Button(_copiedCode ? "已复制" : "复制", () =>
            {
                Copy(code);
                _copiedCode = true;
                App.ShowToast("邀请码已复制", BannerKind.Success);
                Rebuild();
            }, BtnStyle.Secondary, _copiedCode ? "check" : "copy", DS.Size.ButtonHeightSmall, false, codeEmpty);
            copyCode.Width = 104;
            copyCode.VerticalAlignment = VerticalAlignment.Center;

            var codeRow = new Grid();
            codeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            codeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(codeText, 0);
            codeRow.Children.Add(codeText);
            Grid.SetColumn(copyCode, 1);
            copyCode.Margin = new Thickness(10, 0, 0, 0);
            codeRow.Children.Add(copyCode);
            inner.Children.Add(codeRow);

            inner.Children.Add(new Rectangle { Height = 1, Fill = Ui.B(palette.Border) });
            inner.Children.Add(Ui.Text("邀请链接", DS.FontSize.Caption, FontWeights.Normal, palette.MutedForeground));
            var urlText = Ui.Text(urlEmpty ? "正在获取邀请链接…" : url, DS.FontSize.Caption, FontWeights.Normal,
                palette.SecondaryText);
            urlText.TextWrapping = TextWrapping.NoWrap;
            urlText.TextTrimming = TextTrimming.CharacterEllipsis;
            urlText.MaxHeight = 34;
            inner.Children.Add(urlText);

            // 复制链接 + 分享
            var copyLink = C.Button(_copiedLink ? "已复制" : "复制链接", () =>
            {
                Copy(url);
                _copiedLink = true;
                App.ShowToast("邀请链接已复制", BannerKind.Success);
                Rebuild();
            }, BtnStyle.Secondary, "link", DS.Size.ButtonHeightSmall, false, urlEmpty);

            Border share;
            if (urlEmpty)
            {
                share = C.Button("分享", null, BtnStyle.Primary, "upload", DS.Size.ButtonHeightSmall, false, true);
            }
            else
            {
                share = C.Button("分享", () =>
                {
                    Copy(url);
                    App.ShowToast("邀请链接已复制，可粘贴分享给好友", BannerKind.Success);
                }, BtnStyle.Primary, "upload", DS.Size.ButtonHeightSmall);
            }

            var actions = new Grid();
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetColumn(copyLink, 0);
            actions.Children.Add(copyLink);
            Grid.SetColumn(share, 1);
            share.Margin = new Thickness(10, 0, 0, 0);
            actions.Children.Add(share);
            inner.Children.Add(actions);

            return C.Card(inner);
        }

        UIElement RewardCard()
        {
            var inner = Ui.Stack(Orientation.Vertical, 10);
            inner.Children.Add(Ui.Stack(Orientation.Horizontal, 10,
                Ui.IconTile("gift", DS.IconColor.Orange),
                C.SectionHeader("奖励规则")));
            inner.AddRow(RewardRow("person", "邀请人奖励",
                (_payload != null ? _payload.InviteRewardCoins : 0) + " 金币", DS.IconColor.Green), 10);
            inner.AddRow(RewardRow("gift", "被邀请人奖励",
                (_payload != null ? _payload.InviteeRewardCoins : 0) + " 金币", DS.IconColor.Cyan), 10);
            inner.AddRow(RewardRow("coin", "新用户注册赠送",
                (_payload != null ? _payload.RegisterCoins : 0) + " 金币", DS.IconColor.Teal), 10);
            return C.Card(inner);
        }

        static UIElement RewardRow(string icon, string title, string value, Color color)
        {
            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var badge = new Border
            {
                Width = 26,
                Height = 26,
                CornerRadius = new CornerRadius(DS.Radius.Sm),
                Background = Ui.B(Ui.Alpha(color, 0.14)),
                Child = new Grid { Children = { Ui.Icon(icon, 13, color, 2) } },
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(badge, 0);
            row.Children.Add(badge);

            var label = Ui.Text(title, DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.SecondaryText);
            label.Margin = new Thickness(10, 0, 8, 0);
            Grid.SetColumn(label, 1);
            row.Children.Add(label);

            var amount = Ui.Text(value, DS.FontSize.Body, FontWeights.SemiBold, DS.IconColor.Orange);
            amount.HorizontalAlignment = HorizontalAlignment.Right;
            Grid.SetColumn(amount, 2);
            row.Children.Add(amount);
            return row;
        }

        static void Copy(string text)
        {
            try { System.Windows.Clipboard.SetText(text ?? ""); }
            catch { }
        }

        async Task Load()
        {
            try
            {
                _payload = await ApiClient.Shared.FetchCoins();
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            Rebuild();
        }
    }

    // MARK: - 账号设置（改密 / 密保 / 更换主控 / 退出登录）

    /// <summary>账号设置：修改密码、密保问题、更换主控与退出登录（对应 iOS AccountSettingsView）</summary>
    public class AccountSettingsView : Screen
    {
        readonly Grid _host = new Grid();
        readonly TextFieldControl _oldPassword;
        readonly TextFieldControl _newPassword;
        readonly TextFieldControl _confirmPassword;
        readonly TextFieldControl _questionField;
        readonly TextFieldControl _answerField;

        string _currentQuestion;
        bool _securityLoaded;
        bool _loaded;
        bool _savingPassword;
        bool _savingSecurity;

        public AccountSettingsView()
        {
            HidesHeader = false;
            Title = "账号设置";
            _oldPassword = C.TextField("原密码", "当前登录密码", "", true);
            _newPassword = C.TextField("新密码", "至少 6 位", "", true);
            _confirmPassword = C.TextField("确认新密码", "再次输入新密码", "", true);
            _questionField = C.TextField("密保问题", "例如：我的第一台服务器名字", "");
            _answerField = C.TextField("密保答案", "找回密码时使用（不区分大小写）", "");
            _host.Margin = new Thickness(0, DS.Size.Gap, 0, 24);
            Content = Ui.ScrollPage(_host);
            Rebuild();
        }

        public override void OnAppear()
        {
            if (_loaded) return;
            _loaded = true;
            Ui.Fire(LoadSecurity);
        }

        bool HasSecurityQuestion { get { return !string.IsNullOrEmpty(_currentQuestion); } }

        void Rebuild()
        {
            _host.Children.Clear();
            var palette = Ui.P;
            var stack = Ui.Stack(Orientation.Vertical, DS.Size.GapLarge);

            // 修改密码
            var password = Ui.Stack(Orientation.Vertical, 12);
            password.Children.Add(Ui.Stack(Orientation.Horizontal, 10,
                Ui.IconTile("lock", DS.IconColor.Amber),
                C.SectionHeader("修改密码")));
            password.Children.Add(_oldPassword);
            password.Children.Add(_newPassword);
            password.Children.Add(_confirmPassword);
            password.Children.Add(C.Button("保存新密码", () => Ui.Fire(ChangePassword), BtnStyle.Primary, "shield",
                DS.Size.ButtonHeight, _savingPassword, _savingPassword));
            stack.AddRow(C.Card(password), DS.Size.GapLarge);

            // 密保问题
            var security = Ui.Stack(Orientation.Vertical, 12);
            security.Children.Add(Ui.Stack(Orientation.Horizontal, 10,
                Ui.IconTile("key", DS.IconColor.TealDeep),
                C.SectionHeader("密保问题", "用于找回密码")));
            if (HasSecurityQuestion)
            {
                security.AddRow(C.ReadOnlyField("密保问题", _currentQuestion), 12);
                security.AddRow(C.ReadOnlyField("密保答案", "", true), 12);
                security.AddRow(Ui.Text("密保答案已加密保存，不会明文展示；如需修改，请联系管理员在「用户管理」中重置密保后重新设置。",
                    DS.FontSize.Caption, FontWeights.Normal, palette.MutedForeground, TextWrapping.Wrap), 12);
            }
            else if (_securityLoaded)
            {
                security.AddRow(_questionField, 12);
                security.AddRow(_answerField, 12);
                security.AddRow(C.Button("保存密保", () => Ui.Fire(SaveSecurity), BtnStyle.Primary, "shield",
                    DS.Size.ButtonHeight, _savingSecurity, _savingSecurity), 12);
            }
            else
            {
                security.AddRow(C.LoadingBlock("正在获取密保信息…"), 12);
            }
            stack.AddRow(C.Card(security), DS.Size.GapLarge);

            // 其他：更换主控 / 退出登录
            var other = Ui.Stack(Orientation.Vertical, 10);
            other.Children.Add(Ui.Stack(Orientation.Horizontal, 10,
                Ui.IconTile("gear", DS.IconColor.Slate),
                C.SectionHeader("其他")));
            other.AddRow(C.MenuList(
                C.MenuRow("server", DS.IconColor.Slate, "更换主控", "退出登录并返回主控地址配置页", null, ConfirmResetMaster),
                C.MenuRow("logout", DS.IconColor.Rose, "退出登录", "退出后需要重新输入账号密码", null, ConfirmLogout)), 10);
            stack.AddRow(C.Card(other), DS.Size.GapLarge);

            _host.Children.Add(stack);
        }

        void ConfirmResetMaster()
        {
            MainShell.PresentAlert("更换主控地址？", "将退出登录并返回主控地址配置页", "确定",
                () => App.ResetMaster(), true);
        }

        void ConfirmLogout()
        {
            MainShell.PresentAlert("退出登录？", "退出后需要重新输入账号密码", "退出",
                () => App.Logout(), true);
        }

        async Task LoadSecurity()
        {
            try { _currentQuestion = await ApiClient.Shared.FetchSecurityQuestion(); }
            catch { }
            _securityLoaded = true;
            Rebuild();
        }

        async Task ChangePassword()
        {
            var oldValue = _oldPassword.Value ?? "";
            var newValue = _newPassword.Value ?? "";
            var confirmValue = _confirmPassword.Value ?? "";
            if (newValue.Length < 6)
            {
                App.ShowToast("新密码至少 6 位", BannerKind.Warning);
                return;
            }
            if (newValue != confirmValue)
            {
                App.ShowToast("两次输入的新密码不一致", BannerKind.Warning);
                return;
            }
            _savingPassword = true;
            Rebuild();
            try
            {
                await ApiClient.Shared.ChangePassword(oldValue, newValue);
                App.ShowToast("密码已更新", BannerKind.Success);
                _oldPassword.Value = "";
                _newPassword.Value = "";
                _confirmPassword.Value = "";
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _savingPassword = false;
                Rebuild();
            }
        }

        async Task SaveSecurity()
        {
            var question = (_questionField.Value ?? "").Trim();
            var answer = (_answerField.Value ?? "").Trim();
            if (question.Length == 0 || answer.Length < 2)
            {
                App.ShowToast("请填写密保问题与答案（答案至少 2 个字符）", BannerKind.Warning);
                return;
            }
            _savingSecurity = true;
            Rebuild();
            try
            {
                await ApiClient.Shared.UpdateSecurity(question, answer);
                _currentQuestion = question;
                App.ShowToast("密保已保存", BannerKind.Success);
                _answerField.Value = "";
            }
            catch (Exception error)
            {
                App.Report(error);
            }
            finally
            {
                _savingSecurity = false;
                Rebuild();
            }
        }
    }
}
