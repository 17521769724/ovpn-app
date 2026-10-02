using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using OVPNPanel.Theme;

namespace OVPNPanel.Core
{
    /// <summary>
    /// WPF 界面基础设施：线程调度、基础控件构造、按压反馈、底部浮层与全局横幅。
    /// 所有视图都以命令式方式构建，风格与配色严格复用 Theme/DS 中的三端统一令牌。
    /// </summary>
    public static class Ui
    {
        public static Palette P { get { return AppTheme.Palette; } }

        // MARK: - 线程调度

        public static void Post(Action action)
        {
            var app = Application.Current;
            if (app == null) { action(); return; }
            if (app.Dispatcher.CheckAccess()) action();
            else app.Dispatcher.BeginInvoke(DispatcherPriority.Normal, action);
        }

        public static void Run(Action action)
        {
            var app = Application.Current;
            if (app == null) { action(); return; }
            if (app.Dispatcher.CheckAccess()) action();
            else app.Dispatcher.Invoke(action);
        }

        /// <summary>触发一个异步动作：未捕获的异常统一走全局红色横幅提示</summary>
        public static async void Fire(Func<System.Threading.Tasks.Task> action, Action<Exception> onError = null)
        {
            try
            {
                await action();
            }
            catch (Exception error)
            {
                if (onError != null) onError(error);
                else AppState.Shared.Report(error);
            }
        }

        // MARK: - 基础构造

        public static SolidColorBrush B(Color color) { return AppTheme.Palette.B(color); }

        public const string Family = "Segoe UI, Microsoft YaHei UI, Microsoft YaHei, SimSun";

        public static TextBlock Text(string text, double size = DS.FontSize.Body,
            FontWeight? weight = null, Color? color = null, TextWrapping wrap = TextWrapping.NoWrap)
        {
            return new TextBlock
            {
                Text = text ?? "",
                FontSize = size,
                FontWeight = weight ?? FontWeights.Normal,
                Foreground = B(color ?? P.Foreground),
                TextWrapping = wrap,
                VerticalAlignment = VerticalAlignment.Center,
                TextTrimming = wrap == TextWrapping.NoWrap ? TextTrimming.CharacterEllipsis : TextTrimming.None,
            };
        }

        public static TextBlock Body(string text, Color? color = null, double size = DS.FontSize.Body)
        {
            return Text(text, size, FontWeights.Normal, color ?? P.Foreground);
        }

        public static TextBlock Caption(string text, Color? color = null)
        {
            return Text(text, DS.FontSize.Caption, FontWeights.Normal, color ?? P.MutedForeground);
        }

        public static TextBlock SectionTitle(string text)
        {
            return Text(text, DS.FontSize.Section, FontWeights.SemiBold, P.Foreground);
        }

        public static StackPanel VStack(params UIElement[] children)
        {
            return Stack(Orientation.Vertical, 0, children);
        }

        public static StackPanel HStack(params UIElement[] children)
        {
            return Stack(Orientation.Horizontal, 0, children);
        }

        /// <summary>在 StackPanel 中按固定间距排列子元素</summary>
        public static StackPanel Stack(Orientation orientation, double spacing, params UIElement[] children)
        {
            var panel = new StackPanel { Orientation = orientation };
            for (int i = 0; i < children.Length; i++)
            {
                if (children[i] == null) continue;
                if (i > 0 && spacing > 0)
                {
                    if (orientation == Orientation.Vertical)
                        ((FrameworkElement)children[i]).Margin = AddTop(((FrameworkElement)children[i]).Margin, spacing);
                    else
                        ((FrameworkElement)children[i]).Margin = AddLeft(((FrameworkElement)children[i]).Margin, spacing);
                }
                panel.Children.Add(children[i]);
            }
            return panel;
        }

        public static void AddRow(this StackPanel panel, UIElement child, double spacing)
        {
            if (panel.Children.Count > 0 && spacing > 0)
                ((FrameworkElement)child).Margin = AddTop(((FrameworkElement)child).Margin, spacing);
            panel.Children.Add(child);
        }

        public static Thickness AddTop(Thickness t, double value) { return new Thickness(t.Left, t.Top + value, t.Right, t.Bottom); }
        public static Thickness AddLeft(Thickness t, double value) { return new Thickness(t.Left + value, t.Top, t.Right, t.Bottom); }

