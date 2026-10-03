package com.ovpn.panel.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNamingStrategy
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

/** 主控接口错误（对应 iOS APIError） */
class APIError(
    message: String,
    val cancelled: Boolean = false,
) : Exception(message)

/** 主控 HTTP 客户端（Bearer 令牌 + 统一包裹解析），对应 iOS APIClient */
object ApiClient {

    private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()

    val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        explicitNulls = false
        namingStrategy = JsonNamingStrategy.SnakeCase
    }

    private val http = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(40, TimeUnit.SECONDS)
        .writeTimeout(40, TimeUnit.SECONDS)
        .build()

    @Volatile
    private var _baseUrl: String = ""

    @Volatile
    private var _token: String? = null

    val baseUrl: String get() = _baseUrl

    val token: String? get() = _token

    /** 更新主控地址（统一去掉尾部斜杠） */
    fun setBaseUrl(url: String) {
        _baseUrl = url.trim().trimEnd('/')
    }

    fun setToken(value: String?) {
        _token = value
    }

    private fun makeRequest(
        path: String,
        method: String,
        query: Map<String, String>?,
        body: Map<String, Any?>?,
    ): Request {
        val currentBase = _baseUrl
        if (currentBase.isEmpty()) throw APIError("主控地址无效")
        val builder = (currentBase + path).toHttpUrlOrNull()?.newBuilder()
            ?: throw APIError("主控地址无效")
        query?.forEach { (key, value) -> builder.addQueryParameter(key, value) }

        val requestBuilder = Request.Builder()
            .url(builder.build())
            .method(
                method,
                when {
                    body != null -> jsonEncode(body).toRequestBody(JSON_MEDIA)
                    method == "POST" || method == "PUT" || method == "PATCH" ->
                        "{}".toRequestBody(JSON_MEDIA)
                    else -> null
                },
            )
            .header("Accept", "application/json")
        token?.let { requestBuilder.header("Authorization", "Bearer $it") }
        return requestBuilder.build()
    }

    /** 执行请求并返回 data 段（对应 request<T>(...)） */
    suspend fun <T> request(
        path: String,
        method: String = "GET",
        query: Map<String, String>? = null,
        body: Map<String, Any?>? = null,
        deserializer: DeserializationStrategy<T>,
    ): T {
        val request = makeRequest(path, method, query, body)
        val (code, text) = try {
            withContext(Dispatchers.IO) {
                http.newCall(request).execute().use { response ->
                    response.code to response.body?.string().orEmpty()
                }
            }
        } catch (e: IOException) {
            throw APIError("无法连接主控：${e.message ?: "网络异常"}")
        }

        val root = try {
            json.parseToJsonElement(text).jsonObject
        } catch (e: Exception) {
            if (code == 200) throw APIError("数据解析失败：响应不是合法的 JSON")
            throw APIError("主控返回异常（HTTP $code）")
        }

        val envelopeCode = root["code"]?.jsonPrimitive?.content?.toIntOrNull() ?: 0
        val message = root["message"]?.jsonPrimitive?.content.orEmpty()
        if (envelopeCode != 0) {
            throw APIError(message.ifEmpty { "请求失败" })
        }
        val data: JsonElement = root["data"] ?: throw APIError("数据解析失败：响应缺少 data")
        return try {
            json.decodeFromJsonElement(deserializer, data)
        } catch (e: Exception) {
            throw APIError("数据解析失败：${e.message ?: "字段不匹配"}")
        }
    }

    /** 无返回体请求 */
    suspend fun requestVoid(
        path: String,
        method: String = "POST",
        query: Map<String, String>? = null,
        body: Map<String, Any?>? = null,
    ) {
        request(path, method, query, body, EmptyPayload.serializer())
    }
}

/** 空返回体 */
@kotlinx.serialization.Serializable
class EmptyPayload

/** 将 Map 编码为 JSON 对象（与 Swift JSONSerialization 行为一致） */
fun jsonEncode(body: Map<String, Any?>): String = buildJsonObject {
    body.forEach { (key, value) -> put(key, toJson(value)) }
}.toString()

private fun toJson(value: Any?): JsonElement = when (value) {
    null -> JsonPrimitive(null as String?)
    is String -> JsonPrimitive(value)
    is Boolean -> JsonPrimitive(value)
    is Int -> JsonPrimitive(value)
    is Long -> JsonPrimitive(value)
    is Double -> JsonPrimitive(value)
    is Float -> JsonPrimitive(value)
    is Number -> JsonPrimitive(value)
    is Map<*, *> -> buildJsonObject {
        value.forEach { (k, v) -> put(k.toString(), toJson(v)) }
    }
    is List<*> -> buildJsonArray { value.forEach { add(toJson(it)) } }
    else -> JsonPrimitive(value.toString())
}

/** 便捷：构造 JSON 对象体 */
fun bodyOf(vararg pairs: Pair<String, Any?>): Map<String, Any?> = pairs.toMap()

/** 便捷：空 JSON 对象 */
val EmptyBody: JsonObject = buildJsonObject { }