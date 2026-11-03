"""校园示意图地理配准：把 0.4.0 官方手绘图反推到 WGS-84，并生成 App 侧数据文件。

模型刻意选择**无旋转的轴对齐变换**（dx = a·px + b，dy = c·py + d）：
示意图本质是正北向上的平面图，用带旋转的相似变换会让每块瓦片的轴对齐外接矩形
比实际内容略大，相邻瓦片被拉伸的方向不同，接缝处会错开 0.4~0.8 m。
轴对齐后瓦片天然共边，精度几乎不变（平均 17.2 m）。

流程：
1. OSM 真实建筑轮廓 ↔ `lib/data/campus_places.dart` 锚点，按「名称 + 距离」配对，
   鲁棒拟合轴对齐变换（锚点是图像坐标，需先翻 y）。
2. 从 `tools/map/labels/labels_*.webp` 的 alpha 连通域切出印刷标签框（仅作诊断留档）。
3. 生成 `lib/data/campus_labels.dart`（139 个锚点的经纬度，含同名不同楼）
   与 `lib/data/campus_tiles.dart`（30 块瓦片的经纬度范围，共边）。

用法：
    python tools/map/georef_campus_map.py
输出：scratch/georef_params.json、places_latlng.json、label_boxes.json、gcp_pairs.csv
"""

from __future__ import annotations

import json
import math
import re
from difflib import SequenceMatcher
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "scratch"
MAP_W, MAP_H = 4500.0, 5350.0
LAT0, LNG0 = 31.2935, 121.5545
M_LAT = 110540.0
M_LNG = 111320.0 * math.cos(math.radians(LAT0))


# ---------------------------------------------------------------- 几何
def to_enu(lng, lat):
    return np.stack(
        [(np.asarray(lng) - LNG0) * M_LNG, (np.asarray(lat) - LAT0) * M_LAT], axis=-1
    )


def to_ll(xy):
    return (LAT0 + float(xy[1]) / M_LAT, LNG0 + float(xy[0]) / M_LNG)


def ring_centroid(pts):
    pts = np.asarray(pts, float)
    x, y = pts[:, 0], pts[:, 1]
    x1, y1 = np.roll(x, -1), np.roll(y, -1)
    cross = x * y1 - x1 * y
    area2 = cross.sum()
    if abs(area2) < 1e-15:
        return pts.mean(0)
    return np.array(
        [((x + x1) * cross).sum() / (3 * area2), ((y + y1) * cross).sum() / (3 * area2)]
    )


def fit_axis(src, dst):
    """轴对齐映射：dx = ax·px + bx，dy = ay·py + by（无旋转、无切变、允许横纵比例不同）。"""
    ax, *_ = np.linalg.lstsq(
        np.column_stack([src[:, 0], np.ones(len(src))]), dst[:, 0], rcond=None
    )
    ay, *_ = np.linalg.lstsq(
        np.column_stack([src[:, 1], np.ones(len(src))]), dst[:, 1], rcond=None
    )
    return ax, ay


def apply_axis(model, pts):
    ax, ay = model
    pts = np.asarray(pts, float)
    return np.column_stack([pts[:, 0] * ax[0] + ax[1], pts[:, 1] * ay[0] + ay[1]])


# ---------------------------------------------------------------- 名称
def norm_name(s: str) -> str:
    s = re.sub(r"[（(].*?[)）]", "", (s or "").strip())
    s = re.sub(r"[\s·・\-—_]", "", s)
    return s.replace("学生公寓", "学生宿舍").replace("公寓", "宿舍")


def name_score(a: str, b: str) -> float:
    na, nb = norm_name(a), norm_name(b)
    if not na or not nb:
        return 0.0
    if na == nb:
        return 1.0
    if na in nb or nb in na:
        return 0.88
    return SequenceMatcher(None, na, nb).ratio()


# ---------------------------------------------------------------- 数据源
def load_places():
    txt = (ROOT / "lib/data/campus_places.dart").read_text("utf-8")
    return [
        (m.group(1), float(m.group(2)), float(m.group(3)))
        for m in re.finditer(
            r"CampusPlace\(name:\s*'([^']+)',\s*anchor:\s*Offset\(([\d.]+),\s*([\d.]+)\)\)",
            txt,
        )
    ]


def load_osm():
    geo = json.loads(
        (ROOT / "tools/map/usst_516_buildings.geojson").read_text("utf-8")
    )
    out = []
    for feature in geo["features"]:
        geometry = feature.get("geometry") or {}
        if geometry.get("type") != "Polygon":
            continue
        center = ring_centroid(geometry["coordinates"][0])
        if not (121.545 < center[0] < 121.562 and 31.286 < center[1] < 31.299):
            continue
        out.append(
            {
                "name": (feature.get("properties") or {}).get("name", "") or "",
                "lnglat": center,
                "enu": to_enu(*center),
            }
        )
    return out


