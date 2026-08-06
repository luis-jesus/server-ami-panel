#!/usr/bin/env python3

from __future__ import annotations

import argparse
import grp
import html
import json
import mimetypes
import os
import platform
import pwd
import re
import shutil
import socket
import stat
import subprocess
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, unquote, urlparse
from urllib.request import Request, urlopen
from xml.etree import ElementTree

ROOT_DIR = Path(__file__).resolve().parent.parent
STATIC_DIR = Path(__file__).resolve().parent / "static"
INVENTORY_DIR = ROOT_DIR / "output"
UPDATE_DIR = ROOT_DIR / "update-reports"
MAX_LOG_LINES = 400
MAX_FILE_PREVIEW = 256 * 1024
SERVICE_ACTIONS = ("start", "stop", "restart")
HOME_BRIEFING_CACHE_TTL = 60
HOME_BRIEFING_CACHE_FILE = ROOT_DIR / "config" / "home_briefing_cache.json"
HOME_BRIEFING_HISTORY_DAYS = 7
HOME_BRIEFING_VISIBLE_DAYS = 2
CISA_ADVISORIES_FEED_URL = "https://www.cisa.gov/cybersecurity-advisories/all.xml"
CISA_KEV_FEED_URL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
SECURITY_NEWS_FEEDS = (
    {
        "name": "CISA Advisories",
        "short_name": "CISA",
        "url": CISA_ADVISORIES_FEED_URL,
        "kind": "official",
        "category": "official",
        "priority": 4,
    },
    {
        "name": "The Hacker News",
        "short_name": "The Hacker News",
        "url": "https://feeds.feedburner.com/TheHackersNews",
        "kind": "blog",
        "category": "blog",
        "priority": 1,
    },
    {
        "name": "BleepingComputer",
        "short_name": "BleepingComputer",
        "url": "https://www.bleepingcomputer.com/feed/",
        "kind": "news",
        "category": "news",
        "priority": 2,
    },
    {
        "name": "Krebs on Security",
        "short_name": "Krebs on Security",
        "url": "https://krebsonsecurity.com/feed/",
        "kind": "analysis",
        "category": "analysis",
        "priority": 3,
    },
)
YAHOO_CHART_URL = "https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?interval=1d&range=5d"
MARKET_SYMBOLS = (
    {"symbol": "^GSPC", "label": "S&P 500", "kind": "indice", "precision": 2, "suffix": " pts"},
    {"symbol": "^IXIC", "label": "Nasdaq", "kind": "indice", "precision": 2, "suffix": " pts"},
    {"symbol": "^DJI", "label": "Dow Jones", "kind": "indice", "precision": 2, "suffix": " pts"},
    {"symbol": "MXN=X", "label": "USD/MXN", "kind": "fx", "precision": 4},
    {"symbol": "EURUSD=X", "label": "EUR/USD", "kind": "fx", "precision": 4},
    {"symbol": "JPY=X", "label": "USD/JPY", "kind": "fx", "precision": 3},
)
HOME_BRIEFING_CACHE: dict[str, Any] = {"expires_at": 0.0, "payload": None}
HOME_BRIEFING_LOCK = threading.Lock()


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def safe_stat_mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0


def parse_key_value_file(file_path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not file_path.is_file():
        return data

    for line in file_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key:
            data[key] = value
    return data


def read_lines(file_path: Path, limit: int = 200) -> list[str]:
    if not file_path.is_file():
        return []
    return file_path.read_text(encoding="utf-8", errors="replace").splitlines()[:limit]


def read_json_file(file_path: Path) -> dict[str, Any]:
    if not file_path.is_file():
        return {}
    try:
        return json.loads(file_path.read_text(encoding="utf-8", errors="replace"))
    except json.JSONDecodeError:
        return {}


def write_json_file(file_path: Path, payload: dict[str, Any]) -> None:
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_text(json.dumps(payload, indent=2, ensure_ascii=True), encoding="utf-8")


def count_warning_lines(file_path: Path) -> int:
    return len([line for line in read_lines(file_path, limit=1000) if line.strip()])


def format_timestamp(epoch_value: float) -> str:
    return datetime.fromtimestamp(epoch_value, tz=timezone.utc).replace(microsecond=0).isoformat()


def command_exists(command_name: str) -> bool:
    return shutil.which(command_name) is not None


def run_command(command: list[str], timeout: int = 10) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def parse_os_release() -> dict[str, str]:
    file_path = Path("/etc/os-release")
    if not file_path.is_file():
        return {}

    data: dict[str, str] = {}
    for raw_line in file_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key] = value.strip().strip('"')
    return data


def detect_package_backend() -> str:
    if command_exists("dpkg-query"):
        return "dpkg"
    if command_exists("zypper"):
        return "zypper"
    if command_exists("rpm"):
        return "rpm"
    if command_exists("pacman"):
        return "pacman"
    if command_exists("apk"):
        return "apk"
    if command_exists("xbps-query"):
        return "xbps"
    if command_exists("qlist"):
        return "portage"
    if command_exists("nix-store"):
        return "nix"
    return "unknown"


def detect_init_system() -> str:
    if command_exists("systemctl") and Path("/run/systemd/system").is_dir():
        return "systemd"
    if command_exists("openrc") or command_exists("rc-status"):
        return "openrc"
    if command_exists("sv"):
        return "runit"
    if command_exists("s6-rc"):
        return "s6"
    if Path("/etc/init.d").is_dir():
        return "sysvinit"
    return "unknown"


def detect_firewall_backend() -> str:
    if command_exists("ufw"):
        return "ufw"
    if command_exists("firewall-cmd"):
        return "firewalld"
    if command_exists("nft"):
        return "nftables"
    if command_exists("iptables"):
        return "iptables"
    return "none"


def detect_container_backends() -> list[str]:
    backends: list[str] = []
    for backend_name, command_name in (
        ("docker", "docker"),
        ("podman", "podman"),
        ("incus", "incus"),
        ("lxc", "lxc"),
        ("libvirt", "virsh"),
    ):
        if command_exists(command_name):
            backends.append(backend_name)
    return backends


def detect_ip_addresses() -> list[str]:
    addresses: list[str] = []
    if command_exists("ip"):
        result = run_command(["ip", "-o", "addr", "show", "up", "scope", "global"], timeout=6)
        if result and result.returncode == 0:
            for line in result.stdout.splitlines():
                fields = line.split()
                if len(fields) < 4:
                    continue
                address = fields[3].split("/", 1)[0]
                if address not in addresses:
                    addresses.append(address)

    if addresses:
        return addresses

    try:
        for item in socket.getaddrinfo(socket.gethostname(), None):
            address = item[4][0]
            if address.startswith("127.") or address == "::1":
                continue
            if address not in addresses:
                addresses.append(address)
    except socket.gaierror:
        return []
    return addresses


def parse_port_token(token: str) -> int | None:
    if token.endswith(":*"):
        return None

    candidate = token.rsplit(":", 1)[-1]
    if candidate.startswith("[") and candidate.endswith("]"):
        candidate = candidate[1:-1]

    if candidate.isdigit():
        return int(candidate)
    return None


