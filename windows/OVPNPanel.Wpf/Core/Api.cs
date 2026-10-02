using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace OVPNPanel.Core
{
    /// <summary>主控接口错误</summary>
    public class ApiException : Exception
    {
        public bool IsCancelled { get; private set; }

        public ApiException(string message, bool cancelled = false) : base(message)
        {
            IsCancelled = cancelled;
        }

        public static ApiException BadURL() => new ApiException("主控地址无效");
        public static ApiException Cancelled() => new ApiException("请求已取消", true);

        /// <summary>归一化任意异常：取消类错误统一识别，避免误报</summary>
        public static ApiException From(Exception error)
        {
            if (error is ApiException) return (ApiException)error;
            if (error is TaskCanceledException || error is OperationCanceledException) return Cancelled();
            return new ApiException("无法连接主控：" + error.Message);
        }
    }

    /// <summary>主控 HTTP 客户端（Bearer 令牌 + 统一包裹解析）</summary>
    public sealed class ApiClient
    {
        public static readonly ApiClient Shared = new ApiClient();

        static readonly HttpClient Http = CreateClient();

        string _baseURL = "";
        string _token;

        static HttpClient CreateClient()
        {
            // 兼容 Win7：默认不启用 TLS1.2，这里显式打开
            try
            {
                ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // Tls12
            }
            catch { /* 老系统忽略 */ }
            var handler = new HttpClientHandler
            {
                AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
            };
            var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(40) };
            return client;
        }

        ApiClient() { }

        public void SetBaseURL(string url)
        {
            _baseURL = (url ?? "").Trim().TrimEnd('/');
        }

        public string CurrentBaseURL => _baseURL;

        public void SetToken(string value) { _token = value; }

        public string CurrentToken => _token;

        HttpRequestMessage MakeRequest(string path, string method, Dictionary<string, string> query, Dictionary<string, object> body)
        {
            if (string.IsNullOrEmpty(_baseURL)) throw ApiException.BadURL();
            var url = _baseURL + path;
            if (query != null && query.Count > 0)
            {
                var sb = new StringBuilder(url);
                sb.Append(url.IndexOf('?') >= 0 ? '&' : '?');
                bool first = true;
                foreach (var kv in query)
                {
                    if (!first) sb.Append('&');
                    first = false;
                    sb.Append(Uri.EscapeDataString(kv.Key)).Append('=').Append(Uri.EscapeDataString(kv.Value ?? ""));
                }
                url = sb.ToString();
            }

            var request = new HttpRequestMessage(new HttpMethod(method), url);
            request.Headers.TryAddWithoutValidation("Accept", "application/json");
            if (!string.IsNullOrEmpty(_token))
            {
                request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + _token);
            }
            if (body != null)
            {
                var json = J.Serialize(body);
                request.Content = new StringContent(json, Encoding.UTF8, "application/json");
            }
            return request;
        }

        /// <summary>执行请求并返回 data 段（原始字典）</summary>
        public async Task<Dictionary<string, object>> RequestRaw(string path, string method = "GET",
            Dictionary<string, string> query = null, Dictionary<string, object> body = null,
            CancellationToken cancellationToken = default(CancellationToken))
        {
            Dictionary<string, object> envelope;
            int statusCode = 0;
            try
            {
                using (var request = MakeRequest(path, method, query, body))
                using (var response = await Http.SendAsync(request, cancellationToken).ConfigureAwait(false))
                {
                    statusCode = (int)response.StatusCode;
                    var text = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    envelope = J.Dict(J.Parse(text));
                }
            }
            catch (Exception error)
            {
                throw ApiException.From(error);
            }

            if (envelope == null)
            {
                if (statusCode == 200) throw new ApiException("数据解析失败：响应不是合法的 JSON");
                throw new ApiException("主控返回异常（HTTP " + statusCode + "）");
            }

            var code = J.Int(envelope, "code");
            if (code != 0)
            {
                var message = J.Str(envelope, "message");
                throw new ApiException(string.IsNullOrEmpty(message) ? "请求失败" : message);
            }
            object data;
            if (!envelope.TryGetValue("data", out data) || data == null)
            {
                return new Dictionary<string, object>();
            }
            return J.Dict(data) ?? new Dictionary<string, object>();
        }

        public async Task<T> Request<T>(string path, Func<Dictionary<string, object>, T> mapper,
            string method = "GET", Dictionary<string, string> query = null,
            Dictionary<string, object> body = null, CancellationToken cancellationToken = default(CancellationToken))
        {
            var data = await RequestRaw(path, method, query, body, cancellationToken).ConfigureAwait(false);
            return mapper(data);
        }

        public async Task RequestVoid(string path, string method = "POST",
            Dictionary<string, string> query = null, Dictionary<string, object> body = null,
            CancellationToken cancellationToken = default(CancellationToken))
        {
            await RequestRaw(path, method, query, body, cancellationToken).ConfigureAwait(false);
        }

        // MARK: - 探活（配置主控地址时使用）

        public async Task<string> ProbeAsync(string normalizedBase, CancellationToken cancellationToken = default(CancellationToken))
        {
            var url = normalizedBase + "/api/v1/lines";
            try
            {
                using (var request = new HttpRequestMessage(HttpMethod.Get, url))
                {
                    request.Headers.TryAddWithoutValidation("Accept", "application/json");
                    using (var response = await Http.SendAsync(request, cancellationToken).ConfigureAwait(false))
                    {
                        var status = (int)response.StatusCode;
                        var text = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                        var decoded = J.Dict(J.Parse(text));
                        var isMaster = decoded != null && decoded.ContainsKey("code");
                        if (!isMaster && status < 200 || status > 299)
                        {
                            if (!isMaster) throw new ApiException("该地址不是有效的主控（HTTP " + status + "）");
                        }
                        if (!isMaster && (status < 200 || status > 299))
                            throw new ApiException("该地址不是有效的主控（HTTP " + status + "）");
                        return null;
                    }
                }
            }
            catch (ApiException) { throw; }
            catch (Exception error)
            {
                var apiError = ApiException.From(error);
                if (apiError.IsCancelled) throw ApiException.Cancelled();
                throw new ApiException("无法连接该地址：" + error.Message);
            }
        }

        // MARK: - 认证

        public Task<AuthResult> Login(string username, string password, CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "username", username }, { "password", password } };
            return Request("/api/v1/auth/login", AuthResult.From, "POST", null, body, ct);
        }

        public Task<AuthResult> Register(string username, string password, string email,
            string captchaToken, string captchaInput, CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "username", username }, { "password", password }, { "email", email } };
            if (!string.IsNullOrEmpty(captchaToken)) body["captchaToken"] = captchaToken;
            if (!string.IsNullOrEmpty(captchaInput)) body["captchaInput"] = captchaInput;
            return Request("/api/v1/auth/register", AuthResult.From, "POST", null, body, ct);
        }

        /// <summary>注册验证码（GET /api/auth/captcha，与 Web 端同一接口）</summary>
        public Task<CaptchaPayload> FetchCaptcha(CancellationToken ct = default(CancellationToken))
        {
            return Request("/api/auth/captcha", CaptchaPayload.From, "GET", null, null, ct);
        }

        public async Task<string> ForgotQuestion(string account, CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "account", account } };
            var result = await Request("/api/v1/auth/forgot", SimpleResult.From, "POST", null, body, ct).ConfigureAwait(false);
            return result.Question ?? "";
        }

        public Task ResetPassword(string account, string answer, string newPassword, CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "account", account }, { "answer", answer }, { "newPassword", newPassword } };
            return RequestVoid("/api/v1/auth/reset-password", "POST", null, body, ct);
        }

        // MARK: - 服务器与线路

        public Task<LinesPayload> FetchLines(CancellationToken ct = default(CancellationToken))
        {
            return Request("/api/v1/lines", LinesPayload.From, "GET", null, null, ct);
        }

        public Task<LineConfig> FetchLineConfig(int lineId, int nodeId, string family = "v4", CancellationToken ct = default(CancellationToken))
        {
            var query = new Dictionary<string, string> { { "nodeId", nodeId.ToString() }, { "family", family } };
            return Request("/api/v1/lines/" + lineId + "/config", LineConfig.From, "GET", query, null, ct);
        }

        public Task<UserStatusPayload> FetchUserStatus(CancellationToken ct = default(CancellationToken))
        {
            return Request("/api/v1/user/status", UserStatusPayload.From, "GET", null, null, ct);
        }

        /// <summary>用户主动断开：关闭主控侧在线会话并通知节点释放 peer</summary>
        public Task CloseSessions(CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "action", "disconnect" } };
            return RequestVoid("/api/v1/user/sessions", "POST", null, body, ct);
        }

        // MARK: - 用户中心

        public Task<UserCenterPayload> FetchUserCenter(CancellationToken ct = default(CancellationToken))
        {
            return Request("/api/v1/user", UserCenterPayload.From, "GET", null, null, ct);
        }

        public Task<TrafficPayload> FetchTraffic(int days = 15, CancellationToken ct = default(CancellationToken))
        {
            var query = new Dictionary<string, string> { { "days", days.ToString() } };
            return Request("/api/v1/user/traffic", TrafficPayload.From, "GET", query, null, ct);
        }

        public Task ChangePassword(string oldPassword, string newPassword, CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "oldPassword", oldPassword }, { "newPassword", newPassword } };
            return RequestVoid("/api/v1/user/password", "POST", null, body, ct);
        }

        public async Task<string> FetchSecurityQuestion(CancellationToken ct = default(CancellationToken))
        {
            var result = await Request("/api/v1/user/security", SimpleResult.From, "GET", null, null, ct).ConfigureAwait(false);
            return result.Question;
        }

        public Task UpdateSecurity(string question, string answer, CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "question", question }, { "answer", answer } };
            return RequestVoid("/api/v1/user/security", "POST", null, body, ct);
        }

        // MARK: - 套餐与订单

        public Task<PlansPayload> FetchPlans(CancellationToken ct = default(CancellationToken))
        {
            return Request("/api/v1/plans", PlansPayload.From, "GET", null, null, ct);
        }

        public Task<OrdersPayload> FetchOrders(int page = 1, CancellationToken ct = default(CancellationToken))
        {
            var query = new Dictionary<string, string> { { "page", page.ToString() } };
            return Request("/api/v1/orders", OrdersPayload.From, "GET", query, null, ct);
        }

        public Task<CreateOrderPayload> CreateOrder(int planId, string method, bool useCoins = false,
            bool payWithBalance = false, int? channelId = null, CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "plan_id", planId }, { "method", method } };
            if (useCoins) body["use_coins"] = true;
            if (payWithBalance) body["pay_with_balance"] = true;
            if (channelId.HasValue) body["channel_id"] = channelId.Value;
            return Request("/api/v1/orders", CreateOrderPayload.From, "POST", null, body, ct);
        }

        /// <summary>余额充值：创建充值订单并返回支付跳转地址</summary>
        public Task<CreateOrderPayload> RechargeBalance(double amountYuan, string method, int? channelId,
            CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "amount_yuan", amountYuan }, { "method", method } };
            if (channelId.HasValue) body["channel_id"] = channelId.Value;
            return Request("/api/v1/orders/recharge", CreateOrderPayload.From, "POST", null, body, ct);
        }

        public Task<CreateOrderPayload> PayOrder(int id, CancellationToken ct = default(CancellationToken))
        {
            return Request("/api/v1/orders/" + id + "/pay", CreateOrderPayload.From, "POST", null, null, ct);
        }

        public Task CancelOrder(int id, CancellationToken ct = default(CancellationToken))
        {
            return RequestVoid("/api/v1/orders/" + id + "/cancel", "POST", null, null, ct);
        }

        // MARK: - 公告

        public Task<AnnouncementsPayload> FetchAnnouncements(CancellationToken ct = default(CancellationToken))
        {
            return Request("/api/v1/announcements", AnnouncementsPayload.From, "GET", null, null, ct);
        }

        public Task MarkAnnouncementsRead(List<int> ids, CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "ids", ids } };
            return RequestVoid("/api/v1/announcements", "POST", null, body, ct);
        }

        // MARK: - 激活码

        public async Task<List<ActivationRecord>> FetchActivationRecords(CancellationToken ct = default(CancellationToken))
        {
            var payload = await Request("/api/v1/activation",
                d => new { Records = J.MapList(J.A(d, "records"), ActivationRecord.From) },
                "GET", null, null, ct).ConfigureAwait(false);
            return payload.Records;
        }

        public Task<ActivationPreview> PreviewActivation(string code, CancellationToken ct = default(CancellationToken))
        {
            var query = new Dictionary<string, string> { { "code", code } };
            return Request("/api/v1/activation", ActivationPreview.From, "GET", query, null, ct);
        }

        public Task<ActivationRedeemResult> RedeemActivation(string code, CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "code", code } };
            return Request("/api/v1/activation", ActivationRedeemResult.From, "POST", null, body, ct);
        }

        // MARK: - 金币

        public Task<CoinsPayload> FetchCoins(CancellationToken ct = default(CancellationToken))
        {
            return Request("/api/v1/coins", CoinsPayload.From, "GET", null, null, ct);
        }

        // MARK: - 反馈

        public async Task<List<FeedbackItem>> FetchFeedback(CancellationToken ct = default(CancellationToken))
        {
            var payload = await Request("/api/v1/feedback", FeedbackListPayload.From, "GET", null, null, ct).ConfigureAwait(false);
            return payload.Feedback;
        }

        public Task SubmitFeedback(int? lineId, string title, string content, string contact,
            CancellationToken ct = default(CancellationToken))
        {
            var body = new Dictionary<string, object> { { "title", title }, { "content", content }, { "contact", contact } };
            if (lineId.HasValue) body["lineId"] = lineId.Value;
            return RequestVoid("/api/v1/feedback", "POST", null, body, ct);
        }
    }
}