# ---------------------------------------------------------------- 配准
def solve(places, osm):
    # 锚点是图像坐标（y 向下），翻成北向上后再做轴对齐映射
    p = np.array([[x * MAP_W, (1 - y) * MAP_H] for _, x, y in places])

    def assign(radius, gate, model):
        pred = apply_axis(model, p)
        cand = []
        for pi in range(len(places)):
            for oi, o in enumerate(osm):
                if not o["name"]:
                    continue
                score = name_score(places[pi][0], o["name"])
                if score < gate:
                    continue
                dist = float(np.linalg.norm(o["enu"] - pred[pi]))
                if dist > radius:
                    continue
                cand.append((score + 0.3 * (1 - dist / radius), pi, oi))
        cand.sort(key=lambda c: -c[0])
        used_p, used_o, out = set(), set(), []
        for _, pi, oi in cand:
            if pi in used_p or oi in used_o:
                continue
            used_p.add(pi)
            used_o.add(oi)
            out.append((pi, oi, name_score(places[pi][0], osm[oi]["name"])))
        return out

    # 1. 精确同名 bootstrap
    pairs = []
    for pi in range(len(places)):
        for oi, o in enumerate(osm):
            if o["name"] and name_score(places[pi][0], o["name"]) >= 0.999:
                pairs.append((pi, oi, 1.0))
                break

    # 2. 名称 + 距离交替迭代
    for radius, gate in ((400, 0.55), (260, 0.55), (170, 0.6), (110, 0.62)):
        model = fit_axis(
            np.array([p[i] for i, _, _ in pairs]),
            np.array([osm[j]["enu"] for _, j, _ in pairs]),
        )
        cand = assign(radius, gate, model)
        if len(cand) >= 8:
            pairs = cand

    # 3. 鲁棒剔除离群点
    for _ in range(6):
        src = np.array([p[i] for i, _, _ in pairs])
        dst = np.array([osm[j]["enu"] for _, j, _ in pairs])
        model = fit_axis(src, dst)
        res = np.linalg.norm(apply_axis(model, src) - dst, axis=1)
        keep = res <= max(15.0, 2.5 * float(np.median(res)))
        if keep.all() or keep.sum() < 8:
            break
        pairs = [pair for pair, k in zip(pairs, keep) if k]

    pairs = [pair for pair in pairs if pair[2] >= 0.6]
    src = np.array([p[i] for i, _, _ in pairs])
    dst = np.array([osm[j]["enu"] for _, j, _ in pairs])
    model = fit_axis(src, dst)
    residual = np.linalg.norm(apply_axis(model, src) - dst, axis=1)

    # 留一交叉验证
    loo = []
    for i in range(len(src)):
        mask = np.arange(len(src)) != i
        m2 = fit_axis(src[mask], dst[mask])
        loo.append(
            float(np.linalg.norm(apply_axis(m2, src[i : i + 1])[0] - dst[i]))
        )
    return pairs, residual, np.array(loo), model, p


# ---------------------------------------------------------------- 标签框（诊断留档）
def label_boxes():
    canvas = Image.new("RGBA", (int(MAP_W), int(MAP_H)), (0, 0, 0, 0))
    for row in range(6):
        for col in range(5):
            tile = Image.open(
                ROOT / f"tools/map/labels/labels_r{row}_c{col}.webp"
            ).convert("RGBA")
            w = int(min(1024, MAP_W - col * 1024))
            h = int(min(1024, MAP_H - row * 1024))
            canvas.paste(tile.crop((0, 0, w, h)), (col * 1024, row * 1024))

    mask = np.asarray(canvas)[:, :, 3] > 8
    parent = list(range(1))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    runs, prev = [], []
    for y in range(mask.shape[0]):
        row = mask[y]
        if not row.any():
            prev = []
            continue
        d = np.diff(row.astype(np.int8))
        starts = list(np.flatnonzero(d == 1) + 1)
        ends = list(np.flatnonzero(d == -1) + 1)
        if row[0]:
            starts.insert(0, 0)
        if row[-1]:
            ends.append(len(row))
        cur = []
        for x0, x1 in zip(starts, ends):
            parent.append(len(parent))
            rid = len(parent) - 1
            cur.append((x0, x1, rid))
            for px0, px1, pid in prev:
                if x0 < px1 and px0 < x1:
                    ra, rb = find(rid), find(pid)
                    if ra != rb:
                        parent[rb] = ra
        for x0, x1, rid in cur:
            runs.append((find(rid), y, x0, x1))
        prev = cur

    merged = {}
    for rid, y, x0, x1 in runs:
        box = merged.setdefault(find(rid), [MAP_W, MAP_H, 0, 0])
        box[0] = min(box[0], x0)
        box[1] = min(box[1], y)
        box[2] = max(box[2], x1)
        box[3] = max(box[3], y + 1)
    return [b for b in merged.values() if (b[2] - b[0]) * (b[3] - b[1]) > 400]