def detect_listening_ports() -> set[int]:
    ports: set[int] = set()

    if command_exists("ss"):
        result = run_command(["ss", "-H", "-lntu"], timeout=8)
        if result is not None and result.returncode == 0:
            for line in result.stdout.splitlines():
                fields = line.split()
                if len(fields) < 5:
                    continue
                port = parse_port_token(fields[4])
                if port is not None:
                    ports.add(port)
            if ports:
                return ports

    if command_exists("netstat"):
        result = run_command(["netstat", "-lntu"], timeout=8)
        if result is not None and result.returncode == 0:
            for line in result.stdout.splitlines():
                stripped = line.strip()
                if not stripped.startswith(("tcp", "udp")):
                    continue
                fields = stripped.split()
                if len(fields) < 4:
                    continue
                port = parse_port_token(fields[3])
                if port is not None:
                    ports.add(port)

    return ports


def build_system_info() -> dict[str, Any]:
    os_release = parse_os_release()
    ip_addresses = detect_ip_addresses()
    return {
        "hostname": socket.gethostname(),
        "os_name": os_release.get("PRETTY_NAME") or os_release.get("NAME") or platform.system(),
        "os_id": os_release.get("ID", "unknown"),
        "kernel": platform.release(),
        "init_system": detect_init_system(),
        "package_backend": detect_package_backend(),
        "firewall_backend": detect_firewall_backend(),
        "container_backends": detect_container_backends(),
        "ip_addresses": ip_addresses,
        "primary_ip": ip_addresses[0] if ip_addresses else "unknown",
    }


def normalize_space(value: str) -> str:
    return " ".join(value.split())


def trim_text(value: str, limit: int = 240) -> str:
    compact = normalize_space(value)
    if len(compact) <= limit:
        return compact
    truncated = compact[: max(0, limit - 3)].rstrip()
    if " " in truncated:
        truncated = truncated.rsplit(" ", 1)[0]
    return f"{truncated}..."


def strip_html_fragment(value: str) -> str:
    if not value:
        return ""
    without_tags = re.sub(r"<[^>]+>", " ", value)
    return normalize_space(html.unescape(without_tags))


def parse_external_timestamp(raw_value: str) -> str:
    candidate = (raw_value or "").strip()
    if not candidate:
        return ""

    try:
        parsed = parsedate_to_datetime(candidate)
    except (TypeError, ValueError, IndexError, OverflowError):
        parsed = None

    if parsed is not None:
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc).replace(microsecond=0).isoformat()

    for pattern in ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d"):
        try:
            parsed_fallback = datetime.strptime(candidate, pattern)
        except ValueError:
            continue
        return parsed_fallback.replace(tzinfo=timezone.utc).isoformat()

    return candidate


def fetch_remote_bytes(url: str, timeout: int = 12) -> bytes:
    request = Request(url, headers={"User-Agent": "ServerAM1/1.0 (+local panel)"})
    with urlopen(request, timeout=timeout) as response:
        return response.read()


def xml_local_name(tag: str) -> str:
    return str(tag).rsplit("}", 1)[-1].lower()


def find_feed_text(node: ElementTree.Element, *names: str) -> str:
    accepted = {name.lower() for name in names}
    for child in list(node):
        if xml_local_name(child.tag) not in accepted:
            continue
        return "".join(child.itertext()).strip()
    return ""


def find_feed_link(node: ElementTree.Element) -> str:
    for child in list(node):
        local_name = xml_local_name(child.tag)
        if local_name != "link":
            continue
        href = str(child.attrib.get("href", "")).strip()
        rel = str(child.attrib.get("rel", "alternate")).strip().lower()
        if href and rel in {"", "alternate"}:
            return href
        text_value = "".join(child.itertext()).strip()
        if text_value:
            return text_value
    return ""


def parse_feed_items(raw_feed: str, feed_config: dict[str, Any], limit: int) -> list[dict[str, Any]]:
    root = ElementTree.fromstring(raw_feed)
    channel = root.find("channel")
    item_nodes: list[ElementTree.Element]
    if channel is not None:
        item_nodes = channel.findall("item")
    else:
        item_nodes = [node for node in root.iter() if xml_local_name(node.tag) == "entry"]

    items: list[dict[str, Any]] = []
    for item in item_nodes[:limit]:
        title = normalize_space(find_feed_text(item, "title") or "Sin titulo")
        link = find_feed_link(item)
        summary_raw = find_feed_text(item, "description", "summary", "content", "encoded")
        published_raw = find_feed_text(item, "pubdate", "published", "updated", "date")
        guid = normalize_space(find_feed_text(item, "guid", "id") or link or title)
        items.append(
            {
                "id": f"{feed_config['short_name']}:{guid}",
                "category": str(feed_config["category"]),
                "title": title,
                "summary": trim_text(strip_html_fragment(summary_raw) or title, limit=260),
                "link": link,
                "published_at": parse_external_timestamp(published_raw),
                "source": str(feed_config["short_name"]),
                "source_kind": str(feed_config["kind"]),
                "source_url": str(feed_config["url"]),
            }
        )
    return items


def fetch_security_feed(feed_config: dict[str, Any], per_feed_limit: int) -> list[dict[str, Any]]:
    raw_feed = fetch_remote_bytes(str(feed_config["url"])).decode("utf-8", errors="replace")
    return parse_feed_items(raw_feed, feed_config, per_feed_limit)


