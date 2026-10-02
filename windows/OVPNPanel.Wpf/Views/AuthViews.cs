using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using OVPNPanel.Theme;

namespace OVPNPanel.Core
{
    // MARK: - 主控地址配置

    public class SetupView : Screen
    {
        readonly TextFieldControl _address;
        readonly Grid _buttonHost = new Grid();

        public SetupView()
        {
            HidesHeader = true;
            _address = C.TextField("主控地址", "https://你的域名", LocalStore.MasterURL ?? "");

            var logo = new Border
            {
                Width = 64,
                Height = 64,
                CornerRadius = new CornerRadius(DS.Radius.Xxl),
                Background = Ui.P.AccentGradient,
                HorizontalAlignment = HorizontalAlignment.Center,
                Child = new Grid { Children = { Ui.Icon("shieldFill", 28, Colors.White, 2) } },
                Effect = new System.Windows.Media.Effects.DropShadowEffect
                {
                    BlurRadius = 14, ShadowDepth = 6, Opacity = 0.35, Color = DS.Brand.Green,
                },
            };

            var heading = Ui.Stack(Orientation.Vertical, 10);
            heading.Children.Add(logo);
            var title = Ui.Text("OVPN 客户端", DS.FontSize.Title, FontWeights.SemiBold, Ui.P.Foreground);
            title.HorizontalAlignment = HorizontalAlignment.Center;
            title.Margin = new Thickness(0, 10, 0, 0);
            heading.Children.Add(title);
            var subtitle = Ui.Caption("首次使用请填写你的主控地址");
            subtitle.HorizontalAlignment = HorizontalAlignment.Center;
            heading.Children.Add(subtitle);
            heading.Margin = new Thickness(0, 0, 0, 8);

            var form = Ui.Stack(Orientation.Vertical, 14);
            form.Children.Add(_address);
            form.Children.Add(_buttonHost);
            RebuildButton();

            var footnote = Ui.Text("请填写主控面板的访问地址，例如 https://panel.example.com\n客户端将使用该地址登录并获取线路",
                DS.FontSize.Caption, FontWeights.Normal, Ui.P.MutedForeground, TextWrapping.Wrap);
            footnote.TextAlignment = TextAlignment.Center;
            footnote.HorizontalAlignment = HorizontalAlignment.Center;

            var content = Ui.Stack(Orientation.Vertical, 20);
            content.Margin = new Thickness(0, 40, 0, 20);
            content.Children.Add(heading);
            content.Children.Add(C.Card(form));
            content.Children.Add(footnote);

            Content = Ui.ScrollPage(content);
        }

        void RebuildButton()
        {
            _buttonHost.Children.Clear();
            _buttonHost.Children.Add(C.Button("连接并继续", () => Ui.Fire(Submit), BtnStyle.Primary, "arrowRight"));
        }

        async System.Threading.Tasks.Task Submit()
        {
            var value = (_address.Value ?? "").Trim();
            if (value.Length == 0)
            {
                App.ShowToast("请输入主控地址", BannerKind.Warning);
                return;
            }
            RebuildButton();
            _buttonHost.Children.Clear();
            _buttonHost.Children.Add(C.Button("连接并继续", null, BtnStyle.Primary, null, DS.Size.ButtonHeight, true));
            try
            {
                await App.ConfigureMaster(value);
                App.ShowToast("主控地址已保存", BannerKind.Success);
            }
            finally
            {
                RebuildButton();
            }
        }
    }

    // MARK: - 登录

    public class LoginView : Screen
    {
        readonly TextFieldControl _account;
        readonly TextFieldControl _password;
        readonly Grid _buttonHost = new Grid();
        bool _loading;

