#!/usr/bin/env python3
"""CI 界面检查用的模拟主控：返回与真实主控一致的响应结构（snake_case + 统一包裹）。

仅供自动化 UI 截图使用，不参与正式部署。
"""
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from datetime import datetime, timedelta, timezone

PORT = 8788
TZ = timezone(timedelta(hours=8))


def iso(days_offset: int = 0, hours: int = 0) -> str:
    return (datetime.now(TZ) + timedelta(days=days_offset, hours=hours)).strftime(
        "%Y-%m-%dT%H:%M:%S+08:00"
    )


USER = {
    "id": 1,
    "username": "demo",
    "email": "demo@example.com",
    "role": "user",
    "status": "active",
    "plan_id": 1,
    "plan_name": "标准套餐",
    "plan_expires_at": iso(days_offset=60),
    "traffic_limit_bytes": 1099511627776,
    "traffic_used_bytes": 6385000,
    "remain_bytes": 1093126627776,
    "speed_limit_kbps": 51200,
    "device_limit": 3,
    "level": 2,
    "coins": 320,
    "balance_cents": 1250,
    "balance_yuan": 12.5,
}

QUOTA = {"valid": True, "reason": "", "expired": False, "over_quota": False, "has_plan": True}

NODES = [
    {
        "id": 1, "name": "香港节点", "address": "203.0.113.10", "address_v6": "2001:db8::10",
        "has_ipv4": True, "has_ipv6": True, "region": "中国香港", "status": "online",
        "online_count": 12, "cpu_usage": 0.35, "mem_usage": 0.52, "disk_usage": 0.41,
        "load1": 0.62, "ratio": 1.0, "level_required": 1, "level_ok": True,
        "dco_enabled": True, "rx_rate": 1048576, "tx_rate": 5242880,
        "usable": True, "unusable_reason": "",
    },
    {
        "id": 2, "name": "日本节点", "address": "198.51.100.20", "address_v6": "",
        "has_ipv4": True, "has_ipv6": False, "region": "日本东京", "status": "online",
        "online_count": 5, "cpu_usage": 0.18, "mem_usage": 0.33, "disk_usage": 0.27,
        "load1": 0.24, "ratio": 1.5, "level_required": 1, "level_ok": True,
        "dco_enabled": False, "rx_rate": 2097152, "tx_rate": 1048576,
        "usable": True, "unusable_reason": "",
    },
]

LINES = [
    {"id": 1, "name": "香港 IEPL 01", "protocol": "udp", "port": 1194,
     "remark": "低延迟线路", "category": "香港节点"},
    {"id": 2, "name": "香港 BGP 02", "protocol": "tcp", "port": 443,
     "remark": "", "category": "香港节点"},
    {"id": 3, "name": "日本 软银 01", "protocol": "udp", "port": 1194,
     "remark": "", "category": "默认分类"},
]


def traffic_days(count: int):
    days = []
    now = datetime.now(TZ)
    for i in range(count - 1, -1, -1):
        day = now - timedelta(days=i)
        if i == 1:
            rx, tx = 4194304, 8878080        # 前一天流量较大，便于看图表
        elif i == 4:
            rx, tx = 524288, 1048576
        else:
            rx, tx = 20480 * (i % 3), 40960 * (i % 2)
        days.append({
            "day": day.strftime("%Y-%m-%d"),
            "rx_bytes": rx,
            "tx_bytes": tx,
            "total_bytes": rx + tx,
        })
    return days