def parse_iso_utc(value: Any) -> datetime | None:
    candidate = str(value or "").strip()
    if not candidate:
        return None
    try:
        parsed = datetime.fromisoformat(candidate.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def filter_items_within_days(items: list[dict[str, Any]], key: str, days: int) -> list[dict[str, Any]]:
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    filtered: list[dict[str, Any]] = []
    for item in items:
        parsed = parse_iso_utc(item.get(key))
        if parsed is None:
            continue
        if parsed >= cutoff:
            filtered.append(item)
    return filtered


def build_security_headlines(limit: int = 28, per_feed_limit: int = 12, days: int | None = HOME_BRIEFING_HISTORY_DAYS) -> dict[str, Any]:
    per_source_items: list[tuple[dict[str, Any], list[dict[str, Any]]]] = []
    feed_statuses: list[dict[str, Any]] = []

    with ThreadPoolExecutor(max_workers=len(SECURITY_NEWS_FEEDS) or 1) as executor:
        future_map = {
            executor.submit(fetch_security_feed, feed_config, per_feed_limit): feed_config
            for feed_config in SECURITY_NEWS_FEEDS
        }
        for future in as_completed(future_map):
            feed_config = future_map[future]
            try:
                items = future.result()
                if days is not None:
                    items = filter_items_within_days(items, "published_at", days)
                per_source_items.append((feed_config, items))
                feed_statuses.append(
                    {
                        "name": str(feed_config["name"]),
                        "label": str(feed_config["short_name"]),
                        "url": str(feed_config["url"]),
                        "status": "ok",
                        "count": len(items),
                    }
                )
            except (ElementTree.ParseError, HTTPError, URLError, OSError, ValueError) as error:
                feed_statuses.append(
                    {
                        "name": str(feed_config["name"]),
                        "label": str(feed_config["short_name"]),
                        "url": str(feed_config["url"]),
                        "status": "error",
                        "count": 0,
                        "detail": str(error),
                    }
                )

    per_source_items.sort(key=lambda item: int(item[0].get("priority", 99)))
    selected: list[dict[str, Any]] = []

    for round_index in range(per_feed_limit):
        for _, items in per_source_items:
            if len(selected) >= limit:
                break
            if round_index < len(items):
                selected.append(items[round_index])
        if len(selected) >= limit:
            break

    ordered = sorted(
        selected,
        key=lambda entry: (str(entry.get("published_at") or ""), str(entry.get("id") or "")),
        reverse=True,
    )[:limit]
    failing = [feed.get("label", "feed") for feed in feed_statuses if feed.get("status") != "ok"]
    return {
        "source": {
            "name": "Security blogs and sites",
            "status": "ok" if ordered else "error",
            "detail": f"Feeds degradados: {', '.join(failing[:3])}" if failing else "",
        },
        "feeds": feed_statuses,
        "items": ordered,
    }


def build_kev_snapshot(limit: int = 28, days: int | None = HOME_BRIEFING_HISTORY_DAYS) -> dict[str, Any]:
    payload = json.loads(fetch_remote_bytes(CISA_KEV_FEED_URL).decode("utf-8", errors="replace"))
    vulnerabilities = payload.get("vulnerabilities") or []
    ordered = sorted(vulnerabilities, key=lambda entry: str(entry.get("dateAdded", "")), reverse=True)
    items: list[dict[str, Any]] = []
    for entry in ordered:
        cve_id = str(entry.get("cveID", "")).strip()
        title = normalize_space(str(entry.get("vulnerabilityName") or cve_id or "Vulnerabilidad sin identificar"))
        vendor = normalize_space(str(entry.get("vendorProject", "")))
        product = normalize_space(str(entry.get("product", "")))
        items.append(
            {
                "id": cve_id or title,
                "cve_id": cve_id,
                "title": title,
                "vendor": vendor,
                "product": product,
                "summary": trim_text(str(entry.get("shortDescription", "")), limit=260),
                "published_at": parse_external_timestamp(str(entry.get("dateAdded", ""))),
                "due_at": parse_external_timestamp(str(entry.get("dueDate", ""))),
                "required_action": trim_text(str(entry.get("requiredAction", "")), limit=260),
                "ransomware_use": str(entry.get("knownRansomwareCampaignUse", "Unknown")),
                "link": f"https://www.cve.org/CVERecord?id={cve_id}" if cve_id else "",
            }
        )

    if days is not None:
        items = filter_items_within_days(items, "published_at", days)
    items = items[:limit]

    return {
        "source": {"name": "CISA KEV Catalog", "url": CISA_KEV_FEED_URL, "status": "ok"},
        "catalog_version": str(payload.get("catalogVersion", "desconocida")),
        "released_at": parse_external_timestamp(str(payload.get("dateReleased", ""))),
        "count": int(payload.get("count", len(vulnerabilities) or 0)),
        "items": items,
    }


def last_numeric_values(values: list[Any], count: int = 2) -> list[float]:
    collected = [float(value) for value in values if isinstance(value, (int, float))]
    return collected[-count:]


def build_market_entry(config: dict[str, Any]) -> dict[str, Any]:
    encoded_symbol = quote(str(config["symbol"]), safe="")
    payload = json.loads(fetch_remote_bytes(YAHOO_CHART_URL.format(symbol=encoded_symbol)).decode("utf-8", errors="replace"))
    result = ((payload.get("chart") or {}).get("result") or [None])[0]
    if not isinstance(result, dict):
        raise ValueError("missing chart result")

    meta = result.get("meta") or {}
    quotes = (((result.get("indicators") or {}).get("quote") or [{}])[0]).get("close") or []
    recent_values = last_numeric_values(quotes, count=2)
    current = recent_values[-1] if recent_values else float(meta.get("regularMarketPrice") or 0.0)
    previous = recent_values[-2] if len(recent_values) >= 2 else float(meta.get("chartPreviousClose") or meta.get("previousClose") or current)
    if not current:
        raise ValueError("missing market price")

    change = current - previous
    change_percent = (change / previous * 100) if previous else 0.0
    precision = int(config.get("precision", 2))
    prefix = str(config.get("prefix", ""))
    suffix = str(config.get("suffix", ""))
    return {
        "symbol": str(config["symbol"]),
        "label": str(config["label"]),
        "kind": str(config["kind"]),
        "value": f"{prefix}{current:,.{precision}f}{suffix}",
        "raw_value": round(current, precision + 2),
        "change": round(change, precision + 2),
        "change_percent": round(change_percent, 2),
        "trend": "up" if change > 0 else "down" if change < 0 else "flat",
        "market_state": str(meta.get("marketState", "unknown")).lower(),
        "source": normalize_space(str(meta.get("fullExchangeName") or meta.get("exchangeName") or "Yahoo Finance")),
        "currency": normalize_space(str(meta.get("currency", ""))),
        "as_of": parse_external_timestamp(str(meta.get("regularMarketTime", ""))),
    }


def build_market_snapshot() -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    failures: list[str] = []

    with ThreadPoolExecutor(max_workers=len(MARKET_SYMBOLS) or 1) as executor:
        future_map = {
            executor.submit(build_market_entry, config): config
            for config in MARKET_SYMBOLS
        }
        for future in as_completed(future_map):
            config = future_map[future]
            try:
                entries.append(future.result())
            except (KeyError, TypeError, ValueError, json.JSONDecodeError, HTTPError, URLError, OSError) as error:
                failures.append(f"{config['symbol']}: {error}")

    entries.sort(key=lambda entry: next((index for index, item in enumerate(MARKET_SYMBOLS) if item["symbol"] == entry["symbol"]), len(MARKET_SYMBOLS)))

    return {
        "source": {
            "name": "Yahoo Finance Chart API",
            "url": "https://query1.finance.yahoo.com/",
            "status": "ok" if entries else "error",
            "detail": "; ".join(failures[:3]) if failures else "",
        },
        "items": entries,
    }


def build_home_briefing_payload() -> dict[str, Any]:
    generated_at = now_iso()
    sources: dict[str, Any] = {}

    with ThreadPoolExecutor(max_workers=3) as executor:
        headlines_future = executor.submit(build_security_headlines, 28, 12, None)
        kev_future = executor.submit(build_kev_snapshot, 28, None)
        market_future = executor.submit(build_market_snapshot)

        try:
            headlines = headlines_future.result()
        except (ElementTree.ParseError, json.JSONDecodeError, HTTPError, URLError, OSError, ValueError) as error:
            headlines = {
                "source": {"name": "Security blogs and sites", "status": "error", "detail": str(error)},
                "feeds": [],
                "items": [],
            }
        sources["headlines"] = headlines["source"]

        try:
            kev_snapshot = kev_future.result()
        except (json.JSONDecodeError, HTTPError, URLError, OSError, ValueError) as error:
            kev_snapshot = {
                "source": {"name": "CISA KEV Catalog", "url": CISA_KEV_FEED_URL, "status": "error", "detail": str(error)},
                "catalog_version": "desconocida",
                "released_at": "",
                "count": 0,
                "items": [],
            }
        sources["kev"] = kev_snapshot["source"]

        market_snapshot = market_future.result()
        sources["market"] = market_snapshot["source"]

    headline_items = headlines.get("items", [])
    vulnerability_items = kev_snapshot.get("items", [])
    headline_history_items = filter_items_within_days(headline_items, "published_at", HOME_BRIEFING_HISTORY_DAYS)
    vulnerability_history_items = filter_items_within_days(vulnerability_items, "published_at", HOME_BRIEFING_HISTORY_DAYS)

    return {
        "generated_at": generated_at,
        "cache_ttl_seconds": HOME_BRIEFING_CACHE_TTL,
        "sources": sources,
        "security": {
            "headlines": headline_items,
            "headlines_7d": headline_history_items,
            "headline_sources": headlines.get("feeds", []),
            "vulnerabilities": vulnerability_items,
            "vulnerabilities_7d": vulnerability_history_items,
            "catalog_version": kev_snapshot.get("catalog_version", "desconocida"),
            "catalog_count": kev_snapshot.get("count", 0),
            "catalog_released_at": kev_snapshot.get("released_at", ""),
            "history_window_days": HOME_BRIEFING_HISTORY_DAYS,
            "visible_window_days": HOME_BRIEFING_VISIBLE_DAYS,
        },
        "market": {
            "tickers": market_snapshot.get("items", []),
        },
    }


def home_briefing_has_content(payload: dict[str, Any]) -> bool:
    security = payload.get("security") or {}
    market = payload.get("market") or {}
    return any(
        (
            security.get("headlines"),
            security.get("vulnerabilities"),
            market.get("tickers"),
        )
    )


def load_persisted_home_briefing() -> dict[str, Any] | None:
    payload = read_json_file(HOME_BRIEFING_CACHE_FILE)
    if not payload or not home_briefing_has_content(payload):
        return None
    payload["stale"] = True
    payload["stale_reason"] = "persisted-cache"
    return payload


def save_persisted_home_briefing(payload: dict[str, Any]) -> None:
    if not home_briefing_has_content(payload):
        return
    persisted_payload = dict(payload)
    persisted_payload.pop("stale", None)
    persisted_payload.pop("stale_reason", None)
    write_json_file(HOME_BRIEFING_CACHE_FILE, persisted_payload)


def get_home_briefing_payload() -> dict[str, Any]:
    now_epoch = time.time()
    with HOME_BRIEFING_LOCK:
        cached_payload = HOME_BRIEFING_CACHE.get("payload")
        expires_at = float(HOME_BRIEFING_CACHE.get("expires_at") or 0.0)
        if cached_payload and now_epoch < expires_at:
            return cached_payload

    payload = build_home_briefing_payload()
    if not home_briefing_has_content(payload):
        persisted_payload = load_persisted_home_briefing()
        if persisted_payload:
            with HOME_BRIEFING_LOCK:
                HOME_BRIEFING_CACHE["payload"] = persisted_payload
                HOME_BRIEFING_CACHE["expires_at"] = now_epoch + min(HOME_BRIEFING_CACHE_TTL, 120)
            return persisted_payload

    save_persisted_home_briefing(payload)
    with HOME_BRIEFING_LOCK:
        HOME_BRIEFING_CACHE["payload"] = payload
        HOME_BRIEFING_CACHE["expires_at"] = now_epoch + HOME_BRIEFING_CACHE_TTL
    return payload


def parse_properties(output: str) -> dict[str, str]:
    properties: dict[str, str] = {}
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        properties[key] = value
    return properties


def service_status_label(active_state: str) -> str:
    lowered = active_state.lower()
    if lowered in {"active", "running", "started"}:
        return "running"
    if lowered in {"activating", "reloading"}:
        return "transition"
    if lowered in {"inactive", "dead", "stopped", "exited"}:
        return "stopped"
    if lowered in {"failed", "crashed"}:
        return "failed"
    return "unknown"


def build_member_status(source_name: str, status: str, enabled: str, detail: str, actions: list[str]) -> dict[str, Any]:
    return {
        "source_name": source_name,
        "status": status,
        "enabled": enabled,
        "detail": detail,
        "actions": actions,
    }


def query_systemd_service(candidate: str) -> dict[str, Any] | None:
    source_name = candidate if "." in candidate else f"{candidate}.service"
    result = run_command(
        [
            "systemctl",
            "show",
            source_name,
            "--property=LoadState",
            "--property=ActiveState",
            "--property=UnitFileState",
            "--no-pager",
        ],
        timeout=8,
    )
    if result is None:
        return None

    properties = parse_properties(result.stdout)
    load_state = properties.get("LoadState", "unknown")
    if load_state == "not-found":
        return None

    active_state = properties.get("ActiveState", "unknown")
    unit_file_state = properties.get("UnitFileState", "unknown")
    return build_member_status(
        source_name=source_name,
        status=service_status_label(active_state),
        enabled=unit_file_state,
        detail=f"systemd active={active_state} enabled={unit_file_state}",
        actions=list(SERVICE_ACTIONS),
    )


def query_openrc_service(candidate: str) -> dict[str, Any] | None:
    if not command_exists("rc-service"):
        return None
    result = run_command(["rc-service", candidate, "status"], timeout=8)
    if result is None:
        return None
    combined = f"{result.stdout}\n{result.stderr}".lower()
    if "does not exist" in combined or "not found" in combined:
        return None

    enabled = "unknown"
    if command_exists("rc-update"):
        enabled_result = run_command(["rc-update", "show"], timeout=8)
        if enabled_result is not None and candidate in enabled_result.stdout:
            enabled = "enabled"
        elif enabled_result is not None:
            enabled = "disabled"

    return build_member_status(
        source_name=candidate,
        status="running" if result.returncode == 0 else "stopped",
        enabled=enabled,
        detail=(result.stdout or result.stderr).strip() or "openrc status unavailable",
        actions=list(SERVICE_ACTIONS),
    )


def query_runit_service(candidate: str) -> dict[str, Any] | None:
    if not command_exists("sv"):
        return None
    result = run_command(["sv", "status", candidate], timeout=8)
    if result is None:
        return None
    output = f"{result.stdout}\n{result.stderr}".strip()
    lowered = output.lower()
    if "no such file" in lowered or "unable to control" in lowered:
        return None

    status = "running" if lowered.startswith("run:") else "stopped"
    return build_member_status(
        source_name=candidate,
        status=status,
        enabled="unknown",
        detail=output or "runit status unavailable",
        actions=list(SERVICE_ACTIONS),
    )


def query_sysv_service(candidate: str) -> dict[str, Any] | None:
    if not command_exists("service"):
        return None
    result = run_command(["service", candidate, "status"], timeout=8)
    if result is None:
        return None
    output = f"{result.stdout}\n{result.stderr}".strip()
    lowered = output.lower()
    if "unrecognized service" in lowered or "not found" in lowered:
        return None

    status = "running" if result.returncode == 0 else "stopped"
    return build_member_status(
        source_name=candidate,
        status=status,
        enabled="unknown",
        detail=output or "sysv status unavailable",
        actions=list(SERVICE_ACTIONS),
    )


def query_s6_service(candidate: str) -> dict[str, Any] | None:
    if not command_exists("s6-rc"):
        return None
    all_services = run_command(["s6-rc", "-a", "list"], timeout=8)
    if all_services is None or candidate not in all_services.stdout.splitlines():
        return None
    live_services = run_command(["s6-rc", "-a", "list", "live"], timeout=8)
    live_entries = set(live_services.stdout.splitlines()) if live_services is not None else set()
    return build_member_status(
        source_name=candidate,
        status="running" if candidate in live_entries else "stopped",
        enabled="unknown",
        detail="s6 service state derived from live set",
        actions=[],
    )


def query_service_member(init_system: str, candidate: str) -> dict[str, Any] | None:
    if init_system == "systemd":
        return query_systemd_service(candidate)
    if init_system == "openrc":
        return query_openrc_service(candidate)
    if init_system == "runit":
        return query_runit_service(candidate)
    if init_system == "s6":
        return query_s6_service(candidate)
    if init_system == "sysvinit":
        return query_sysv_service(candidate)
    return None


def query_first_service_member(init_system: str, candidates: list[str]) -> dict[str, Any] | None:
    for candidate in candidates:
        member = query_service_member(init_system, candidate)
        if member is not None:
            return member
    return None


def aggregate_members(members: list[dict[str, Any]]) -> tuple[str, str, list[str]]:
    if not members:
        return "not-installed", "unknown", []

    statuses = {member["status"] for member in members}
    enabled_values = [member["enabled"] for member in members if member.get("enabled") and member["enabled"] != "unknown"]
    actions = sorted({action for member in members for action in member.get("actions", [])})

    if statuses == {"running"}:
        return "running", enabled_values[0] if enabled_values else "unknown", actions
    if "running" in statuses:
        return "degraded", enabled_values[0] if enabled_values else "unknown", actions
    if "failed" in statuses:
        return "failed", enabled_values[0] if enabled_values else "unknown", actions
    if statuses == {"stopped"}:
        return "stopped", enabled_values[0] if enabled_values else "unknown", actions
    return next(iter(statuses)), enabled_values[0] if enabled_values else "unknown", actions


def detect_sftp_capability() -> dict[str, str]:
    config_paths = [Path("/etc/ssh/sshd_config")]
    config_dir = Path("/etc/ssh/sshd_config.d")
    if config_dir.is_dir():
        config_paths.extend(sorted(config_dir.glob("*.conf")))

    if not any(path.is_file() for path in config_paths):
        return {"status": "unknown", "detail": "No se encontro configuracion sshd para verificar SFTP."}

    for file_path in config_paths:
        if not file_path.is_file():
            continue
        for raw_line in file_path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            lowered = line.lower()
            if lowered.startswith("subsystem") and "sftp" in lowered:
                return {"status": "enabled", "detail": f"SFTP declarado en {file_path}"}
    return {"status": "disabled", "detail": "No se detecto una directiva Subsystem sftp en la configuracion analizada."}


def detect_docker_socket_capability() -> dict[str, Any]:
    effective_uid = os.geteuid()
    effective_gid = os.getegid()
    effective_groups = set(os.getgroups())
    effective_groups.add(effective_gid)
    try:
        current_user = pwd.getpwuid(effective_uid).pw_name
    except KeyError:
        current_user = str(effective_uid)

    for file_path in (Path("/var/run/docker.sock"), Path("/run/docker.sock")):
        try:
            file_stat = file_path.stat()
        except OSError:
            continue

        if stat.S_ISSOCK(file_stat.st_mode):
            writable = "si" if os.access(file_path, os.W_OK) else "no"
            readable = "si" if os.access(file_path, os.R_OK) else "no"
            try:
                owner = pwd.getpwuid(file_stat.st_uid).pw_name
            except KeyError:
                owner = str(file_stat.st_uid)
            try:
                group = grp.getgrgid(file_stat.st_gid).gr_name
            except KeyError:
                group = str(file_stat.st_gid)
            mode = stat.S_IMODE(file_stat.st_mode)
            group_member = "si" if file_stat.st_gid in effective_groups else "no"
            return {
                "status": "available",
                "detail": f"Socket detectado en {file_path} (owner={owner}, group={group}, mode={mode:04o}, usuario_panel={current_user}, grupo_socket={group_member}, read={readable}, write={writable}).",
                "meta": {
                    "path": str(file_path),
                    "owner": owner,
                    "group": group,
                    "mode": f"{mode:04o}",
                    "panel_user": current_user,
                    "panel_group_member": group_member,
                    "panel_read": readable,
                    "panel_write": writable,
                },
            }

    return {
        "status": "missing",
        "detail": "No se detecto docker.sock en /var/run o /run.",
    }


def detect_docker_cli_capability() -> dict[str, Any]:
    if not command_exists("docker"):
        return {
            "status": "missing",
            "detail": "El binario docker no esta disponible en PATH.",
        }

    result = run_command(
        [
            "docker",
            "info",
            "--format",
            "{{.ServerVersion}}|{{.ContainersRunning}}|{{.ContainersPaused}}|{{.ContainersStopped}}|{{.Driver}}",
        ],
        timeout=8,
    )
    if result is None:
        return {
            "status": "unknown",
            "detail": "No fue posible ejecutar docker info dentro del tiempo esperado.",
        }

    output = result.stdout.strip()
    error_output = result.stderr.strip()
    if result.returncode != 0:
        detail = error_output or output or "docker info devolvio un error sin detalle adicional."
        status = "denied" if "permission denied" in detail.lower() else "unavailable"
        return {
            "status": status,
            "detail": f"El cliente Docker no pudo consultar el daemon: {detail}",
        }

    server_version, running, paused, stopped, driver = (output.split("|", 4) + ["", "", "", "", ""])[:5]
    return {
        "status": "available",
        "detail": f"El cliente Docker puede consultar el daemon (server={server_version or 'desconocido'}, driver={driver or 'desconocido'}).",
        "meta": {
            "server_version": server_version or "desconocido",
            "containers_running": running or "0",
            "containers_paused": paused or "0",
            "containers_stopped": stopped or "0",
            "driver": driver or "desconocido",
        },
    }


def tail_text_file(file_path: Path, line_limit: int = 40) -> str:
    if not file_path.is_file():
        return ""
    lines = file_path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(lines[-line_limit:])


def build_service_item(
    service_id: str,
    title: str,
    kind: str,
    members: list[dict[str, Any]],
    *,
    backend: str = "",
    detail: str = "",
    capabilities: dict[str, Any] | None = None,
    ports: list[int] | None = None,
    listening_ports: list[int] | None = None,
) -> dict[str, Any]:
    status, enabled, actions = aggregate_members(members)
    if not detail:
        detail = "; ".join(member["detail"] for member in members if member.get("detail")) or "Sin detalle adicional."
    return {
        "id": service_id,
        "title": title,
        "kind": kind,
        "backend": backend,
        "status": status,
        "enabled": enabled,
        "detail": detail,
        "source_name": ", ".join(member["source_name"] for member in members) if members else "",
        "actions": actions,
        "members": members,
        "capabilities": capabilities or {},
        "ports": ports or [],
        "listening_ports": listening_ports or [],
        "last_check": now_iso(),
    }
def ssh_service_snapshot(init_system: str, all_listening_ports: set[int] | None = None) -> dict[str, Any]:
    member = query_first_service_member(init_system, ["ssh", "sshd"])
    members = [member] if member else []
    expected_ports = [22]
    listening_source = all_listening_ports if all_listening_ports is not None else detect_listening_ports()
    listening_ports = sorted(listening_source.intersection(expected_ports))
    return build_service_item(
        "ssh",
        "SSH",
        "service",
        members,
        detail="Servicio de acceso remoto por SSH.",
        capabilities={"sftp": detect_sftp_capability()},
        ports=expected_ports,
        listening_ports=listening_ports,
    )


def samba_service_snapshot(init_system: str, all_listening_ports: set[int] | None = None) -> dict[str, Any]:
    members: list[dict[str, Any]] = []
    for candidate in ["smbd", "nmbd", "samba", "smb"]:
        member = query_service_member(init_system, candidate)
        if member is not None:
            members.append(member)
    expected_ports = [139, 445]
    listening_source = all_listening_ports if all_listening_ports is not None else detect_listening_ports()
    listening_ports = sorted(listening_source.intersection(expected_ports))
    return build_service_item(
        "samba",
        "Samba",
        "service",
        members,
        detail="Servicios SMB y descubrimiento NetBIOS agrupados.",
        ports=expected_ports,
        listening_ports=listening_ports,
    )


def docker_service_snapshot(init_system: str, all_listening_ports: set[int] | None = None) -> dict[str, Any]:
    member = query_first_service_member(init_system, ["docker"])
    members = [member] if member else []
    expected_ports = [2375, 2376]
    listening_source = all_listening_ports if all_listening_ports is not None else detect_listening_ports()
    listening_ports = sorted(listening_source.intersection(expected_ports))
    return build_service_item(
        "docker",
        "Docker",
        "service",
        members,
        detail="Daemon de contenedores Docker.",
        capabilities={
            "docker_socket": detect_docker_socket_capability(),
            "docker_cli": detect_docker_cli_capability(),
        },
        ports=expected_ports,
        listening_ports=listening_ports,
    )


def firewall_runtime_snapshot(firewall_backend: str) -> dict[str, str]:
    if firewall_backend == "ufw":
        result = run_command(["ufw", "status"], timeout=8)
        output = result.stdout.strip() if result is not None else ""
        if result is None:
            return {"status": "unknown", "detail": "No fue posible consultar ufw."}
        return {
            "status": "running" if "Status: active" in output else "stopped",
            "detail": output or "ufw status sin salida",
        }
    if firewall_backend == "firewalld":
        result = run_command(["firewall-cmd", "--state"], timeout=8)
        output = (result.stdout or result.stderr).strip() if result is not None else ""
        if result is None:
            return {"status": "unknown", "detail": "No fue posible consultar firewalld."}
        return {
            "status": "running" if result.returncode == 0 and "running" in output else "stopped",
            "detail": output or "firewalld sin salida",
        }
    if firewall_backend == "nftables":
        result = run_command(["nft", "list", "ruleset"], timeout=8)
        if result is None:
            return {"status": "unknown", "detail": "No fue posible consultar nftables."}
        output = result.stdout.strip()
        return {
            "status": "running" if result.returncode == 0 and output else "stopped",
            "detail": output[:600] or (result.stderr.strip() if result.stderr else "Sin reglas activas detectadas."),
        }
    if firewall_backend == "iptables":
        result = run_command(["iptables", "-S"], timeout=8)
        if result is None:
            return {"status": "unknown", "detail": "No fue posible consultar iptables."}
        rules = [line for line in result.stdout.splitlines() if line.startswith("-A ")]
        return {
            "status": "running" if result.returncode == 0 and bool(rules) else "stopped",
            "detail": result.stdout.strip()[:600] or (result.stderr.strip() if result.stderr else "Sin reglas activas detectadas."),
        }
    return {"status": "not-installed", "detail": "No se detecto un backend de firewall administrado."}


def firewall_service_snapshot(init_system: str, firewall_backend: str) -> dict[str, Any]:
    candidates_map = {
        "ufw": ["ufw"],
        "firewalld": ["firewalld"],
        "nftables": ["nftables", "netfilter-persistent"],
        "iptables": ["iptables", "netfilter-persistent"],
    }
    members: list[dict[str, Any]] = []
    for candidate in candidates_map.get(firewall_backend, []):
        member = query_service_member(init_system, candidate)
        if member is not None:
            members.append(member)

    runtime = firewall_runtime_snapshot(firewall_backend)
    item = build_service_item(
        "firewall",
        "Firewall",
        "firewall",
        members,
        backend=firewall_backend,
        detail=runtime["detail"],
        listening_ports=[],
    )
    if item["status"] in {"not-installed", "unknown"}:
        item["status"] = runtime["status"]
    elif item["status"] == "stopped" and runtime["status"] == "running":
        item["status"] = "running"
    if not item["actions"] and firewall_backend == "ufw":
        item["actions"] = list(SERVICE_ACTIONS)
    return item


def collect_services_status() -> dict[str, Any]:
    system_info = build_system_info()
    init_system = system_info["init_system"]
    firewall_backend = system_info["firewall_backend"]
    listening_ports = detect_listening_ports()
    services = [
        ssh_service_snapshot(init_system, listening_ports),
        samba_service_snapshot(init_system, listening_ports),
        docker_service_snapshot(init_system, listening_ports),
        firewall_service_snapshot(init_system, firewall_backend),
    ]
    return {
        "system": system_info,
        "listening_ports": sorted(listening_ports),
        "services": services,
        "updated_at": now_iso(),
    }


def resolve_service_targets(service_id: str) -> tuple[str, list[str], str]:
    system_info = build_system_info()
    init_system = system_info["init_system"]
    firewall_backend = system_info["firewall_backend"]

    if service_id == "ssh":
        service_item = ssh_service_snapshot(init_system)
    elif service_id == "samba":
        service_item = samba_service_snapshot(init_system)
    elif service_id == "docker":
        service_item = docker_service_snapshot(init_system)
    elif service_id == "firewall":
        service_item = firewall_service_snapshot(init_system, firewall_backend)
    else:
        raise ValueError("unknown service id")

    source_names = [member["source_name"] for member in service_item.get("members", []) if member.get("source_name")]
    return init_system, source_names, firewall_backend


def execute_service_action(service_id: str, action: str) -> dict[str, Any]:
    if action not in SERVICE_ACTIONS:
        raise ValueError("invalid action")

    init_system, source_names, firewall_backend = resolve_service_targets(service_id)

    if service_id == "firewall" and firewall_backend == "ufw":
        command_map = {
            "start": ["ufw", "--force", "enable"],
            "stop": ["ufw", "--force", "disable"],
            "restart": ["ufw", "reload"],
        }
        command = command_map[action]
        result = run_command(command, timeout=30)
        if result is None:
            raise ValueError("could not execute firewall action")
        return {
            "service_id": service_id,
            "action": action,
            "command": command,
            "exit_code": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "status": "completed" if result.returncode == 0 else "failed",
        }

    if not source_names:
        raise ValueError("service targets unavailable on this host")

    if init_system == "systemd":
        command = ["systemctl", action, *source_names]
        result = run_command(command, timeout=30)
    elif init_system == "openrc":
        target = source_names[0]
        command = ["rc-service", target, action]
        result = run_command(command, timeout=30)
    elif init_system == "runit":
        target = source_names[0]
        subcommand = {"start": "up", "stop": "down", "restart": "restart"}[action]
        command = ["sv", subcommand, target]
        result = run_command(command, timeout=30)
    elif init_system == "sysvinit":
        target = source_names[0]
        command = ["service", target, action]
        result = run_command(command, timeout=30)
    else:
        raise ValueError("service actions are not supported for this init system")

    if result is None:
        raise ValueError("could not execute service action")

    return {
        "service_id": service_id,
        "action": action,
        "command": command,
        "exit_code": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "status": "completed" if result.returncode == 0 else "failed",
    }


def collect_service_logs(service_id: str, line_limit: int = 40) -> dict[str, Any]:
    init_system, source_names, firewall_backend = resolve_service_targets(service_id)

    if command_exists("journalctl") and source_names:
        command = ["journalctl"]
        for source_name in source_names:
            command.extend(["-u", source_name])
        command.extend(["-n", str(line_limit), "--no-pager", "--output=short-iso"])
        result = run_command(command, timeout=20)
        if result is not None:
            return {
                "service_id": service_id,
                "status": "ok" if result.returncode == 0 else "limited",
                "source": "journalctl",
                "command": command,
                "content": (result.stdout or result.stderr or "Sin logs disponibles.").strip(),
            }

    if service_id == "firewall" and firewall_backend == "ufw":
        ufw_log = Path("/var/log/ufw.log")
        content = tail_text_file(ufw_log, line_limit=line_limit)
        if content:
            return {
                "service_id": service_id,
                "status": "ok",
                "source": str(ufw_log),
                "command": ["tail", "-n", str(line_limit), str(ufw_log)],
                "content": content,
            }

    return {
        "service_id": service_id,
        "status": "unsupported",
        "source": init_system,
        "command": [],
        "content": "No hay una ruta uniforme de logs para este servicio o backend en el host actual.",
    }


@dataclass
class JobRecord:
    job_id: str
    name: str
    command: list[str]
    started_at: str
    status: str = "running"
    exit_code: int | None = None
    finished_at: str | None = None
    report_dir: str | None = None
    lines: list[str] = field(default_factory=list)

    def append_line(self, line: str) -> None:
        self.lines.append(line)
        if len(self.lines) > MAX_LOG_LINES:
            self.lines = self.lines[-MAX_LOG_LINES:]
        if line.startswith("snapshot_dir=") or line.startswith("report_dir="):
            _, value = line.split("=", 1)
            self.report_dir = value.strip()

    def to_dict(self) -> dict[str, Any]:
        return {
            "job_id": self.job_id,
            "name": self.name,
            "command": self.command,
            "started_at": self.started_at,
            "status": self.status,
            "exit_code": self.exit_code,
            "finished_at": self.finished_at,
            "report_dir": self.report_dir,
            "log": "\n".join(self.lines),
        }


class JobRegistry:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._jobs: dict[str, JobRecord] = {}

    def list_jobs(self) -> list[dict[str, Any]]:
        with self._lock:
            jobs = [job.to_dict() for job in self._jobs.values()]
        jobs.sort(key=lambda item: item["started_at"], reverse=True)
        return jobs

    def create_job(self, name: str, command: list[str]) -> JobRecord:
        job = JobRecord(
            job_id=uuid.uuid4().hex,
            name=name,
            command=command,
            started_at=now_iso(),
        )
        with self._lock:
            self._jobs[job.job_id] = job
        return job

    def append_output(self, job_id: str, line: str) -> None:
        with self._lock:
            self._jobs[job_id].append_line(line)

    def finalize(self, job_id: str, exit_code: int) -> None:
        with self._lock:
            job = self._jobs[job_id]
            job.exit_code = exit_code
            job.status = "completed" if exit_code == 0 else "failed"
            job.finished_at = now_iso()


JOBS = JobRegistry()


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def relative_files(report_dir: Path) -> list[dict[str, Any]]:
    files: list[dict[str, Any]] = []
    if not report_dir.is_dir():
        return files

    for file_path in sorted(report_dir.rglob("*")):
        if not file_path.is_file():
            continue
        suffix = file_path.suffix.lower()
        files.append(
            {
                "path": file_path.relative_to(report_dir).as_posix(),
                "size": file_path.stat().st_size,
                "previewable": suffix in {".txt", ".log", ".json", ".tsv", ".md"},
            }
        )
    return files


def inventory_report_item(report_dir: Path) -> dict[str, Any]:
    manifest = parse_key_value_file(report_dir / "manifest.txt")
    collector_status = {
        key.replace("collector_", "", 1): value
        for key, value in manifest.items()
        if key.startswith("collector_")
    }
    return {
        "kind": "inventory",
        "id": report_dir.name,
        "path": str(report_dir),
        "created_at": format_timestamp(safe_stat_mtime(report_dir)),
        "manifest": manifest,
        "collector_status": collector_status,
        "warnings_count": count_warning_lines(report_dir / "warnings.log"),
        "files": relative_files(report_dir),
    }


def update_report_item(report_dir: Path) -> dict[str, Any]:
    manifest = parse_key_value_file(report_dir / "manifest.txt")
    summary = parse_key_value_file(report_dir / "summary.txt")
    report_json = read_json_file(report_dir / "report.json")
    trust = report_json.get("trust", {}) if isinstance(report_json, dict) else {}
    security = report_json.get("security", {}) if isinstance(report_json, dict) else {}
    return {
        "kind": "update",
        "id": report_dir.name,
        "path": str(report_dir),
        "created_at": format_timestamp(safe_stat_mtime(report_dir)),
        "manifest": manifest,
        "summary": summary,
        "trust": {
            "status": trust.get("status", manifest.get("trust_status", "unknown")),
            "review_sources": trust.get("review_sources", []),
            "allowed_sources": trust.get("allowed_sources", []),
            "official_sources": trust.get("official_sources", []),
            "official_count": trust.get("official_count", 0),
            "allowed_count": trust.get("allowed_count", 0),
            "review_count": trust.get("review_count", 0),
        },
        "security": {
            "backend": security.get("backend", "unknown"),
            "sections": security.get("sections", {}),
        },
        "files": relative_files(report_dir),
    }


def list_reports(base_dir: Path, builder: Any, limit: int = 12) -> list[dict[str, Any]]:
    if not base_dir.is_dir():
        return []

    report_dirs = [path for path in base_dir.iterdir() if path.is_dir()]
    report_dirs.sort(key=safe_stat_mtime, reverse=True)
    return [builder(path) for path in report_dirs[:limit]]


def resolve_report_dir(kind: str, report_id: str) -> Path:
    if kind == "inventory":
        base_dir = INVENTORY_DIR
    elif kind == "update":
        base_dir = UPDATE_DIR
    else:
        raise FileNotFoundError("unknown report kind")

    report_dir = (base_dir / report_id).resolve()
    if base_dir.resolve() not in report_dir.parents:
        raise FileNotFoundError("invalid report path")
    if not report_dir.is_dir():
        raise FileNotFoundError("report not found")
    return report_dir


def resolve_report_file(report_dir: Path, relative_path: str) -> Path:
    target_path = (report_dir / relative_path).resolve()
    if report_dir.resolve() not in target_path.parents:
        raise FileNotFoundError("invalid file path")
    if not target_path.is_file():
        raise FileNotFoundError("file not found")
    return target_path


def preview_report_file(file_path: Path) -> dict[str, Any]:
    raw_content = file_path.read_text(encoding="utf-8", errors="replace")
    content = raw_content[:MAX_FILE_PREVIEW]
    return {
        "path": file_path.name,
        "size": file_path.stat().st_size,
        "content": content,
        "truncated": len(raw_content) > len(content),
    }


def guess_download_name(report_dir: Path, file_path: Path) -> str:
    return f"{report_dir.name}_{file_path.relative_to(report_dir).as_posix().replace('/', '_')}"


def launch_job(name: str, command: list[str]) -> dict[str, Any]:
    ensure_dir(INVENTORY_DIR)
    ensure_dir(UPDATE_DIR)
    job = JOBS.create_job(name=name, command=command)
    process = subprocess.Popen(
        command,
        cwd=ROOT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )

    def worker() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            JOBS.append_output(job.job_id, line.rstrip())
        JOBS.finalize(job.job_id, process.wait())

    threading.Thread(target=worker, daemon=True).start()
    return job.to_dict()


class PanelHandler(BaseHTTPRequestHandler):
    server_version = "ServerAM1Panel/1.0"

    def log_message(self, format: str, *args: Any) -> None:
        return

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/system":
            self._send_json(build_system_info())
            return

        if parsed.path == "/api/status":
            self._send_json(
                {
                    "project_root": str(ROOT_DIR),
                    "server_time": now_iso(),
                    "system": build_system_info(),
                    "jobs": JOBS.list_jobs(),
                    "inventory_count": len(list_reports(INVENTORY_DIR, inventory_report_item, limit=200)),
                    "update_count": len(list_reports(UPDATE_DIR, update_report_item, limit=200)),
                }
            )
            return

        if parsed.path == "/api/home-briefing":
            self._send_json(get_home_briefing_payload())
            return

        if parsed.path == "/api/services":
            self._send_json(collect_services_status())
            return

        if parsed.path.startswith("/api/services/") and parsed.path.endswith("/logs"):
            path_parts = [part for part in parsed.path.split("/") if part]
            if len(path_parts) != 4:
                self._send_json({"error": "invalid service log path"}, status=HTTPStatus.BAD_REQUEST)
                return

            service_id = unquote(path_parts[2])
            line_limit = parse_qs(parsed.query).get("lines", ["40"])[0]
            try:
                limit = max(1, min(int(line_limit), 200))
            except ValueError:
                self._send_json({"error": "invalid lines parameter"}, status=HTTPStatus.BAD_REQUEST)
                return

            try:
                self._send_json(collect_service_logs(service_id, line_limit=limit))
            except ValueError as error:
                self._send_json({"error": str(error)}, status=HTTPStatus.BAD_REQUEST)
            return

        if parsed.path == "/api/reports":
            kind = parse_qs(parsed.query).get("kind", ["inventory"])[0]
            if kind == "inventory":
                self._send_json(list_reports(INVENTORY_DIR, inventory_report_item))
            elif kind == "update":
                self._send_json(list_reports(UPDATE_DIR, update_report_item))
            else:
                self._send_json({"error": "invalid report kind"}, status=HTTPStatus.BAD_REQUEST)
            return

        if parsed.path.startswith("/api/reports/"):
            path_parts = [part for part in parsed.path.split("/") if part]
            if len(path_parts) < 4:
                self._send_json({"error": "invalid report path"}, status=HTTPStatus.BAD_REQUEST)
                return

            kind = path_parts[2]
            report_id = unquote(path_parts[3])
            try:
                report_dir = resolve_report_dir(kind, report_id)
            except FileNotFoundError as error:
                self._send_json({"error": str(error)}, status=HTTPStatus.NOT_FOUND)
                return

            if len(path_parts) == 5 and path_parts[4] == "file":
                relative_path = parse_qs(parsed.query).get("path", [""])[0]
                if not relative_path:
                    self._send_json({"error": "missing file path"}, status=HTTPStatus.BAD_REQUEST)
                    return
                try:
                    file_path = resolve_report_file(report_dir, relative_path)
                except FileNotFoundError as error:
                    self._send_json({"error": str(error)}, status=HTTPStatus.NOT_FOUND)
                    return
                self._send_json(preview_report_file(file_path))
                return

            if len(path_parts) == 5 and path_parts[4] == "download":
                relative_path = parse_qs(parsed.query).get("path", [""])[0]
                if not relative_path:
                    self._send_json({"error": "missing file path"}, status=HTTPStatus.BAD_REQUEST)
                    return
                try:
                    file_path = resolve_report_file(report_dir, relative_path)
                except FileNotFoundError as error:
                    self._send_json({"error": str(error)}, status=HTTPStatus.NOT_FOUND)
                    return
                self._send_file(file_path, download_name=guess_download_name(report_dir, file_path))
                return

            if kind == "inventory":
                self._send_json(inventory_report_item(report_dir))
            elif kind == "update":
                self._send_json(update_report_item(report_dir))
            else:
                self._send_json({"error": "invalid report kind"}, status=HTTPStatus.BAD_REQUEST)
            return

        self._serve_static(parsed.path)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        body = self._read_json_body()

        if parsed.path == "/api/jobs/inventory":
            command = ["bash", "scripts/collect_inventory.sh"]
            if bool(body.get("quick")):
                command.append("--quick")
            self._send_json(launch_job("inventory", command), status=HTTPStatus.ACCEPTED)
            return

        if parsed.path == "/api/jobs/update":
            mode = body.get("mode", "check")
            if mode not in {"check", "apply"}:
                self._send_json({"error": "invalid mode"}, status=HTTPStatus.BAD_REQUEST)
                return
            command = ["bash", "scripts/update_packages.sh", f"--{mode}"]
            if bool(body.get("no_refresh")):
                command.append("--no-refresh")
            if bool(body.get("auto_yes")):
                command.append("--yes")
            if bool(body.get("allow_untrusted_sources")):
                command.append("--allow-untrusted-sources")
            self._send_json(launch_job("update", command), status=HTTPStatus.ACCEPTED)
            return

        if parsed.path == "/api/services/action":
            service_id = str(body.get("service_id", "")).strip()
            action = str(body.get("action", "")).strip()
            try:
                result = execute_service_action(service_id, action)
            except ValueError as error:
                self._send_json({"error": str(error)}, status=HTTPStatus.BAD_REQUEST)
                return
            self._send_json(
                {
                    "result": result,
                    "services": collect_services_status(),
                },
                status=HTTPStatus.ACCEPTED,
            )
            return

        self._send_json({"error": "unknown endpoint"}, status=HTTPStatus.NOT_FOUND)

    def _read_json_body(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length == 0:
            return {}
        raw_payload = self.rfile.read(content_length)
        try:
            payload = json.loads(raw_payload.decode("utf-8"))
        except json.JSONDecodeError:
            return {}
        return payload if isinstance(payload, dict) else {}

    def _serve_static(self, path: str) -> None:
        relative_path = "index.html" if path in {"", "/"} else path.lstrip("/")
        target = (STATIC_DIR / relative_path).resolve()
        if STATIC_DIR.resolve() not in target.parents and target != STATIC_DIR.resolve() / "index.html":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        if not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        mime_type, _ = mimetypes.guess_type(str(target))
        payload = target.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime_type or "application/octet-stream")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _send_json(self, payload: Any, status: HTTPStatus = HTTPStatus.OK) -> None:
        raw_payload = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw_payload)))
        self.end_headers()
        self.wfile.write(raw_payload)

    def _send_file(self, file_path: Path, download_name: str) -> None:
        payload = file_path.read_bytes()
        mime_type, _ = mimetypes.guess_type(str(file_path))
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime_type or "application/octet-stream")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Content-Disposition", f'attachment; filename="{download_name}"')
        self.end_headers()
        self.wfile.write(payload)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Execution and monitoring panel for ServerAM1")
    parser.add_argument("--host", default="127.0.0.1", help="Bind address for the local web panel")
    parser.add_argument("--port", type=int, default=8765, help="TCP port for the local web panel")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    ensure_dir(INVENTORY_DIR)
    ensure_dir(UPDATE_DIR)
    httpd = ThreadingHTTPServer((args.host, args.port), PanelHandler)
    print(f"panel_url=http://{args.host}:{args.port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())