        public static Grid Row(params UIElement[] children)
        {
            var grid = new Grid();
            foreach (var child in children) grid.Children.Add(child);
            return grid;
        }

        /// <summary>左右两端对齐的一行（左内容 + 右侧内容）</summary>
        public static Grid Split(FrameworkElement left, FrameworkElement right)
        {
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            if (left != null) { Grid.SetColumn(left, 0); grid.Children.Add(left); }
            if (right != null)
            {
                Grid.SetColumn(right, 2);
                right.HorizontalAlignment = HorizontalAlignment.Right;
                grid.Children.Add(right);
            }
            return grid;
        }

        public static Border Box(UIElement child, Color? background = null, double radius = DS.Radius.Xl,
            Color? border = null, double borderThickness = 1, Thickness? padding = null)
        {
            var box = new Border
            {
                CornerRadius = new CornerRadius(radius),
                Background = background.HasValue ? B(background.Value) : null,
                BorderBrush = border.HasValue ? B(border.Value) : null,
                BorderThickness = border.HasValue ? new Thickness(borderThickness) : new Thickness(0),
                Padding = padding ?? new Thickness(0),
                SnapsToDevicePixels = true,
            };
            if (child != null) box.Child = child;
            return box;
        }

        /// <summary>把任意元素裁剪为圆角矩形（用于渐变背景）</summary>
        public static Border Clip(UIElement child, double radius)
        {
            return new Border
            {
                CornerRadius = new CornerRadius(radius),
                ClipToBounds = true,
                Background = Brushes.Transparent,
                Child = child,
            };
        }

        public static Rectangle VLine(double height = 10, Color? color = null)
        {
            return new Rectangle
            {
                Width = 1,
                Height = height,
                Fill = B(color ?? Color.FromArgb(97, P.MutedForeground.R, P.MutedForeground.G, P.MutedForeground.B)),
                VerticalAlignment = VerticalAlignment.Center,
            };
        }

        public static UIElement Spacer()
        {
            return new Grid { Width = 1, Height = 1 };
        }

        public static void SetTooltip(FrameworkElement element, string tip)
        {
            if (!string.IsNullOrEmpty(tip)) element.ToolTip = tip;
        }

        // MARK: - 图标

        public static Path Icon(string name, double size, Color color, double thickness = 2)
        {
            return Icons.Create(name, size, color, thickness);
        }

        /// <summary>彩色图标块（对应 iOS IconTile）</summary>
        public static Border IconTile(string iconName, Color color, double size = 30)
        {
            var gradient = new LinearGradientBrush(
                Color.FromArgb((byte)(0.22 * 255), color.R, color.G, color.B),
                Color.FromArgb((byte)(0.12 * 255), color.R, color.G, color.B), 45);
            var path = Icons.Create(iconName, size * 0.46, color, 1.9);
            return new Border
            {
                Width = size,
                Height = size,
                CornerRadius = new CornerRadius(size * 0.3),
                Background = gradient,
                Child = new Grid { Children = { path } },
                VerticalAlignment = VerticalAlignment.Center,
            };
        }

        // MARK: - 按压反馈

        public static readonly TimeSpan PressDuration = TimeSpan.FromMilliseconds(110);

        /// <summary>给任意元素附加「按下缩放」反馈与点击回调</summary>
        public static T Clickable<T>(this T element, Action onClick, double scale = 0.97) where T : FrameworkElement
        {
            var transform = new ScaleTransform(1, 1);
            element.RenderTransformOrigin = new Point(0.5, 0.5);

            TransformGroup group;
            if (element.RenderTransform is TransformGroup)
            {
                group = (TransformGroup)element.RenderTransform;
                group.Children.Add(transform);
            }
            else
            {
                group = new TransformGroup();
                group.Children.Add(transform);
                element.RenderTransform = group;
            }

            element.Cursor = Cursors.Hand;
            element.MouseLeftButtonDown += (s, e) =>
            {
                Animate(transform, ScaleTransform.ScaleXProperty, scale, PressDuration);
                Animate(transform, ScaleTransform.ScaleYProperty, scale, PressDuration);
                element.CaptureMouse();
                e.Handled = true;
            };
            element.MouseLeftButtonUp += (s, e) =>
            {
                Animate(transform, ScaleTransform.ScaleXProperty, 1, PressDuration);
                Animate(transform, ScaleTransform.ScaleYProperty, 1, PressDuration);
                element.ReleaseMouseCapture();
                if (onClick != null) onClick();
                e.Handled = true;
            };
            element.MouseLeave += (s, e) =>
            {
                if (Mouse.Captured == element) element.ReleaseMouseCapture();
                Animate(transform, ScaleTransform.ScaleXProperty, 1, PressDuration);
                Animate(transform, ScaleTransform.ScaleYProperty, 1, PressDuration);
            };
            return element;
        }

