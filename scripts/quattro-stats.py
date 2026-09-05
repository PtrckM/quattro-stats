#!/usr/bin/env python3
"""Collector for the Quattro Stats Omarchy plugin.

Samples /proc twice, one second apart, to compute CPU/network/disk-io rates,
then emits a single JSON document on stdout. Every external tool is optional;
missing tools degrade a section to null rather than failing the whole run.
"""
import json
import os
import re
import subprocess
import time

PING_HOST = os.environ.get("QUATTRO_PING_HOST", "1.1.1.1")
BATTERY_DIR = os.environ.get("QUATTRO_BATTERY_DIR", "/sys/class/power_supply/BAT0")


def sh(cmd, timeout=3):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""


def read_file(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except Exception:
        return None


def cpu_times():
    stat = read_file("/proc/stat")
    if not stat:
        return {"user": 0, "system": 0, "total": 0}
    parts = [int(x) for x in stat.splitlines()[0].split()[1:]]
    parts = (parts + [0] * 8)[:8]
    user, nice, system, idle, iowait, irq, softirq, steal = parts
    idle_all = idle + iowait
    non_idle = user + nice + system + irq + softirq + steal
    return {"user": user + nice, "system": system + irq + softirq, "total": idle_all + non_idle}


def net_bytes():
    result = {}
    dev = read_file("/proc/net/dev")
    if not dev:
        return result
    for line in dev.splitlines()[2:]:
        if ":" not in line:
            continue
        iface, rest = line.split(":", 1)
        iface = iface.strip()
        if iface == "lo":
            continue
        fields = rest.split()
        result[iface] = {"rx": int(fields[0]), "tx": int(fields[8])}
    return result


def disk_sectors():
    result = {}
    stats = read_file("/proc/diskstats")
    if not stats:
        return result
    for line in stats.splitlines():
        f = line.split()
        name = f[2]
        if re.match(r"^(loop|ram|dm-)", name):
            continue
        result[name] = {"read": int(f[5]) * 512, "write": int(f[9]) * 512}
    return result


def default_iface():
    out = sh(["ip", "route", "get", PING_HOST])
    m = re.search(r"dev (\S+)", out)
    return m.group(1) if m else None


def primary_disk():
    out = sh(["df", "-B1", "--output=source,size,used,avail,pcent,target", "/"])
    lines = out.splitlines()
    if len(lines) < 2:
        return None
    f = lines[1].split()
    return {
        "source": f[0],
        "totalBytes": int(f[1]),
        "usedBytes": int(f[2]),
        "availBytes": int(f[3]),
        "usedPercent": int(f[4].rstrip("%")),
        "mount": f[5],
    }


def sensors_json():
    out = sh(["sensors", "-j"])
    if not out:
        return None
    try:
        return json.loads(out)
    except Exception:
        return None


def cpu_temp(sensors_data):
    if not sensors_data:
        return None
    for chip, chip_sensors in sensors_data.items():
        if not chip.startswith("coretemp") and "cpu" not in chip.lower():
            continue
        for label, vals in chip_sensors.items():
            if not isinstance(vals, dict):
                continue
            if label.lower().startswith("package") or label == "Tctl":
                for k, v in vals.items():
                    if k.endswith("_input"):
                        return v
    return None


def fan_speeds(sensors_data):
    result = {}
    if not sensors_data:
        return result
    for chip_sensors in sensors_data.values():
        for label, vals in chip_sensors.items():
            if not isinstance(vals, dict):
                continue
            for k, v in vals.items():
                if k.endswith("_input") and "fan" in k:
                    result[label] = v
    return result


def gpu_stats():
    out = sh([
        "nvidia-smi",
        "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,clocks.sm,power.draw",
        "--format=csv,noheader,nounits",
    ])
    if not out:
        return None
    parts = [p.strip() for p in out.splitlines()[0].split(",")]

    def to_num(s):
        try:
            return float(s)
        except Exception:
            return None

    if len(parts) < 6:
        return None
    return {
        "util": to_num(parts[0]),
        "tempC": to_num(parts[1]),
        "memUsedMB": to_num(parts[2]),
        "memTotalMB": to_num(parts[3]),
        "clockMHz": to_num(parts[4]),
        "powerW": to_num(parts[5]),
    }


def memory():
    meminfo = read_file("/proc/meminfo")
    if not meminfo:
        return None
    info = {}
    for line in meminfo.splitlines():
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        info[k.strip()] = int(v.strip().split()[0]) * 1024
    total = info.get("MemTotal", 0)
    free = info.get("MemFree", 0)
    available = info.get("MemAvailable", free)
    buffers = info.get("Buffers", 0)
    cached = info.get("Cached", 0)
    used = max(0, total - available)
    return {
        "totalBytes": total,
        "usedBytes": used,
        "freeBytes": available,
        "buffersBytes": buffers,
        "cachedBytes": cached,
        "usedPercent": round(used / total * 100, 1) if total else 0,
    }


def load_avg():
    loadavg = read_file("/proc/loadavg")
    if not loadavg:
        return None
    parts = loadavg.split()
    return {"one": float(parts[0]), "five": float(parts[1]), "fifteen": float(parts[2])}


def uptime_seconds():
    up = read_file("/proc/uptime")
    return float(up.split()[0]) if up else None


def battery():
    if not os.path.isdir(BATTERY_DIR):
        return None

    def rd(name):
        return read_file(os.path.join(BATTERY_DIR, name))

    capacity = rd("capacity")
    status = rd("status")
    energy_full = rd("energy_full") or rd("charge_full")
    energy_full_design = rd("energy_full_design") or rd("charge_full_design")
    energy_now = rd("energy_now") or rd("charge_now")
    health = None
    if energy_full and energy_full_design:
        try:
            design = int(energy_full_design)
            health = round(int(energy_full) / design * 100) if design else None
        except Exception:
            health = None

    # Instantaneous draw, in microwatts. Falls back to current*voltage when
    # the driver doesn't expose power_now directly.
    power_now = rd("power_now")
    if not power_now:
        current_now = rd("current_now")
        voltage_now = rd("voltage_now")
        if current_now and voltage_now:
            try:
                power_now = str(abs(int(current_now)) * abs(int(voltage_now)) // 1_000_000)
            except Exception:
                power_now = None

    ac_online = read_file("/sys/class/power_supply/AC0/online")
    plugged_in = ac_online == "1"

    time_to_full_min = None
    time_to_ten_min = None
    try:
        if power_now and int(power_now) > 0 and energy_now and energy_full:
            p = int(power_now)
            e_now = int(energy_now)
            e_full = int(energy_full)
            if status == "Charging":
                time_to_full_min = round(max(0, e_full - e_now) / p * 60)
            elif status == "Discharging":
                ten_pct = 0.10 * e_full
                time_to_ten_min = round(max(0, e_now - ten_pct) / p * 60)
    except Exception:
        pass

    is_full = status == "Full" or (
        plugged_in and capacity and int(capacity) >= 99
        and not (power_now and int(power_now) > 0 and status == "Charging")
    )

    return {
        "percent": int(capacity) if capacity else None,
        "status": status,
        "charging": status == "Charging",
        "pluggedIn": plugged_in,
        "full": is_full,
        "health": health,
        "timeToFullMin": time_to_full_min,
        "timeToTenMin": time_to_ten_min,
    }


def ping(host):
    out = sh(["ping", "-c", "1", "-W", "1", host], timeout=2)
    m = re.search(r"time=([\d.]+)", out)
    return {"host": host, "ms": float(m.group(1)) if m else None, "ok": m is not None}


def main():
    cpu1 = cpu_times()
    net1 = net_bytes()
    disk1 = disk_sectors()
    time.sleep(1.0)
    cpu2 = cpu_times()
    net2 = net_bytes()
    disk2 = disk_sectors()

    total_delta = cpu2["total"] - cpu1["total"]
    user_delta = cpu2["user"] - cpu1["user"]
    system_delta = cpu2["system"] - cpu1["system"]
    cpu_pct_user = round(user_delta / total_delta * 100, 1) if total_delta else 0.0
    cpu_pct_system = round(system_delta / total_delta * 100, 1) if total_delta else 0.0

    rx1 = sum(v["rx"] for v in net1.values())
    tx1 = sum(v["tx"] for v in net1.values())
    rx2 = sum(v["rx"] for v in net2.values())
    tx2 = sum(v["tx"] for v in net2.values())

    r1 = sum(v["read"] for v in disk1.values())
    w1 = sum(v["write"] for v in disk1.values())
    r2 = sum(v["read"] for v in disk2.values())
    w2 = sum(v["write"] for v in disk2.values())

    sensors_data = sensors_json()

    payload = {
        "ok": True,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "cpu": {
            "user": cpu_pct_user,
            "system": cpu_pct_system,
            "total": round(cpu_pct_user + cpu_pct_system, 1),
            "tempC": cpu_temp(sensors_data),
        },
        "gpu": gpu_stats(),
        "memory": memory(),
        "disk": primary_disk(),
        "diskio": {
            "readBps": max(0, r2 - r1),
            "writeBps": max(0, w2 - w1),
        },
        "network": {
            "iface": default_iface(),
            "downBps": max(0, rx2 - rx1),
            "upBps": max(0, tx2 - tx1),
        },
        "load": load_avg(),
        "uptimeSeconds": uptime_seconds(),
        "battery": battery(),
        "fans": fan_speeds(sensors_data),
        "ping": ping(PING_HOST),
    }
    print(json.dumps(payload))


if __name__ == "__main__":
    main()