        public LoginView()
        {
            HidesHeader = true;
            _account = C.TextField("账号", "用户名或邮箱", LocalStore.LastAccount ?? "");
            _password = C.TextField("密码", "登录密码", "", true);

            var logo = new Border
            {
                Width = 52,
                Height = 52,
                CornerRadius = new CornerRadius(DS.Radius.Lg),
                HorizontalAlignment = HorizontalAlignment.Center,
                Background = new LinearGradientBrush(DS.IconColor.Green, DS.IconColor.Teal, 45),
                Child = new Grid { Children = { Ui.Icon("person", 24, Colors.White, 2) } },
                Effect = new System.Windows.Media.Effects.DropShadowEffect
                {
                    BlurRadius = 12, ShadowDepth = 5, Opacity = 0.32, Color = DS.IconColor.Green,
                },
            };

            var heading = Ui.Stack(Orientation.Vertical, 8);
            heading.Children.Add(logo);
            var title = Ui.Text("登录账号", DS.FontSize.Title, FontWeights.SemiBold, Ui.P.Foreground);
            title.HorizontalAlignment = HorizontalAlignment.Center;
            title.Margin = new Thickness(0, 10, 0, 0);
            heading.Children.Add(title);
            var master = Ui.Caption(App.MasterURL);
            master.HorizontalAlignment = HorizontalAlignment.Center;
            heading.Children.Add(master);

            var form = Ui.Stack(Orientation.Vertical, 14);
            form.Children.Add(_account);
            form.Children.Add(_password);
            form.Children.Add(_buttonHost);
            RebuildButton();

            var links = Ui.Stack(Orientation.Horizontal, 14);
            links.HorizontalAlignment = HorizontalAlignment.Center;
            links.Children.Add(LinkButton("注册新账号", () => ShowRegister()));
            links.Children.Add(Ui.VLine(10));
            links.Children.Add(LinkButton("找回密码", () => ShowForgot()));
            links.Children.Add(Ui.VLine(10));
            links.Children.Add(LinkButton("更换主控", ConfirmResetMaster));

            var content = Ui.Stack(Orientation.Vertical, 18);
            content.Margin = new Thickness(0, 36, 0, 20);
            content.Children.Add(heading);
            content.Children.Add(C.Card(form));
            content.Children.Add(links);

            Content = Ui.ScrollPage(content);
        }

        static UIElement LinkButton(string text, Action action)
        {
            var label = Ui.Text(text, DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.Foreground);
            label.Padding = new Thickness(2, 4, 2, 4);
            return label.Clickable(action, 0.94);
        }

        public override void Refresh()
        {
            RebuildButton();
        }

        void RebuildButton()
        {
            _buttonHost.Children.Clear();
            _buttonHost.Children.Add(C.Button("登录", () => Ui.Fire(Submit), BtnStyle.Primary, "arrowRight",
                DS.Size.ButtonHeight, _loading, _loading));
        }

        async System.Threading.Tasks.Task Submit()
        {
            var account = _account.Value ?? "";
            var password = _password.Value ?? "";
            if (account.Length == 0 || password.Length == 0)
            {
                App.ShowToast("请输入账号与密码", BannerKind.Warning);
                return;
            }
            _loading = true;
            RebuildButton();
            try
            {
                await App.Login(account, password);
                App.ShowToast("登录成功", BannerKind.Success);
            }
            finally
            {
                _loading = false;
                RebuildButton();
            }
        }

        void ShowRegister()
        {
            var view = new RegisterView();
            MainShell.PresentSheet("注册账号", view);
        }

        void ShowForgot()
        {
            var view = new ForgotPasswordView();
            MainShell.PresentSheet("找回密码", view);
        }

        void ConfirmResetMaster()
        {
            MainShell.PresentAlert("更换主控地址？", "将退出登录并返回主控地址配置页", "确定",
                () => App.ResetMaster(), true);
        }
    }

    // MARK: - 注册（含与 Web 端一致的验证码）

    public class RegisterView : Screen
    {
        readonly TextFieldControl _username;
        readonly TextFieldControl _password;
        readonly TextFieldControl _confirm;
        readonly TextFieldControl _email;
        readonly TextFieldControl _captchaInput;
        readonly Border _captchaBox;
        readonly TextBlock _captchaLabel;
        readonly Grid _captchaRow = new Grid();
        readonly Grid _buttonHost = new Grid();
        readonly StackPanel _captchaHint;

        string _captchaCode = "";
        string _captchaToken = "";
        bool _captchaEnabled;
        bool _loadingCaptcha;
        bool _loading;