        public static void Animate(Animatable target, DependencyProperty property, double to, TimeSpan duration,
            IEasingFunction easing = null)
        {
            var animation = new DoubleAnimation(to, duration)
            {
                EasingFunction = easing ?? new QuadraticEase { EasingMode = EasingMode.EaseOut },
            };
            target.BeginAnimation(property, animation);
        }

        public static void AnimateOpacity(UIElement element, double to, int milliseconds)
        {
            element.BeginAnimation(UIElement.OpacityProperty,
                new DoubleAnimation(to, TimeSpan.FromMilliseconds(milliseconds)));
        }

        // MARK: - 滚动容器

        public static ScrollViewer Scroll(UIElement content, Thickness? padding = null)
        {
            return new ScrollViewer
            {
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                Content = padding.HasValue ? Pad(content, padding.Value) : content,
                Focusable = false,
                PanningMode = PanningMode.VerticalOnly,
            };
        }

        public static Border Pad(UIElement child, Thickness padding)
        {
            return new Border { Padding = padding, Child = child };
        }

        /// <summary>页面统一内边距（左右 16）</summary>
        public static Border Page(UIElement child)
        {
            return new Border { Padding = new Thickness(DS.Size.PagePadding, 0, DS.Size.PagePadding, 0), Child = child };
        }

        /// <summary>桌面端内容列：固定最大宽度并居中，保持与手机端一致的纵向版式</summary>
        public static Grid Centered(UIElement content, double maxWidth = DS.Size.ContentMaxWidth)
        {
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(maxWidth) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            content.SetValue(Grid.ColumnProperty, 1);
            grid.Children.Add(content);
            return grid;
        }

        public static Grid ScrollPage(UIElement content, double maxWidth = DS.Size.ContentMaxWidth)
        {
            var inner = Centered(Page(content), maxWidth);
            return new Grid { Children = { Scroll(inner) } };
        }

        // MARK: - 颜色工具

        public static Color Alpha(Color color, double alpha)
        {
            return Color.FromArgb((byte)Math.Round(Math.Max(0, Math.Min(1, alpha)) * 255), color.R, color.G, color.B);
        }

        public static Color Mix(Color a, Color b, double t)
        {
            return Color.FromRgb(
                (byte)Math.Round(a.R + (b.R - a.R) * t),
                (byte)Math.Round(a.G + (b.G - a.G) * t),
                (byte)Math.Round(a.B + (b.B - a.B) * t));
        }
    }

    /// <summary>带按下 / 悬停反馈的通用可点容器（卡片、列表行、自定义按钮的底座）</summary>
    public class PressSurface : Border
    {
        public event Action Clicked;

        public PressSurface()
        {
            Background = Brushes.Transparent;
            Cursor = Cursors.Hand;
            SnapsToDevicePixels = true;
        }

        public Action HoverChanged;

        protected override void OnMouseEnter(MouseEventArgs e)
        {
            base.OnMouseEnter(e);
            if (HoverChanged != null) HoverChanged();
        }

        protected override void OnMouseLeave(MouseEventArgs e)
        {
            base.OnMouseLeave(e);
            if (HoverChanged != null) HoverChanged();
        }

        protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
        {
            base.OnMouseLeftButtonUp(e);
            var handler = Clicked;
            if (handler != null) handler();
            e.Handled = true;
        }

        /// <summary>直接触发一次点击（供键盘 / 程序化触发复用同一逻辑）</summary>
        public void PerformClick()
        {
            var handler = Clicked;
            if (handler != null) handler();
        }
    }

    /// <summary>iOS 风格下拉刷新（滚动到顶部继续下拉触发）</summary>
    public class RefreshableScrollViewer : ScrollViewer
    {
        DateTime _pullStart = DateTime.MinValue;
        bool _armed;