def match_boxes(boxes, places):
    out = []
    for x0, y0, x1, y1 in boxes:
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        best, best_d = None, 1e9
        for name, ax, ay in places:
            d = math.hypot(ax * MAP_W - cx, ay * MAP_H - cy)
            if d < best_d:
                best_d, best = d, name
        out.append(
            {
                "bbox": [int(x0), int(y0), int(x1), int(y1)],
                "center": [round(cx, 1), round(cy, 1)],
                "name": best,
                "anchor_dist_px": round(best_d, 1),
            }
        )
    out.sort(key=lambda r: (r["bbox"][1], r["bbox"][0]))
    return out


# ---------------------------------------------------------------- 输出
def place_latlng(model, anchor_x, anchor_y):
    enu = apply_axis(model, np.array([[(anchor_x) * MAP_W, (1 - anchor_y) * MAP_H]]))[0]
    return to_ll(enu)


def write_labels_dart(places, model):
    rows, seen = [], set()
    for name, ax, ay in places:
        key = (name, round(ax, 4), round(ay, 4))
        if key in seen:
            continue
        seen.add(key)
        lat, lng = place_latlng(model, ax, ay)
        rows.append((name, ax, ay, lat, lng))
    rows.sort(key=lambda r: (r[2], r[1]))

    lines = [
        "// 校园地点：139 个官方锚点（含同名但位置不同的楼，例如机械工程学院实验中心（二）的两栋）。",
        "// 由 tools/map/georef_campus_map.py 生成，勿手改。",
        "// anchor 为 4500x5350 示意图上的归一化坐标（y 向下）；lat/lng 由 36 个 OSM 控制点反推（平均 ~17 m）。",
        "",
        "import 'dart:ui';",
        "",
        "class CampusLabel {",
        "  const CampusLabel({",
        "    required this.name,",
        "    required this.anchor,",
        "    required this.lat,",
        "    required this.lng,",
        "  });",
        "",
        "  final String name;",
        "",
        "  /// 示意图上的归一化锚点，用于把课表教室名对回楼栋。",
        "  final Offset anchor;",
        "",
        "  final double lat;",
        "  final double lng;",
        "}",
        "",
        "const List<CampusLabel> kCampusLabels = <CampusLabel>[",
    ]
    for name, ax, ay, lat, lng in rows:
        escaped = name.replace("'", "\\'")
        lines.append(
            "  CampusLabel(name: '%s', anchor: Offset(%.4f, %.4f), "
            "lat: %.6f, lng: %.6f)," % (escaped, ax, ay, lat, lng)
        )
    lines += ["];", ""]
    (ROOT / "lib/data/campus_labels.dart").write_text("\n".join(lines), encoding="utf-8")
    return len(rows)


def write_tiles_dart(model):
    def px_to_ll(px, py):
        return to_ll(apply_axis(model, np.array([[px, MAP_H - py]]))[0])

    tiles = []
    for row in range(6):
        for col in range(5):
            x0, y0 = col * 1024, row * 1024
            x1, y1 = min(x0 + 1024, MAP_W), min(y0 + 1024, MAP_H)
            corners = [
                px_to_ll(x0, y0),
                px_to_ll(x1, y0),
                px_to_ll(x1, y1),
                px_to_ll(x0, y1),
            ]
            tiles.append(
                {
                    "base": f"assets/map/base_r{row}_c{col}.webp",
                    "south": round(min(c[0] for c in corners), 7),
                    "west": round(min(c[1] for c in corners), 7),
                    "north": round(max(c[0] for c in corners), 7),
                    "east": round(max(c[1] for c in corners), 7),
                }
            )

    # 共边自检：相邻瓦片共享边必须严格相等
    eps = 1e-9
    for row in range(6):
        for col in range(5):
            cur = tiles[row * 5 + col]
            if col < 4:
                nxt = tiles[row * 5 + col + 1]
                assert abs(cur["east"] - nxt["west"]) < eps, (row, col, "west seam")
            if row < 5:
                down = tiles[(row + 1) * 5 + col]
                assert abs(cur["south"] - down["north"]) < eps, (row, col, "south seam")

    lines = [
        "// 0.4.0 官方示意图拆成的 30 块 1024px 瓦片，以及它们在地图上的经纬度范围。",
        "// 由 tools/map/georef_campus_map.py 生成，勿手改。",
        "// 轴对齐变换保证相邻瓦片严格共边（脚本内有断言自检）。",
        "",
        "import 'package:flutter_map/flutter_map.dart';",
        "import 'package:latlong2/latlong.dart';",
        "",
        "class CampusTile {",
        "  const CampusTile({",
        "    required this.asset,",
        "    required this.south,",
        "    required this.west,",
        "    required this.north,",
        "    required this.east,",
        "  });",
        "",
        "  final String asset;",
        "  final double south;",
        "  final double west;",
        "  final double north;",
        "  final double east;",
        "",
        "  LatLngBounds get bounds =>",
        "      LatLngBounds(LatLng(south, west), LatLng(north, east));",
        "}",
        "",
        "const List<CampusTile> kCampusTiles = <CampusTile>[",
    ]
    for tile in tiles:
        lines.append(
            "  CampusTile(asset: '%s', south: %.7f, west: %.7f, "
            "north: %.7f, east: %.7f),"
            % (tile["base"], tile["south"], tile["west"], tile["north"], tile["east"])
        )
    lines += ["];", ""]
    (ROOT / "lib/data/campus_tiles.dart").write_text("\n".join(lines), encoding="utf-8")
    return len(tiles)