def payload_for(path: str, query: str):
    if path == "/api/v1/auth/login":
        return {"token": "demo-token", "expires_in": 86400, "user": USER}
    if path == "/api/v1/user":
        return {
            "user": USER,
            "plan": {
                "id": 1, "name": "标准套餐", "description": "演示套餐：30 天 / 1TB",
                "price_cents": 1990, "duration_days": 30,
                "traffic_bytes": 1099511627776, "speed_limit_kbps": 51200,
                "device_limit": 3, "is_active": True,
            },
            "quota": QUOTA,
            "traffic": {
                "used_bytes": 6385000, "limit_bytes": 1099511627776,
                "remain_bytes": 1093126627776, "percent": 0.6,
            },
            "online_sessions": [
                {
                    "session_key": "1:u1:1001", "node_id": 1, "node_name": "香港节点",
                    "client_ip": "203.0.113.77", "virtual_ip": "10.8.0.2",
                    "rx_bytes": 1234567, "tx_bytes": 7654321,
                    "connected_at": iso(hours=-1),
                }
            ],
            "server_time": iso(),
        }
    if path == "/api/v1/user/traffic":
        m = re.search(r"days=(\d+)", query)
        count = int(m.group(1)) if m else 15
        days = traffic_days(count)
        return {
            "days": days,
            "total_bytes": sum(d["total_bytes"] for d in days),
            "days_count": len(days),
        }
    if path == "/api/v1/lines":
        return {
            "nodes": NODES,
            "lines": LINES,
            "level": 2,
            "quota": QUOTA,
            "speed_limit_kbps": 51200,
            "device_limit": 3,
        }
    if path == "/api/v1/plans":
        return {
            "plans": [
                {
                    "id": 1, "name": "标准套餐", "description": "30 天 / 1TB / 3 台设备",
                    "price_cents": 1990, "duration_days": 30,
                    "traffic_bytes": 1099511627776, "speed_limit_kbps": 51200,
                    "device_limit": 3, "is_current": True, "level": 2,
                    "coin_price": 300, "bonus_coins": 50,
                    "coin_exchange_enabled": True, "can_exchange": True,
                    "can_use_balance": True,
                },
                {
                    "id": 2, "name": "高级套餐", "description": "90 天 / 3TB / 5 台设备",
                    "price_cents": 4990, "duration_days": 90,
                    "traffic_bytes": 3298534883328, "speed_limit_kbps": 102400,
                    "device_limit": 5, "is_current": False, "level": 3,
                    "coin_price": 0, "bonus_coins": 0,
                    "coin_exchange_enabled": False, "can_exchange": False,
                    "can_use_balance": True,
                },
            ],
            "purchase_enabled": True,
            "currency_symbol": "¥",
            "node_online": 2,
            "node_total": 2,
            "user": {"level": 2, "coins": 320, "balance_cents": 1250, "balance_yuan": 12.5},
        }
    if path == "/api/v1/coins":
        return {
            "coins": 320,
            "invite_code": "DEMO8888",
            "invite_url": "https://panel.example.com/register?invite=DEMO8888",
            "invite_enabled": True,
            "invite_reward_coins": 50,
            "invitee_reward_coins": 20,
            "coin_exchange_enabled": True,
            "register_coins": 10,
            "recharge_coins_per_yuan": 100,
            "logs": [],
        }
    if path == "/api/v1/announcements":
        return {
            "announcements": [
                {
                    "id": 1, "title": "欢迎使用 OVPN",
                    "content": "这是一条用于界面检查的演示公告内容。",
                    "is_top": True, "created_at": iso(hours=-3), "read": False,
                }
            ],
            "unread_count": 1,
            "unread_ids": [1],
        }
    if path == "/api/v1/user/status":
        return {
            "status": "active", "quota": QUOTA, "block": None,
            "recent_kick": None, "notice": None, "server_time": iso(),
        }
    if path == "/api/v1/user/sessions":
        return {}
    if path == "/api/v1/orders":
        return {"orders": [], "page": 1, "page_size": 10, "total": 0}
    return None


class Handler(BaseHTTPRequestHandler):
    def _send(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle(self, method):
        from urllib.parse import urlparse
        parsed = urlparse(self.path)
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        data = payload_for(parsed.path, parsed.query)
        if data is None:
            self._send({"code": 404, "message": "not found", "data": None})
        else:
            self._send({"code": 0, "message": "", "data": data})

    def do_GET(self):
        self._handle("GET")

    def do_POST(self):
        self._handle("POST")

    def log_message(self, fmt, *args):
        print("[mock]", fmt % args)


if __name__ == "__main__":
    print(f"mock master listening on 127.0.0.1:{PORT}")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()