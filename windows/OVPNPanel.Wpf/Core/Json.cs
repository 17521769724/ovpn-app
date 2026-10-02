using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace OVPNPanel.Core
{
    /// <summary>
    /// 轻量 JSON 读写（纯 BCL 实现，不依赖 System.Web.Extensions，也不引入任何第三方 DLL，
    /// 保证最终产物是单一 EXE，且解析结果的类型可预期）：
    ///   对象 → Dictionary&lt;string, object&gt;
    ///   数组 → List&lt;object&gt;
    ///   字符串 → string，整数 → long，小数 → double，布尔 → bool，null → null
    ///
    /// 主控返回的字段为 snake_case，这里按 snake_case 直接取值，
    /// 对应 iOS 端 JSONDecoder 的 convertFromSnakeCase。
    /// </summary>
    public static class J
    {
        public static object Parse(string text)
        {
            if (string.IsNullOrEmpty(text)) return null;
            var parser = new Parser(text);
            var value = parser.ParseValue();
            parser.SkipWhiteSpace();
            return value;
        }

        public static string Serialize(object value)
        {
            var builder = new StringBuilder();
            WriteValue(builder, value);
            return builder.ToString();
        }

        // MARK: - 取值

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
            if (!d.TryGetValue(key, out value)) return null;
            return value as List<object>;
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
            var text = Convert.ToString(value, CultureInfo.InvariantCulture);
            return string.IsNullOrEmpty(text) ? null : text;
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
            var text = value as string;
            if (text != null)
            {
                long parsed;
                if (long.TryParse(text, NumberStyles.Any, CultureInfo.InvariantCulture, out parsed)) return parsed;
            }
            return 0;
        }

        static double ToDouble(object value)
        {
            if (value is double) return (double)value;
            if (value is long) return (long)value;
            if (value is int) return (int)value;
            if (value is decimal) return (double)(decimal)value;
            var text = value as string;
            if (text != null)
            {
                double parsed;
                if (double.TryParse(text, NumberStyles.Any, CultureInfo.InvariantCulture, out parsed)) return parsed;
            }
            return 0;
        }

        static bool ToBool(object value)
        {
            if (value is bool) return (bool)value;
            var text = value as string;
            if (text != null)
            {
                var lower = text.Trim().ToLowerInvariant();
                return lower == "true" || lower == "1" || lower == "yes";
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

        // MARK: - 序列化

        static void WriteValue(StringBuilder builder, object value)
        {
            if (value == null) { builder.Append("null"); return; }
            if (value is string) { WriteString(builder, (string)value); return; }
            if (value is bool) { builder.Append((bool)value ? "true" : "false"); return; }
            if (value is int || value is long) { builder.Append(Convert.ToInt64(value).ToString(CultureInfo.InvariantCulture)); return; }
            if (value is double || value is float || value is decimal)
            {
                builder.Append(Convert.ToDouble(value).ToString("R", CultureInfo.InvariantCulture));
                return;
            }
            var dict = value as IDictionary;
            if (dict != null)
            {
                builder.Append('{');
                bool first = true;
                foreach (DictionaryEntry entry in dict)
                {
                    if (!first) builder.Append(',');
                    first = false;
                    WriteString(builder, Convert.ToString(entry.Key));
                    builder.Append(':');
                    WriteValue(builder, entry.Value);
                }
                builder.Append('}');
                return;
            }
            var list = value as IEnumerable;
            if (list != null)
            {
                builder.Append('[');
                bool first = true;
                foreach (var item in list)
                {
                    if (!first) builder.Append(',');
                    first = false;
                    WriteValue(builder, item);
                }
                builder.Append(']');
                return;
            }
            WriteString(builder, Convert.ToString(value));
        }

        static void WriteString(StringBuilder builder, string text)
        {
            if (text == null) { builder.Append("null"); return; }
            builder.Append('"');
            foreach (var ch in text)
            {
                switch (ch)
                {
                    case '"': builder.Append("\\\""); break;
                    case '\\': builder.Append("\\\\"); break;
                    case '\n': builder.Append("\\n"); break;
                    case '\r': builder.Append("\\r"); break;
                    case '\t': builder.Append("\\t"); break;
                    case '\b': builder.Append("\\b"); break;
                    case '\f': builder.Append("\\f"); break;
                    default:
                        if (ch < 0x20) builder.Append("\\u").Append(((int)ch).ToString("x4"));
                        else builder.Append(ch);
                        break;
                }
            }
            builder.Append('"');
        }

        // MARK: - 解析

        sealed class Parser
        {
            readonly string _text;
            int _index;

            public Parser(string text) { _text = text; _index = 0; }

            public void SkipWhiteSpace()
            {
                while (_index < _text.Length && char.IsWhiteSpace(_text[_index])) _index++;
            }

            public object ParseValue()
            {
                SkipWhiteSpace();
                if (_index >= _text.Length) return null;
                char ch = _text[_index];
                switch (ch)
                {
                    case '{': return ParseObject();
                    case '[': return ParseArray();
                    case '"': return ParseString();
                    case 't':
                        Expect("true"); return true;
                    case 'f':
                        Expect("false"); return false;
                    case 'n':
                        Expect("null"); return null;
                    default: return ParseNumber();
                }
            }

            Dictionary<string, object> ParseObject()
            {
                var result = new Dictionary<string, object>();
                _index++; // {
                SkipWhiteSpace();
                if (_index < _text.Length && _text[_index] == '}') { _index++; return result; }
                while (_index < _text.Length)
                {
                    SkipWhiteSpace();
                    var key = ParseString();
                    SkipWhiteSpace();
                    if (_index >= _text.Length || _text[_index] != ':') throw Error("缺少 ':'");
                    _index++;
                    result[key] = ParseValue();
                    SkipWhiteSpace();
                    if (_index >= _text.Length) throw Error("对象未闭合");
                    if (_text[_index] == ',') { _index++; continue; }
                    if (_text[_index] == '}') { _index++; break; }
                    throw Error("对象中出现意外字符");
                }
                return result;
            }

            List<object> ParseArray()
            {
                var result = new List<object>();
                _index++; // [
                SkipWhiteSpace();
                if (_index < _text.Length && _text[_index] == ']') { _index++; return result; }
                while (_index < _text.Length)
                {
                    result.Add(ParseValue());
                    SkipWhiteSpace();
                    if (_index >= _text.Length) throw Error("数组未闭合");
                    if (_text[_index] == ',') { _index++; continue; }
                    if (_text[_index] == ']') { _index++; break; }
                    throw Error("数组中出现意外字符");
                }
                return result;
            }

            string ParseString()
            {
                if (_index >= _text.Length || _text[_index] != '"') throw Error("期望字符串");
                _index++;
                var builder = new StringBuilder();
                while (_index < _text.Length)
                {
                    char ch = _text[_index++];
                    if (ch == '"') return builder.ToString();
                    if (ch != '\\') { builder.Append(ch); continue; }
                    if (_index >= _text.Length) break;
                    char escape = _text[_index++];
                    switch (escape)
                    {
                        case '"': builder.Append('"'); break;
                        case '\\': builder.Append('\\'); break;
                        case '/': builder.Append('/'); break;
                        case 'b': builder.Append('\b'); break;
                        case 'f': builder.Append('\f'); break;
                        case 'n': builder.Append('\n'); break;
                        case 'r': builder.Append('\r'); break;
                        case 't': builder.Append('\t'); break;
                        case 'u':
                            if (_index + 4 <= _text.Length)
                            {
                                int code;
                                if (int.TryParse(_text.Substring(_index, 4), NumberStyles.HexNumber,
                                        CultureInfo.InvariantCulture, out code))
                                {
                                    builder.Append((char)code);
                                }
                                _index += 4;
                            }
                            break;
                        default: builder.Append(escape); break;
                    }
                }
                throw Error("字符串未闭合");
            }

            object ParseNumber()
            {
                int start = _index;
                while (_index < _text.Length)
                {
                    char ch = _text[_index];
                    if (char.IsDigit(ch) || ch == '-' || ch == '+' || ch == '.' || ch == 'e' || ch == 'E') _index++;
                    else break;
                }
                var token = _text.Substring(start, _index - start);
                if (token.Length == 0) throw Error("非法数字");
                if (token.IndexOf('.') < 0 && token.IndexOf('e') < 0 && token.IndexOf('E') < 0)
                {
                    long parsed;
                    if (long.TryParse(token, NumberStyles.Integer, CultureInfo.InvariantCulture, out parsed)) return parsed;
                }
                double value;
                if (double.TryParse(token, NumberStyles.Float, CultureInfo.InvariantCulture, out value)) return value;
                throw Error("非法数字：" + token);
            }

            void Expect(string literal)
            {
                if (_index + literal.Length > _text.Length
                    || string.CompareOrdinal(_text, _index, literal, 0, literal.Length) != 0)
                {
                    throw Error("期望 " + literal);
                }
                _index += literal.Length;
            }

            Exception Error(string message)
            {
                return new FormatException("JSON 解析失败（位置 " + _index + "）：" + message);
            }
        }
    }
}