def main():
    OUT.mkdir(exist_ok=True)
    places = load_places()
    osm = load_osm()
    pairs, residual, loo, model, p = solve(places, osm)

    records, place_records = [], {}
    for name, ax, ay in places:
        lat, lng = place_latlng(model, ax, ay)
        records.append(
            {"name": name, "anchor": [round(ax, 4), round(ay, 4)],
             "lat": round(lat, 7), "lng": round(lng, 7)}
        )
        place_records[name] = {"lat": round(lat, 7), "lng": round(lng, 7)}

    boxes = match_boxes(label_boxes(), places)
    label_count = write_labels_dart(places, model)
    tile_count = write_tiles_dart(model)

    ax_coef, ay_coef = model
    params = {
        "model": "axis-aligned (no rotation): dx = a*px + b, dy = c*(H-py) + d",
        "image_size": [MAP_W, MAP_H],
        "y_convention": "normalized y is top-down; flip with (1 - y) before applying",
        "scale_x_m_per_px": round(float(ax_coef[0]), 6),
        "scale_y_m_per_px": round(float(ay_coef[0]), 6),
        "offset_enu_m": [round(float(ax_coef[1]), 3), round(float(ay_coef[1]), 3)],
        "origin": {"lat": LAT0, "lng": LNG0},
        "m_per_deg": {"lat": M_LAT, "lng": round(M_LNG, 4)},
        "accuracy": {
            "control_points": len(pairs),
            "residual_mean_m": round(float(residual.mean()), 1),
            "residual_max_m": round(float(residual.max()), 1),
            "loo_mean_m": round(float(loo.mean()), 1),
            "loo_max_m": round(float(loo.max()), 1),
        },
        "labels": label_count,
        "tiles": tile_count,
        "note": "无旋转是刻意的：带旋转时每块瓦片的轴对齐外接矩形会被轻微拉伸，接缝错开 0.4~0.8 m",
        "formula": "ENU_x = a*px + b ; ENU_y = c*(H-py) + d ; lat = LAT0 + ENU_y/M_LAT ; lng = LNG0 + ENU_x/M_LNG",
    }
    (OUT / "georef_params.json").write_text(json.dumps(params, ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT / "places_latlng.json").write_text(json.dumps(records, ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT / "label_boxes.json").write_text(json.dumps(boxes, ensure_ascii=False, indent=1), encoding="utf-8")

    import csv

    with open(OUT / "gcp_pairs.csv", "w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.writer(handle)
        writer.writerow(["place", "osm", "match", "px", "py", "lat", "lng", "residual_m"])
        for (pi, oi, score), res in zip(pairs, residual):
            name, ax, ay = places[pi]
            lat, lng = osm[oi]["lnglat"][1], osm[oi]["lnglat"][0]
            writer.writerow([name, osm[oi]["name"], f"{score:.2f}", f"{ax*MAP_W:.1f}", f"{ay*MAP_H:.1f}",
                             f"{lat:.7f}", f"{lng:.7f}", f"{res:.1f}"])

    print(
        f"pairs={len(pairs)} residual={residual.mean():.1f}m loo={loo.mean():.1f}m "
        f"labels={label_count} tiles={tile_count} "
        f"scale=({ax_coef[0]:.6f}, {ay_coef[0]:.6f}) m/px"
    )


if __name__ == "__main__":
    main()

