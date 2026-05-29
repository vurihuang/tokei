#!/usr/bin/env python3
# <bitbar.title>AI Usage Bar</bitbar.title>
# <bitbar.version>v0.1</bitbar.version>
# <bitbar.author>local</bitbar.author>
# <bitbar.desc>Claude Code + Codex 本地 token / 缓存命中 / 花费 / 额度</bitbar.desc>
# <swiftbar.runInBash>false</swiftbar.runInBash>
#
# 数据全部读自本地会话日志,不联网、不改动任何 CLI:
#   Claude Code: ~/.claude/projects/<proj>/<session>.jsonl  (assistant 行 message.usage,增量)
#   Codex:       ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl (token_count 事件,含额度)

import os
import sys
import glob
import json
from datetime import datetime, timedelta

HOME = os.path.expanduser("~")
CLAUDE_DIR = os.path.join(HOME, ".claude", "projects")
CODEX_DIR = os.path.join(HOME, ".codex", "sessions")

# 每 1M token 美元单价。价格会变,按需自行核对。
# write5m / write1h = 5 分钟 / 1 小时 缓存写入价。
PRICING = {
    "opus":   {"in": 5.0,  "out": 25.0, "cache_read": 0.5,  "write5m": 6.25,  "write1h": 10.0},
    "sonnet": {"in": 3.0,  "out": 15.0, "cache_read": 0.3,  "write5m": 3.75,  "write1h": 6.0},
    "haiku":  {"in": 1.0,  "out": 5.0,  "cache_read": 0.1,  "write5m": 1.25,  "write1h": 2.0},
}


def price_for(model: str):
    m = (model or "").lower()
    for k in PRICING:
        if k in m:
            return PRICING[k]
    return PRICING["opus"]  # 未知模型按 opus 估(偏保守上限)


RANGE_KEYS = ["today", "yesterday", "week", "month"]


def nice_model(m: str) -> str:
    """claude-opus-4-7 → Opus 4.7;<synthetic> → 合成。"""
    if not m or m == "<synthetic>":
        return "合成"
    s = m.lower()
    fam = ("Opus" if "opus" in s else "Sonnet" if "sonnet" in s
           else "Haiku" if "haiku" in s else m)
    import re
    mt = re.search(r"(\d+)-(\d+)", s)
    return f"{fam} {mt.group(1)}.{mt.group(2)}" if mt else fam


def range_bounds():
    """返回今日/昨日/本周(周一起)/本月(1号起)的本地起点。"""
    now = datetime.now().astimezone()
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    yesterday = today - timedelta(days=1)
    week = today - timedelta(days=today.weekday())   # 周一 0
    month = today.replace(day=1)
    return {"today": today, "yesterday": yesterday, "week": week, "month": month}


def classify(dt, b):
    """给定本地化 dt,返回它命中的区间 key 列表(今日同时属本周/本月)。"""
    d = dt.date()
    ks = []
    if d == b["today"].date():
        ks.append("today")
    if d == b["yesterday"].date():
        ks.append("yesterday")
    if dt >= b["week"]:
        ks.append("week")
    if dt >= b["month"]:
        ks.append("month")
    return ks


def parse_ts(s: str):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def human(n: float) -> str:
    n = float(n)
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.0f}K"
    return f"{n:.0f}"


