#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""学习通（超星）接口探测工具。

目的：现有 App 里课程列表/作业列表靠正则解析 HTML，很脆。超星其实有 JSON 接口，
但字段结构没有公开文档，需要拿真实会话跑一次才能确认。这个脚本就是干这个的。

用法：
    # 1. 电脑浏览器登录 https://i.chaoxing.com
    # 2. F12 → Application → Cookies → 复制整条 cookie（含 _uid / _dstu / fid 等）
    $env:CX_COOKIE = "_uid=...; _dstu=...; fid=24960; ..."
    python chaoxing_probe.py

    # 只探某一项
    python chaoxing_probe.py --only courses

输出：
    · 每个接口的状态码、Content-Type、响应前若干字符
    · JSON 接口会打印「顶层键 + 第一项的键」——这正是写解析代码需要的
    · 原始响应存到 %TEMP%\\cx_probe\\ 下，方便事后分析

注意：cookie 等同账号凭据，别提交、别外传。
"""

import argparse
import json
import os
import re
import sys

import requests

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)
OUT_DIR = os.path.join(os.environ.get("TEMP", "."), "cx_probe")

FID = "24960"  # 上海理工大学在学习通的机构号（App 里写死的那个）


def show_json(tag, text, limit=1200):
    """打印 JSON 的结构而不是全文——键名才是我们需要的。"""
    try:
        data = json.loads(text)
    except ValueError:
        print(f"    {tag}: 不是 JSON，前 200 字：{text[:200]!r}")
        return None

    if isinstance(data, dict):
        print(f"    {tag}: dict, 顶层键 = {list(data.keys())[:12]}")
        _peek(tag, data, limit)
    elif isinstance(data, list):
        print(f"    {tag}: list, 长度 = {len(data)}")
        if data:
            _peek(tag, data[0], limit)
    else:
        print(f"    {tag}: {type(data).__name__} = {str(data)[:200]}")
    return data


def _peek(tag, obj, limit):
    if isinstance(obj, dict):
        print(f"        第一项键 = {list(obj.keys())[:20]}")
    size = len(json.dumps(obj, ensure_ascii=False))
    if size > limit:
        print(f"        （内容 {size} 字节，已截断）")


def dump(name, text):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


def main():
    ap = argparse.ArgumentParser(description="学习通接口探测")
    ap.add_argument("--cookie", default=os.environ.get("CX_COOKIE"))
    ap.add_argument("--only", choices=["courses", "active", "works", "exam"],
                    help="只探某一项")
    args = ap.parse_args()

    if not args.cookie:
        print("缺 cookie。设置环境变量 CX_COOKIE，或 --cookie '...'")
        return 1

    s = requests.Session()
    s.headers.update({
        "User-Agent": UA,
        "Cookie": args.cookie,
        "Accept": "*/*",
        "Referer": "https://i.chaoxing.com/",
    })

    want = lambda k: args.only in (None, k)  # noqa: E731

    # ---------------------------------------------------------- 账号信息
    r = s.get("https://i.chaoxing.com/base", timeout=20)
    print(f"\n[账号] i.chaoxing.com/base -> {r.status_code} "
          f"{r.headers.get('content-type', '')[:30]} len={len(r.text)}")
    m = re.search(r"<title>([^<]*)</title>", r.text)
    if m:
        print(f"    标题: {m.group(1).strip()[:40]}")

    # ---------------------------------------------------------- 课程（JSON）
    courses = []
    if want("courses"):
        url = "https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&rss=1"
        r = s.get(url, timeout=20)
        print(f"\n[课程·JSON] backclazzdata -> {r.status_code}")
        data = show_json("course", r.text)
        dump("backclazzdata.json", r.text)

        if isinstance(data, dict) and data.get("result") == 1:
            for channel in data.get("channelList") or []:
                content = (channel or {}).get("content") or {}
                course = content.get("course") or {}
                for item in course.get("data") or []:
                    courses.append({
                        "courseId": str(item.get("courseid", "")),
                        "classId": str(item.get("clazzid") or item.get("id", "")),
                        "name": item.get("name", ""),
                        "cpi": str(item.get("personid") or item.get("cpi") or ""),
                    })
            print(f"    解析出 {len(courses)} 门课")
            for c in courses[:5]:
                print(f"      {c['courseId']:<12} {c['classId']:<12} "
                      f"cpi={c['cpi'][:12]:<14} {c['name'][:24]}")

    # 没从 JSON 里拿到课程，就退回 HTML 列表（和 App 现在的做法一致）
    if not courses and want("courses"):
        url = "https://mooc1-1.chaoxing.com/visit/courselistdata?courseType=1&isActive=1"
        r = s.get(url, timeout=20)
        print(f"\n[课程·HTML] courselistdata -> {r.status_code} len={len(r.text)}")
        dump("courselistdata.html", r.text)
        for m in re.finditer(
            r'<li[^>]*courseId="(\d+)"[^>]*clazzId="(\d+)"[^>]*personId="(\d+)"',
            r.text,
        ):
            courses.append({
                "courseId": m.group(1),
                "classId": m.group(2),
                "cpi": m.group(3),
                "name": "",
            })
        print(f"    正则解析出 {len(courses)} 门课")

    if not courses:
        print("\n⚠ 没拿到课程列表，后面的逐课程接口没法探。先确认 cookie 是否有效。")
        return 2

    head = courses[:3]  # 只探前几门，够看结构

    # ---------------------------------------------------------- 签到活动
    if want("active"):
        print("\n[签到活动·JSON] activelist")
        for c in head:
            r = s.get(
                "https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist",
                params={"fid": FID, "courseId": c["courseId"],
                        "classId": c["classId"], "showNotStartedActive": "1"},
                timeout=20,
            )
            print(f"  {c['name'][:18] or c['courseId']}: {r.status_code} len={len(r.text)}")
            show_json("active", r.text)

    # ---------------------------------------------------------- 作业列表
    if want("works"):
        print("\n[作业·HTML] mooc2/work/list")
        for c in head:
            r = s.get(
                "https://mooc1-1.chaoxing.com/mooc-ans/visit/stucoursemiddle",
                params={"courseid": c["courseId"], "clazzid": c["classId"],
                        "vc": "1", "cpi": c["cpi"], "ismooc2": "1", "v": "2"},
                timeout=20,
            )
            enc = re.search(r'id="workEnc"[^>]*value="([^"]+)"', r.text)
            print(f"  {c['name'][:18] or c['courseId']}: middle={r.status_code} "
                  f"workEnc={'有' if enc else '无'}")
            if not enc:
                continue
            r2 = s.get(
                "https://mooc1.chaoxing.com/mooc2/work/list",
                params={"courseId": c["courseId"], "classId": c["classId"],
                        "enc": enc.group(1), "cpi": c["cpi"], "ut": "s"},
                timeout=20,
            )
            items = re.findall(r'goTask\(this\);', r2.text)
            print(f"      列表={r2.status_code} len={len(r2.text)} 条目≈{len(items)}")
            dump(f"worklist_{c['courseId']}.html", r2.text)

    # ---------------------------------------------------------- 考试列表
    if want("exam"):
        print("\n[考试·探测] exam-list")
        for c in head:
            r = s.get(
                "https://mooc1.chaoxing.com/mooc2/exam/exam-list",
                params={"courseId": c["courseId"], "classId": c["classId"],
                        "cpi": c["cpi"]},
                timeout=20,
            )
            print(f"  {c['name'][:18] or c['courseId']}: {r.status_code} len={len(r.text)}")
            if r.status_code == 200:
                dump(f"examlist_{c['courseId']}.html", r.text)

    print(f"\n原始响应已存到: {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