        public RegisterView()
        {
            HidesHeader = true;
            _username = C.TextField("用户名", "3-32 位字母/数字/下划线");
            _password = C.TextField("密码", "至少 6 位", "", true);
            _confirm = C.TextField("确认密码", "再次输入密码", "", true);
            _email = C.TextField("邮箱（选填）", "用于找回密码");
            _captchaInput = C.TextField("验证码", "输入右侧 4 位字符");

            _captchaLabel = Ui.Text("点击获取", 17, FontWeights.Bold, DS.IconColor.Amber);
            _captchaLabel.FontFamily = new FontFamily("Consolas, Segoe UI");
            _captchaLabel.HorizontalAlignment = HorizontalAlignment.Center;
            _captchaBox = new Border
            {
                Width = 108,
                Height = DS.Size.InputHeight,
                CornerRadius = new CornerRadius(DS.Radius.Lg),
                Background = Ui.B(Ui.Alpha(DS.IconColor.Amber, 0.14)),
                BorderBrush = Ui.B(Ui.Alpha(DS.IconColor.Amber, 0.45)),
                BorderThickness = new Thickness(1),
                Child = new Grid { Children = { _captchaLabel } },
                VerticalAlignment = VerticalAlignment.Bottom,
            };
            _captchaBox.Clickable(() => Ui.Fire(LoadCaptcha));

            var captchaRow = Ui.Stack(Orientation.Horizontal, 10);
            var inputHost = new Grid { Width = 200 };
            inputHost.Children.Add(_captchaInput);
            captchaRow.Children.Add(inputHost);
            captchaRow.Children.Add(_captchaBox);
            _captchaRow.Children.Add(captchaRow);

            _captchaHint = Ui.Stack(Orientation.Vertical, 0);
            _captchaHint.Children.Add(Ui.Caption("看不清？点击橙色方块刷新验证码"));
            _captchaHint.Visibility = Visibility.Collapsed;

            var form = Ui.Stack(Orientation.Vertical, 14);
            form.Children.Add(_username);
            form.Children.Add(_password);
            form.Children.Add(_confirm);
            form.Children.Add(_email);
            form.Children.Add(_captchaRow);
            form.Children.Add(_captchaHint);
            form.Children.Add(_buttonHost);
            RebuildButton();

            var note = Ui.Text("注册即表示同意站点服务条款；注册后可直接登录使用",
                DS.FontSize.Caption, FontWeights.Normal, Ui.P.MutedForeground, TextWrapping.Wrap);
            note.TextAlignment = TextAlignment.Center;
            note.HorizontalAlignment = HorizontalAlignment.Center;

            var content = Ui.Stack(Orientation.Vertical, 16);
            content.Margin = new Thickness(0, 4, 0, 8);
            content.Children.Add(C.Card(form));
            content.Children.Add(note);
            Content = content;

            Ui.Fire(LoadCaptcha);
        }

        void RebuildButton()
        {
            _buttonHost.Children.Clear();
            _buttonHost.Children.Add(C.Button("注册并登录", () => Ui.Fire(Submit), BtnStyle.Primary, "tabInvite",
                DS.Size.ButtonHeight, _loading, _loading));
        }

        /// <summary>拉取验证码（与 Web 端同一接口，码值直接下发）</summary>
        async System.Threading.Tasks.Task LoadCaptcha()
        {
            _loadingCaptcha = true;
            _captchaLabel.Text = "…";
            try
            {
                var payload = await ApiClient.Shared.FetchCaptcha();
                _captchaEnabled = payload.Enabled;
                _captchaCode = payload.Code;
                _captchaToken = payload.Token;
                _captchaInput.Value = "";
                _captchaRow.Visibility = _captchaEnabled ? Visibility.Visible : Visibility.Collapsed;
                _captchaHint.Visibility = _captchaEnabled ? Visibility.Visible : Visibility.Collapsed;
                _captchaLabel.Text = string.IsNullOrEmpty(_captchaCode) ? "点击获取" : _captchaCode;
            }
            catch
            {
                _captchaEnabled = false;
                _captchaRow.Visibility = Visibility.Collapsed;
                _captchaHint.Visibility = Visibility.Collapsed;
            }
            finally
            {
                _loadingCaptcha = false;
                if (_loadingCaptcha) _captchaLabel.Text = "…";
            }
        }

        async System.Threading.Tasks.Task Submit()
        {
            var username = (_username.Value ?? "").Trim();
            var password = _password.Value ?? "";
            var confirm = _confirm.Value ?? "";
            var email = _email.Value ?? "";

            if (username.Length < 3) { App.ShowToast("用户名至少 3 位", BannerKind.Warning); return; }
            if (password.Length < 6) { App.ShowToast("密码至少 6 位", BannerKind.Warning); return; }
            if (password != confirm) { App.ShowToast("两次输入的密码不一致", BannerKind.Warning); return; }
            if (_captchaEnabled && (_captchaInput.Value ?? "").Trim().Length == 0)
            {
                App.ShowToast("请输入验证码", BannerKind.Warning);
                return;
            }

            _loading = true;
            RebuildButton();
            try
            {
                await App.Register(username, password, email, _captchaToken, _captchaInput.Value ?? "");
                App.ShowToast("注册成功，已自动登录", BannerKind.Success);
                var shell = MainShell.Current;
                if (shell != null) shell.Sheet.Dismiss();
            }
            catch (Exception error)
            {
                App.Report(error);
                if (_captchaEnabled) await LoadCaptcha();
            }
            finally
            {
                _loading = false;
                RebuildButton();
            }
        }
    }

    // MARK: - 找回密码（密保问题）