        public Action OnRefresh;

        public RefreshableScrollViewer()
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
            PanningMode = PanningMode.VerticalOnly;
            PreviewMouseWheel += (s, e) => { if (VerticalOffset <= 0 && e.Delta > 0) { } };
            PreviewMouseLeftButtonDown += (s, e) => { if (VerticalOffset <= 0) { _pullStart = DateTime.Now; _armed = true; } };
            PreviewMouseLeftButtonUp += (s, e) =>
            {
                if (_armed && VerticalOffset <= 0 && (DateTime.Now - _pullStart).TotalMilliseconds > 60 && OnRefresh != null)
                {
                    OnRefresh();
                }
                _armed = false;
            };
        }
    }

    /// <summary>居中确认框（对应 iOS 的 .alert）</summary>
    public class AlertHost : Grid
    {
        readonly SolidColorBrush _dimmer = new SolidColorBrush(Color.FromArgb(0, 0, 0, 0));

        public AlertHost()
        {
            Visibility = Visibility.Collapsed;
            VerticalAlignment = VerticalAlignment.Stretch;
            Background = _dimmer;
        }

        public bool IsOpen { get { return Visibility == Visibility.Visible; } }

        public void Present(string title, string message, string confirmText, Action onConfirm,
            bool destructive = false, string cancelText = "取消")
        {
            Children.Clear();

            var stack = Ui.Stack(Orientation.Vertical, 0);
            var titleBlock = Ui.Text(title, 16, FontWeights.SemiBold, Ui.P.Foreground, TextWrapping.Wrap);
            titleBlock.HorizontalAlignment = HorizontalAlignment.Center;
            titleBlock.TextAlignment = TextAlignment.Center;
            stack.Children.Add(titleBlock);

            if (!string.IsNullOrEmpty(message))
            {
                var messageBlock = Ui.Text(message, DS.FontSize.BodySmall, FontWeights.Normal,
                    Ui.P.MutedForeground, TextWrapping.Wrap);
                messageBlock.HorizontalAlignment = HorizontalAlignment.Center;
                messageBlock.TextAlignment = TextAlignment.Center;
                messageBlock.Margin = new Thickness(0, 8, 0, 0);
                stack.Children.Add(messageBlock);
            }

            var buttons = Ui.Stack(Orientation.Horizontal, 10);
            buttons.Margin = new Thickness(0, 18, 0, 0);
            var cancel = C.Button(cancelText, Dismiss, BtnStyle.Secondary, null, DS.Size.ButtonHeight);
            var confirm = C.Button(confirmText, () =>
            {
                Dismiss();
                if (onConfirm != null) onConfirm();
            }, destructive ? BtnStyle.Destructive : BtnStyle.Primary, null, DS.Size.ButtonHeight);
            cancel.Width = 110;
            confirm.Width = 110;
            buttons.Children.Add(cancel);
            buttons.Children.Add(confirm);
            buttons.HorizontalAlignment = HorizontalAlignment.Right;
            stack.Children.Add(buttons);

            var card = Ui.Box(stack, Ui.P.Card, DS.Radius.Xl, Ui.P.Border, 1, new Thickness(20));
            card.MaxWidth = 340;
            card.HorizontalAlignment = HorizontalAlignment.Center;
            card.VerticalAlignment = VerticalAlignment.Center;
            card.Effect = new System.Windows.Media.Effects.DropShadowEffect
            {
                BlurRadius = 22,
                ShadowDepth = 6,
                Opacity = 0.22,
                Color = Colors.Black,
            };
            var scale = new ScaleTransform(0.94, 0.94);
            card.RenderTransformOrigin = new Point(0.5, 0.5);
            card.RenderTransform = scale;

            MouseLeftButtonUp += (s, e) => { if (e.OriginalSource == this) Dismiss(); };
            Children.Add(card);
            Visibility = Visibility.Visible;

            Ui.Post(() =>
            {
                Ui.Animate(scale, ScaleTransform.ScaleXProperty, 1, TimeSpan.FromMilliseconds(180));
                Ui.Animate(scale, ScaleTransform.ScaleYProperty, 1, TimeSpan.FromMilliseconds(180));
                _dimmer.BeginAnimation(SolidColorBrush.ColorProperty,
                    new ColorAnimation(Color.FromArgb(120, 0, 0, 0), TimeSpan.FromMilliseconds(180)));
            });
        }

        public void Dismiss()
        {
            Visibility = Visibility.Collapsed;
            Children.Clear();
            _dimmer.BeginAnimation(SolidColorBrush.ColorProperty, null);
            _dimmer.Color = Color.FromArgb(0, 0, 0, 0);
        }
    }

    /// <summary>全局横幅提示宿主（顶部浮层，自动收起）</summary>
    public class ToastHost : Grid
    {
        readonly AppState _state;
        readonly Border _card;
        readonly TextBlock _label;
        readonly Path _glyph;
        readonly StackPanel _row;

        public ToastHost(AppState state)
        {
            _state = state;
            VerticalAlignment = VerticalAlignment.Top;
            IsHitTestVisible = true;
            Margin = new Thickness(0, 6, 0, 0);
            Visibility = Visibility.Collapsed;

            _glyph = new Path { Width = 16, Height = 16, Stretch = Stretch.Uniform, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 1, 0, 0) };
            _label = Ui.Text("", 13, FontWeights.Medium, Colors.White, TextWrapping.Wrap);
            _row = Ui.Stack(Orientation.Horizontal, 8, _glyph, _label);
            _row.HorizontalAlignment = HorizontalAlignment.Left;

            _card = Ui.Box(_row, Colors.White, DS.Radius.Lg, null, 0, new Thickness(14, 12, 14, 12));
            _card.HorizontalAlignment = HorizontalAlignment.Stretch;
            _card.Effect = new System.Windows.Media.Effects.DropShadowEffect
            {
                BlurRadius = 14,
                ShadowDepth = 4,
                Opacity = 0.16,
                Color = Colors.Black,
            };
            _card.Cursor = Cursors.Hand;
            _card.MouseLeftButtonUp += (s, e) => _state.DismissToast();
            _card.RenderTransformOrigin = new Point(0.5, 0);

            var scale = new ScaleTransform(1, 1);
            _card.RenderTransform = scale;

            var outer = new Border
            {
                Padding = new Thickness(DS.Size.PagePadding, 0, DS.Size.PagePadding, 0),
                Child = _card,
                HorizontalAlignment = HorizontalAlignment.Stretch,
            };
            Children.Add(outer);

            _state.StateChanged += Refresh;
            Refresh();
        }

        void Refresh()
        {
            var toast = _state.Toast;
            if (toast == null)
            {
                Visibility = Visibility.Collapsed;
                return;
            }
            var style = Ui.P.ToastStyle(toast.Kind);
            _card.Background = Ui.B(style.Background);
            _card.BorderBrush = Ui.B(style.Border);
            _card.BorderThickness = new Thickness(1);
            _glyph.Stroke = Ui.B(style.Foreground);
            _glyph.StrokeThickness = 1.8;
            _glyph.StrokeStartLineCap = PenLineCap.Round;
            _glyph.StrokeEndLineCap = PenLineCap.Round;
            _glyph.StrokeLineJoin = PenLineJoin.Round;
            _glyph.Data = Icons.ParseGeometry(Icons.Data(ToastIcon(toast.Kind)));
            _label.Foreground = Ui.B(style.Foreground);
            _label.Text = toast.Text;

            Visibility = Visibility.Visible;
            var scale = (ScaleTransform)_card.RenderTransform;
            var animation = new DoubleAnimation(0.97, 1, TimeSpan.FromMilliseconds(180))
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
            };
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, animation);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, animation);
            _card.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)));
        }

        static string ToastIcon(BannerKind kind)
        {
            switch (kind)
            {
                case BannerKind.Success: return "checkCircle";
                case BannerKind.Error: return "close";
                case BannerKind.Warning: return "warning";
                default: return "info";
            }
        }
    }

    /// <summary>底部弹出浮层（对应用户点击「找回密码」等从底部弹出的交互）</summary>
    public class SheetHost : Grid
    {
        readonly SolidColorBrush _dimmer = new SolidColorBrush(Color.FromArgb(0, 0, 0, 0));

        public SheetHost()
        {
            Visibility = Visibility.Collapsed;
            Background = _dimmer;
            VerticalAlignment = VerticalAlignment.Stretch;
        }

        public bool IsOpen { get { return Visibility == Visibility.Visible; } }

        /// <summary>从底部弹出内容</summary>
        public void Present(string title, UIElement content, Action onClose = null, double maxHeight = 620)
        {
            Children.Clear();

            var panel = Ui.VStack();
            panel.Background = Ui.B(Ui.P.Background);

            var header = Ui.Split(
                Ui.Text(title, 17, FontWeights.SemiBold, Ui.P.Foreground),
                Ui.Icon("close", 16, Ui.P.MutedForeground).Clickable(() => Dismiss(onClose)));
            header.Margin = new Thickness(DS.Size.CardPadding, 14, DS.Size.CardPadding, 10);
            panel.Children.Add(header);

            var body = Ui.Scroll(content, new Thickness(DS.Size.CardPadding, 0, DS.Size.CardPadding, 18));
            body.MaxHeight = maxHeight;
            panel.Children.Add(body);

            var card = new Border
            {
                Child = panel,
                CornerRadius = new CornerRadius(DS.Radius.Xxl, DS.Radius.Xxl, 0, 0),
                Background = Ui.B(Ui.P.Background),
                BorderBrush = Ui.B(Ui.P.Border),
                BorderThickness = new Thickness(0, 1, 0, 0),
                VerticalAlignment = VerticalAlignment.Bottom,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                MaxWidth = DS.Size.ContentMaxWidth,
                ClipToBounds = true,
            };

            var translate = new TranslateTransform(0, 600);
            card.RenderTransform = translate;
            card.SizeChanged += (s, e) =>
            {
                if (translate.Y > 500) translate.Y = card.ActualHeight + 40;
            };

            MouseLeftButtonUp += (s, e) =>
            {
                if (e.OriginalSource == this) Dismiss(onClose);
            };

            Children.Add(card);
            Visibility = Visibility.Visible;

            Ui.Post(() =>
            {
                translate.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(260))
                {
                    EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
                });
                _dimmer.BeginAnimation(SolidColorBrush.ColorProperty,
                    new ColorAnimation(Color.FromArgb(120, 0, 0, 0), TimeSpan.FromMilliseconds(200)));
            });
        }

        public void Dismiss(Action onClose = null)
        {
            if (Visibility != Visibility.Visible) { if (onClose != null) onClose(); return; }
            var card = Children.Count > 0 ? Children[0] as Border : null;
            if (card == null) { Visibility = Visibility.Collapsed; if (onClose != null) onClose(); return; }
            var translate = (TranslateTransform)card.RenderTransform;
            var animation = new DoubleAnimation(card.ActualHeight + 60, TimeSpan.FromMilliseconds(200))
            {
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseIn },
            };
            animation.Completed += (s, e) =>
            {
                Visibility = Visibility.Collapsed;
                Children.Clear();
                _dimmer.BeginAnimation(SolidColorBrush.ColorProperty, null);
                _dimmer.Color = Color.FromArgb(0, 0, 0, 0);
                if (onClose != null) onClose();
            };
            translate.BeginAnimation(TranslateTransform.YProperty, animation);
        }
    }

    /// <summary>圆角进度条（对齐 iOS StatBar 的胶囊轨道 + 渐变填充）</summary>
    public class BarView : Grid
    {
        readonly Border _track;
        readonly Border _fill;

        public BarView(double height = 6)
        {
            Height = height;
            _track = new Border { CornerRadius = new CornerRadius(height / 2), Background = Ui.B(Ui.P.Muted) };
            _fill = new Border
            {
                CornerRadius = new CornerRadius(height / 2),
                HorizontalAlignment = HorizontalAlignment.Left,
                Background = Ui.P.AccentGradient,
            };
            Children.Add(_track);
            Children.Add(_fill);
            SizeChanged += (s, e) => Apply();
        }

        double _value;

        /// <summary>0-100</summary>
        public double Value
        {
            get { return _value; }
            set { _value = value; Apply(); }
        }

        public Color? FillColor { get; set; }

        void Apply()
        {
            double ratio = Math.Max(0, Math.Min(1, _value / 100.0));
            double width = ActualWidth > 0 ? ActualWidth : 0;
            _fill.Width = width * ratio;
            _fill.Background = FillColor.HasValue ? Ui.B(FillColor.Value) : Ui.P.AccentGradient;
        }
    }
}
