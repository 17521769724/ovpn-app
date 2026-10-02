using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Web.Script.Serialization;

namespace OVPNPanel.Core
{
    /// <summary>
    /// 轻量 JSON 读取工具（基于 .NET Framework 自带的 JavaScriptSerializer，
    /// 不引入任何第三方 DLL，保证最终产物是单一 EXE）。
    ///
    /// 主控返回的字段为 snake_case，这里按 snake_case 直接取值，
    /// 对应 iOS 端 JSONDecoder 的 convertFromSnakeCase。
    /// </summary>
    public static class J
    {
        static readonly JavaScriptSerializer Serializer = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };

        public static object Parse(string text)
        {
            if (string.IsNullOrEmpty(text)) return null;
            return Serializer.DeserializeObject(text);
        }

        public static string Serialize(object value) => Serializer.Serialize(value);

        public static Dictionary<string, object> Dict(object value)
        {
            return value as Dictionary<string, object>;
        }

        public static List<object> Arr(object value)
        {
            return value as List<object>;
        }

        public static Dictionary<string, object> D(Dictionary<string, object> d, string key)
        {
            if (d == null) return null;
            object value;
            return d.TryGetValue(key, out value) ? value as Dictionary<string, object> : null;
        }

        public static List<object> A(Dictionary<string, object> d, string key)
        {
            if (d == null) return null;
            object value;
            return d.TryGetValue(key, out value) ? value as List<object> : null;
        }

        public static string Str(Dictionary<string, object> d, string key, string fallback = "")
        {
            if (d == null) return fallback;
            object value;
            if (!d.TryGetValue(key, out value) || value == null) return fallback;
            return Convert.ToString(value, CultureInfo.InvariantCulture);
        }

        public static string OptStr(Dictionary<string, object> d, string key)
        {
            if (d == null) return null;
            object value;
            if (!d.TryGetValue(key, out value) || value == null) return null;
            var s = Convert.ToString(value, CultureInfo.InvariantCulture);
            return string.IsNullOrEmpty(s) ? null : s;
        }

        public static int Int(Dictionary<string, object> d, string key, int fallback = 0)
        {
            return (int)Long(d, key, fallback);
        }

        public static int? OptInt(Dictionary<string, object> d, string key)
        {
            if (d == null) return null;
            object value;
            if (!d.TryGetValue(key, out value) || value == null) return null;
            return (int)ToLong(value);
        }

        public static long Long(Dictionary<string, object> d, string key, long fallback = 0)
        {
            if (d == null) return fallback;
            object value;
            if (!d.TryGetValue(key, out value) || value == null) return fallback;
            return ToLong(value);
        }

        public static long? OptLong(Dictionary<string, object> d, string key)
        {
            if (d == null) return null;
            object value;
            if (!d.TryGetValue(key, out value) || value == null) return null;
            return ToLong(value);
        }

        public static double Dbl(Dictionary<string, object> d, string key, double fallback = 0)
        {
            if (d == null) return fallback;
            object value;
            if (!d.TryGetValue(key, out value) || value == null) return fallback;
            return ToDouble(value);
        }

        public static bool Bool(Dictionary<string, object> d, string key, bool fallback = false)
        {
            if (d == null) return fallback;
            object value;
            if (!d.TryGetValue(key, out value) || value == null) return fallback;
            return ToBool(value);
        }

        public static bool? OptBool(Dictionary<string, object> d, string key)
        {
            if (d == null) return null;
            object value;
            if (!d.TryGetValue(key, out value) || value == null) return null;
            return ToBool(value);
        }

        static long ToLong(object value)
        {
            if (value is long) return (long)value;
            if (value is int) return (int)value;
            if (value is double) return (long)Math.Round((double)value);
            if (value is decimal) return (long)Math.Round((decimal)value);
            if (value is string)
            {
                long parsed;
                if (long.TryParse((string)value, NumberStyles.Any, CultureInfo.InvariantCulture, out parsed)) return parsed;
            }
            return 0;
        }

        static double ToDouble(object value)
        {
            if (value is double) return (double)value;
            if (value is int) return (int)value;
            if (value is long) return (long)value;
            if (value is decimal) return (double)(decimal)value;
            if (value is string)
            {
                double parsed;
                if (double.TryParse((string)value, NumberStyles.Any, CultureInfo.InvariantCulture, out parsed)) return parsed;
            }
            return 0;
        }

        static bool ToBool(object value)
        {
            if (value is bool) return (bool)value;
            if (value is string)
            {
                var s = ((string)value).Trim().ToLowerInvariant();
                return s == "true" || s == "1" || s == "yes";
            }
            if (value is long) return (long)value != 0;
            if (value is int) return (int)value != 0;
            return false;
        }

        /// <summary>把 object 数组映射为目标类型列表（自动跳过 null 项）</summary>
        public static List<T> MapList<T>(List<object> source, Func<Dictionary<string, object>, T> mapper)
        {
            var result = new List<T>();
            if (source == null) return result;
            foreach (var item in source)
            {
                var d = item as Dictionary<string, object>;
                if (d != null) result.Add(mapper(d));
            }
            return result;
        }
    }
}