# ---------- Claude Code ----------
def scan_claude(bounds):
    scan_from = min(bounds["yesterday"], bounds["week"], bounds["month"]).timestamp()
    # 各区间分桶累加
    B = {k: {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0, "models": {}} for k in RANGE_KEYS}
    # 当前会话 = 最近修改的 jsonl,累计其整段 usage
    cur_in = cur_out = cur_cr = cur_cw = 0
    cur_file, cur_mtime = None, -1.0

    for f in glob.glob(os.path.join(CLAUDE_DIR, "*", "*.jsonl")):
        try:
            mtime = os.path.getmtime(f)
        except OSError:
            continue
        in_range = mtime >= scan_from
        is_current = mtime > cur_mtime
        if not in_range and not is_current:
            continue
        rows = []
        try:
            with open(f, "r", encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    if '"usage"' not in line:
                        continue
                    rows.append(line)
        except OSError:
            continue

        if is_current:
            ci = co = ccr = ccw = 0
            for line in rows:
                u = _claude_usage(line)
                if not u:
                    continue
                ci += u["in"]; co += u["out"]; ccr += u["cr"]; ccw += u["cw"]
            cur_in, cur_out, cur_cr, cur_cw = ci, co, ccr, ccw
            cur_file, cur_mtime = f, mtime

        if in_range:
            for line in rows:
                u = _claude_usage(line, want_dt=True)
                if not u:
                    continue
                for k in classify(u["dt"], bounds):
                    b = B[k]
                    b["in"] += u["in"]; b["out"] += u["out"]
                    b["cr"] += u["cr"]; b["cw"] += u["cw"]; b["cost"] += u["cost"]
                    mm = b["models"].setdefault(
                        u["model"], {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0})
                    mm["in"] += u["in"]; mm["out"] += u["out"]
                    mm["cr"] += u["cr"]; mm["cw"] += u["cw"]; mm["cost"] += u["cost"]

    return {
        "ranges": B,
        "cur": {"in": cur_in, "out": cur_out, "cr": cur_cr, "cw": cur_cw,
                "name": os.path.basename(cur_file)[:8] if cur_file else "-"},
    }


def _claude_usage(line, want_dt=False):
    try:
        o = json.loads(line)
    except Exception:
        return None
    if o.get("type") != "assistant":
        return None
    dt = None
    if want_dt:
        # timestamp 是 UTC,转本地用于区间归类
        dt = parse_ts(o.get("timestamp", ""))
        if dt is None:
            return None
        dt = dt.astimezone()
    msg = o.get("message", {})
    u = msg.get("usage")
    if not u:
        return None
    inp = u.get("input_tokens", 0) or 0
    out = u.get("output_tokens", 0) or 0
    cr = u.get("cache_read_input_tokens", 0) or 0
    cw = u.get("cache_creation_input_tokens", 0) or 0
    p = price_for(msg.get("model"))
    cc = u.get("cache_creation") or {}
    w5 = cc.get("ephemeral_5m_input_tokens")
    w1 = cc.get("ephemeral_1h_input_tokens")
    if w5 is None and w1 is None:
        write_cost = cw / 1e6 * p["write5m"]
    else:
        write_cost = (w5 or 0) / 1e6 * p["write5m"] + (w1 or 0) / 1e6 * p["write1h"]
    cost = inp / 1e6 * p["in"] + out / 1e6 * p["out"] + cr / 1e6 * p["cache_read"] + write_cost
    res = {"in": inp, "out": out, "cr": cr, "cw": cw, "cost": cost,
           "model": msg.get("model")}
    if want_dt:
        res["dt"] = dt
    return res


# ---------- Codex ----------
def scan_codex(bounds):
    scan_from = min(bounds["yesterday"], bounds["week"], bounds["month"]).timestamp()
    # 各区间分桶累加(用 last_token_usage 增量)
    B = {k: {"in": 0, "cached": 0, "out": 0, "reason": 0, "cost": 0.0} for k in RANGE_KEYS}
    # 主额度只认 limit_id == "codex";其它桶(如 codex_bengalfox / 单模型额度)忽略
    latest_ts = None
    latest_limits = None
    plan_type = None
    # 全局回退:任意 limit_id 的最新一条,仅在没有 "codex" 主额度时才用
    g_ts = None
    g_limits = None
    g_plan = None
    cur_total = None                      # 当前会话累计(total_token_usage 最后一条)
    cur_mtime = -1.0

    # Codex 长会话会跨天:某区间事件常写在更早日期目录的文件里。
    # 所以按"文件 mtime 在扫描窗口内"筛,而非目录日期。
    files = []
    for f in glob.glob(os.path.join(CODEX_DIR, "**", "rollout-*.jsonl"), recursive=True):
        try:
            if os.path.getmtime(f) >= scan_from:
                files.append(f)
        except OSError:
            continue
    files.sort(key=os.path.getmtime)

    for f in files:
        try:
            mtime = os.path.getmtime(f)
        except OSError:
            continue
        is_current = mtime > cur_mtime
        last_total_in_file = None
        try:
            with open(f, "r", encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    if '"token_count"' not in line:
                        continue
                    try:
                        o = json.loads(line)
                    except Exception:
                        continue
                    info = (o.get("payload") or {}).get("info") or {}
                    last = info.get("last_token_usage") or {}
                    total = info.get("total_token_usage") or {}
                    if total:
                        last_total_in_file = total
                    ts = parse_ts(o.get("timestamp", ""))
                    # 今日额度:主额度取 limit_id == "codex" 的最新一条;
                    # 同时记一份全局最新(任意 limit_id)作为无主额度时的回退
                    rl = (o.get("payload") or {}).get("rate_limits")
                    if ts and rl:
                        if g_ts is None or ts > g_ts:
                            g_ts = ts
                            g_limits = rl
                            g_plan = rl.get("plan_type")
                        if rl.get("limit_id") == "codex" and (latest_ts is None or ts > latest_ts):
                            latest_ts = ts
                            latest_limits = rl
                            plan_type = rl.get("plan_type")
                    # 今日 token:last_token_usage 增量,按本地今日过滤
                    if ts and last:
                        ks = classify(ts.astimezone(), bounds)
                        if ks:
                            li = last.get("input_tokens", 0) or 0
                            lc = last.get("cached_input_tokens", 0) or 0
                            lo = last.get("output_tokens", 0) or 0      # 已含 reasoning
                            lr = last.get("reasoning_output_tokens", 0) or 0
                            # 分档:该请求 input_tokens >272K 走高价档
                            hi = li > 272_000
                            p_in = 10.0 if hi else 5.0
                            p_out = 45.0 if hi else 30.0
                            p_cr = 1.0 if hi else 0.5
                            cost = (li - lc) / 1e6 * p_in + lc / 1e6 * p_cr + lo / 1e6 * p_out
                            for k in ks:
                                b = B[k]
                                b["in"] += li; b["cached"] += lc
                                b["out"] += lo; b["reason"] += lr; b["cost"] += cost
        except OSError:
            continue
        if is_current and last_total_in_file is not None:
            cur_total = last_total_in_file
            cur_mtime = mtime

    # 今日有额度事件但没有 "codex" 主额度桶时,回退到今日全局最新一条
    if latest_limits is None and g_limits is not None:
        latest_limits = g_limits
        plan_type = g_plan

    # 今天完全没用 codex 时,回退到全局最新一个会话文件;
    # 同一文件内仍优先 limit_id == "codex" 主额度,无则取最后一条任意桶
    if latest_limits is None:
        allf = glob.glob(os.path.join(CODEX_DIR, "**", "rollout-*.jsonl"), recursive=True)
        if allf:
            newest = max(allf, key=os.path.getmtime)
            fallback_rl = None
            try:
                with open(newest, "r", encoding="utf-8", errors="ignore") as fh:
                    for line in fh:
                        if '"rate_limits"' not in line:
                            continue
                        try:
                            rl = (json.loads(line).get("payload") or {}).get("rate_limits")
                        except Exception:
                            continue
                        if not rl:
                            continue
                        fallback_rl = rl
                        if rl.get("limit_id") == "codex":
                            latest_limits = rl
                            plan_type = rl.get("plan_type")
            except OSError:
                pass
            if latest_limits is None and fallback_rl is not None:
                latest_limits = fallback_rl
                plan_type = fallback_rl.get("plan_type")

    return {
        "ranges": B,
        "cur_total": cur_total,
        "limits": latest_limits,
        "plan": plan_type,
    }


def fmt_reset(epoch):
    try:
        return datetime.fromtimestamp(int(epoch)).astimezone().strftime("%m-%d %H:%M")
    except Exception:
        return "?"


# ---------- Claude 套餐用量(读 Claude Desktop 的 Chromium HTTP 缓存) ----------
# 数据来自桌面应用每 ~10min 轮询 /usage 的响应(zstd 压缩),纯本地只读。
CLAUDE_CACHE = os.path.join(
    HOME, "Library", "Application Support", "Claude", "Cache", "Cache_Data"
)


def _iso_to_epoch(s):
    dt = parse_ts(s) if s else None
    return int(dt.timestamp()) if dt else None


def scan_claude_plan():
    import shutil
    import subprocess
    import tempfile
    if not os.path.isdir(CLAUDE_CACHE) or not shutil.which("zstd"):
        return None
    # 找到缓存了 organizations/<org>/usage 的文件(文件名是 hash,按内容定位)
    cand = None
    for f in glob.glob(os.path.join(CLAUDE_CACHE, "*_0")):
        try:
            data = open(f, "rb").read()
        except OSError:
            continue
        if b"organizations/" in data and b"/usage" in data and b"\x28\xb5\x2f\xfd" in data:
            mt = os.path.getmtime(f)
            if cand is None or mt > cand[0]:
                cand = (mt, data)
    if cand is None:
        return None
    data = cand[1]
    i = data.find(b"\x28\xb5\x2f\xfd")  # zstd magic
    if i < 0:
        return None
    tmp = os.path.join(tempfile.gettempdir(), "_tokei_claude.zst")
    try:
        with open(tmp, "wb") as fh:
            fh.write(data[i:])
        raw = subprocess.run(["zstd", "-dc", tmp], capture_output=True).stdout
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass
    try:
        j = json.loads(raw)
    except Exception:
        return None
    fh_ = j.get("five_hour") or {}
    sd = j.get("seven_day") or {}
    return {
        "q5": fh_.get("utilization"),
        "q5_reset": _iso_to_epoch(fh_.get("resets_at")),
        "q7": sd.get("utilization"),
        "q7_reset": _iso_to_epoch(sd.get("resets_at")),
    }


def compute():
    bounds = range_bounds()
    cc = scan_claude(bounds)
    cx = scan_codex(bounds)

    def claude_range(b):
        denom = b["cr"] + b["cw"] + b["in"]
        hit = (b["cr"] / denom * 100) if denom else 0.0
        models = [{"name": nice_model(n), "in": v["in"], "out": v["out"],
                   "cr": v["cr"], "cw": v["cw"], "cost": v["cost"]}
                  for n, v in sorted(b["models"].items(),
                                     key=lambda kv: -kv[1]["cost"])]
        return {"hit": hit, "in": b["in"], "out": b["out"],
                "cr": b["cr"], "cw": b["cw"], "cost": b["cost"], "models": models}

    def codex_range(b):
        hit = (b["cached"] / b["in"] * 100) if b["in"] else 0.0
        return {"hit": hit, "in": b["in"] - b["cached"], "cached": b["cached"],
                "out": b["out"], "reason": b["reason"], "cost": b["cost"]}

    cranges = {k: claude_range(cc["ranges"][k]) for k in RANGE_KEYS}
    xranges = {k: codex_range(cx["ranges"][k]) for k in RANGE_KEYS}

    cur = cc["cur"]
    cur_total = cur["in"] + cur["out"] + cur["cr"] + cur["cw"]

    lim = cx["limits"] or {}
    p5 = (lim.get("primary") or {}).get("used_percent")
    pw = (lim.get("secondary") or {}).get("used_percent")
    r5 = (lim.get("primary") or {}).get("resets_at")
    rw = (lim.get("secondary") or {}).get("resets_at")

    plan = scan_claude_plan() or {}

    return {
        "claude": {
            "ranges": cranges,
            "session_name": cur["name"], "session_total": cur_total,
            "q5": plan.get("q5"), "q5_reset": plan.get("q5_reset"),
            "q7": plan.get("q7"), "q7_reset": plan.get("q7_reset"),
        },
        "codex": {
            "ranges": xranges,
            "p5": p5, "pw": pw, "r5": r5, "rw": rw,
            "plan": cx["plan"],
        },
    }


def main_json():
    print(json.dumps(compute(), ensure_ascii=False))


def main():
    d = compute()
    c, x = d["claude"], d["codex"]
    ct = c["ranges"]["today"]
    xt = x["ranges"]["today"]
    cc_hit = ct["hit"]
    cc_cost = ct["cost"]
    cur = {"name": c["session_name"]}
    cur_total = c["session_total"]
    cx_hit = xt["hit"]
    p5, pw, r5, rw = x["p5"], x["pw"], x["r5"], x["rw"]

    # ---- menu bar 标题(紧凑):⚡Claude命中率  ◷Codex周额度 ----
    parts = [f"⚡{cc_hit:.0f}"]
    if p5 is not None:
        parts.append(f"◷{p5:.0f}")
    elif pw is not None:
        parts.append(f"◷{pw:.0f}")
    print(" ".join(parts))
    print("---")

    F = "| font=Menlo size=14"
    HEAD = "| font=Menlo-Bold size=15"
    # Claude 块
    print(f"Claude Code {HEAD}")
    print(f"命中率   {cc_hit:5.1f}% {F}")
    print(f"今日 输入   {human(ct['in']):>6} {F}")
    print(f"今日 输出   {human(ct['out']):>6} {F}")
    print(f"今日 缓存读 {human(ct['cr']):>6} {F}")
    print(f"今日 缓存写 {human(ct['cw']):>6} {F}")
    print(f"今日 ≈成本  ${cc_cost:.2f} {F}")
    print(f"  (按 API 价估,非订阅实付) | font=Menlo size=11")
    print(f"本会话({cur['name']}) {human(cur_total)} {F}")
    print("---")
    # Codex 块
    print(f"Codex {HEAD}")
    print(f"命中率   {cx_hit:5.1f}% {F}")
    print(f"今日 输入   {human(xt['in']):>6} {F}")
    print(f"今日 缓存读 {human(xt['cached']):>6} {F}")
    print(f"今日 输出   {human(xt['out']):>6} {F}")
    if xt.get("reason"):
        print(f"今日 推理   {human(xt['reason']):>6} {F}")
    print(f"今日 ≈成本  ${xt['cost']:.2f} {F}")
    print(f"  (按 API 价估,订阅实付不按此) | font=Menlo size=11")
    if p5 is not None:
        print(f"5h 额度  {p5:5.1f}%  reset {fmt_reset(r5)} {F}")
    if pw is not None:
        print(f"周额度   {pw:5.1f}%  reset {fmt_reset(rw)} {F}")
    if x["plan"]:
        print(f"plan: {x['plan']} {F}")
    print("---")
    print("刷新 | refresh=true")


if __name__ == "__main__":
    if "--json" in sys.argv:
        main_json()
    else:
        main()