    public class ForgotPasswordView : Screen
    {
        readonly StackPanel _body = Ui.Stack(Orientation.Vertical, 16);
        readonly TextFieldControl _account = C.TextField("账号", "用户名或邮箱");
        readonly TextFieldControl _answer = C.TextField("密保答案", "不区分大小写");
        readonly TextFieldControl _newPassword = C.TextField("新密码", "至少 6 位", "", true);
        readonly Grid _buttonHost = new Grid();
        readonly TextBlock _questionLabel = Ui.Text("", DS.FontSize.Body, FontWeights.Normal, Ui.P.Foreground, TextWrapping.Wrap);

        int _step = 1;
        string _question = "";
        bool _loading;
        bool _done;

        public ForgotPasswordView()
        {
            HidesHeader = true;
            Content = _body;
            Rebuild();
        }

        void Rebuild()
        {
            _body.Children.Clear();
            _body.Margin = new Thickness(0, 4, 0, 8);

            if (_done)
            {
                var stack = Ui.Stack(Orientation.Vertical, 12);
                stack.HorizontalAlignment = HorizontalAlignment.Center;
                var check = Ui.Icon("checkCircle", 34, Ui.P.OnlineText, 2);
                check.HorizontalAlignment = HorizontalAlignment.Center;
                stack.Children.Add(check);
                var title = Ui.Text("密码已重置", DS.FontSize.Section, FontWeights.SemiBold, Ui.P.Foreground);
                title.HorizontalAlignment = HorizontalAlignment.Center;
                stack.Children.Add(title);
                var detail = Ui.Caption("请使用新密码登录");
                detail.HorizontalAlignment = HorizontalAlignment.Center;
                stack.Children.Add(detail);
                var button = C.Button("返回登录", DismissSheet);
                button.Width = 180;
                button.HorizontalAlignment = HorizontalAlignment.Center;
                stack.Children.Add(button);
                _body.Children.Add(C.Card(stack));
                return;
            }

            var form = Ui.Stack(Orientation.Vertical, 14);
            if (_step == 1)
            {
                form.Children.Add(_account);
                _buttonHost.Children.Clear();
                _buttonHost.Children.Add(C.Button("下一步", () => Ui.Fire(FetchQuestion), BtnStyle.Primary,
                    "arrowRight", DS.Size.ButtonHeight, _loading, _loading));
                form.Children.Add(_buttonHost);
            }
            else
            {
                var questionBlock = Ui.Stack(Orientation.Vertical, 6);
                questionBlock.Children.Add(Ui.Text("密保问题", DS.FontSize.BodySmall, FontWeights.Normal, Ui.P.MutedForeground));
                _questionLabel.Text = _question;
                _questionLabel.Margin = new Thickness(12);
                var questionBox = Ui.Box(_questionLabel, Ui.P.Muted, DS.Radius.Md, null, 0, new Thickness(0));
                questionBlock.Children.Add(questionBox);
                form.Children.Add(questionBlock);
                form.Children.Add(_answer);
                form.Children.Add(_newPassword);
                _buttonHost.Children.Clear();
                _buttonHost.Children.Add(C.Button("重置密码", () => Ui.Fire(Reset), BtnStyle.Primary, "key",
                    DS.Size.ButtonHeight, _loading, _loading));
                form.Children.Add(_buttonHost);
            }
            _body.Children.Add(C.Card(form));
        }

        void DismissSheet()
        {
            var shell = MainShell.Current;
            if (shell != null) shell.Sheet.Dismiss();
        }

        async System.Threading.Tasks.Task FetchQuestion()
        {
            var account = (_account.Value ?? "").Trim();
            if (account.Length == 0) { App.ShowToast("请输入账号", BannerKind.Warning); return; }
            _loading = true;
            Rebuild();
            try
            {
                _question = await ApiClient.Shared.ForgotQuestion(account);
                _step = 2;
            }
            finally
            {
                _loading = false;
                Rebuild();
            }
        }

        async System.Threading.Tasks.Task Reset()
        {
            var answer = (_answer.Value ?? "").Trim();
            var newPassword = _newPassword.Value ?? "";
            if (answer.Length == 0) { App.ShowToast("请输入密保答案", BannerKind.Warning); return; }
            if (newPassword.Length < 6) { App.ShowToast("新密码至少 6 位", BannerKind.Warning); return; }
            _loading = true;
            Rebuild();
            try
            {
                await ApiClient.Shared.ResetPassword((_account.Value ?? "").Trim(), answer, newPassword);
                _done = true;
                App.ShowToast("密码已重置", BannerKind.Success);
            }
            finally
            {
                _loading = false;
                Rebuild();
            }
        }
    }
}
