#!/usr/bin/env python3
"""Builds the KHERJA vehicle artwork for every platform from the SVG sources in this folder.

  kherja_car.svg + kherja_moto.svg  ->  kherja_duo.svg
  kherja_front.svg: front view with driver and passenger (welcome scene)
  Android: VectorDrawable XML in res/drawable (kj_car / kj_moto / kj_duo / kj_front)
  iOS:     vector PDFs in Assets.xcassets (preserves vector data)

Only the SVG subset used by these files is supported (path, circle, ellipse, rect, g with
translate/scale, linear gradients in objectBoundingBox units). Run:  python3 build_assets.py
"""
import os, re, subprocess, sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ANDROID_DRAWABLE = os.path.join(ROOT, "android-kherja/app/src/main/res/drawable")
IOS_ASSETS = os.path.join(ROOT, "ios-kherja/KHERJA/Assets.xcassets")
NS = {"s": "http://www.w3.org/2000/svg"}
ET.register_namespace("", NS["s"])


def inner(path):
    root = ET.parse(path).getroot()
    vb = [float(x) for x in root.get("viewBox").split()]
    return root, vb


def build_duo():
    car, cvb = inner(os.path.join(HERE, "kherja_car.svg"))
    moto, mvb = inner(os.path.join(HERE, "kherja_moto.svg"))
    ground = 150.0
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 670 170" width="670" height="170">']
    for root in (car, moto):
        for d in root.findall("s:defs", NS):
            out.append(ET.tostring(d, encoding="unicode").replace(' xmlns="http://www.w3.org/2000/svg"', ""))
    for root, s, tx in ((car, 0.80, 0.0), (moto, 0.82, 392.0)):
        ty = ground - 232 * s
        out.append(f'<g transform="translate({tx} {ty}) scale({s})">')
        for el in root:
            if el.tag.endswith("defs"):
                continue
            out.append(ET.tostring(el, encoding="unicode").replace(' xmlns="http://www.w3.org/2000/svg"', ""))
        out.append("</g>")
    out.append("</svg>")
    with open(os.path.join(HERE, "kherja_duo.svg"), "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def argb(color, alpha=1.0):
    color = color.lstrip("#")
    a = int(round(alpha * 255))
    return f"#{a:02X}{color.upper()}"


def bbox(d):
    nums = [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", d)]
    # Absolute commands only: M/L/C pairs; A has 7 numbers (rx ry rot large sweep x y).
    xs, ys, i = [], [], 0
    tokens = re.findall(r"[MLCAZ]|-?\d+(?:\.\d+)?", d)
    cmd, buf = None, []
    for t in tokens:
        if t in "MLCAZ":
            cmd, buf = t, []
            continue
        buf.append(float(t))
        if cmd in "ML" and len(buf) == 2:
            xs.append(buf[0]); ys.append(buf[1]); buf = []
        elif cmd == "C" and len(buf) == 6:
            xs += buf[0::2]; ys += buf[1::2]; buf = []
        elif cmd == "A" and len(buf) == 7:
            xs.append(buf[5]); ys.append(buf[6]); buf = []
    return min(xs), min(ys), max(xs), max(ys)


def circle_d(cx, cy, r):
    return f"M{cx - r} {cy} A{r} {r} 0 1 0 {cx + r} {cy} A{r} {r} 0 1 0 {cx - r} {cy} Z"


def ellipse_d(cx, cy, rx, ry):
    return f"M{cx - rx} {cy} A{rx} {ry} 0 1 0 {cx + rx} {cy} A{rx} {ry} 0 1 0 {cx - rx} {cy} Z"


def rect_d(x, y, w, h, rx):
    return (f"M{x + rx} {y} L{x + w - rx} {y} A{rx} {rx} 0 0 1 {x + w} {y + rx} L{x + w} {y + h - rx} "
            f"A{rx} {rx} 0 0 1 {x + w - rx} {y + h} L{x + rx} {y + h} A{rx} {rx} 0 0 1 {x} {y + h - rx} "
            f"L{x} {y + rx} A{rx} {rx} 0 0 1 {x + rx} {y} Z")


def to_vector_drawable(svg_path, out_path):
    root, vb = inner(svg_path)
    grads = {}
    for g in root.iter("{%s}linearGradient" % NS["s"]):
        stops = [(float(s.get("offset")), s.get("stop-color")) for s in g]
        grads[g.get("id")] = (float(g.get("x1")), float(g.get("y1")), float(g.get("x2")), float(g.get("y2")), stops)

    lines = []

    def emit_path(el, d, indent):
        fill = el.get("fill", "#000000")
        fa = float(el.get("fill-opacity", "1"))
        stroke, sw = el.get("stroke"), el.get("stroke-width")
        sa = float(el.get("stroke-opacity", "1"))
        attrs = [f'android:pathData="{d}"']
        if stroke:
            # VectorDrawable's strokeColor does not accept the SVG url(#gradient) form
            # used for the motorcycle's metallic fork highlight. Resolve it to the
            # final gradient stop as a stable solid-color approximation on Android.
            if stroke.startswith("url("):
                gid = stroke[5:-1]
                if gid not in grads or not grads[gid][4]:
                    raise SystemExit(f"unknown stroke gradient {gid!r} in {svg_path}")
                stroke = grads[gid][4][-1][1]
            attrs.append(f'android:strokeColor="{argb(stroke, sa)}"')
            attrs.append(f'android:strokeWidth="{sw}"')
            if el.get("stroke-linecap"):
                attrs.append(f'android:strokeLineCap="{el.get("stroke-linecap")}"')
        pad = " " * indent
        if fill.startswith("url("):
            gid = fill[5:-1]
            x1, y1, x2, y2, stops = grads[gid]
            bx0, by0, bx1, by1 = bbox(d)
            w, h = bx1 - bx0, by1 - by0
            lines.append(f"{pad}<path " + " ".join(attrs) + ">")
            lines.append(f'{pad}    <aapt:attr name="android:fillColor">')
            lines.append(f'{pad}        <gradient android:type="linear" android:startX="{bx0 + x1 * w:.2f}" '
                         f'android:startY="{by0 + y1 * h:.2f}" android:endX="{bx0 + x2 * w:.2f}" android:endY="{by0 + y2 * h:.2f}">')
            for off, col in stops:
                lines.append(f'{pad}            <item android:offset="{off}" android:color="{argb(col, fa)}"/>')
            lines.append(f"{pad}        </gradient>")
            lines.append(f"{pad}    </aapt:attr>")
            lines.append(f"{pad}</path>")
        else:
            if fill != "none":
                attrs.append(f'android:fillColor="{argb(fill, fa)}"')
            lines.append(f"{pad}<path " + " ".join(attrs) + "/>")

    def walk(node, indent):
        for el in node:
            tag = el.tag.split("}")[1]
            if tag == "defs":
                continue
            if tag == "g":
                tr = el.get("transform")
                if tr:
                    m = re.match(r"translate\(([-\d.]+) ([-\d.]+)\) scale\(([-\d.]+)\)", tr)
                    tx, ty, s = m.groups()
                    lines.append(f'{" " * indent}<group android:translateX="{tx}" android:translateY="{ty}" '
                                 f'android:scaleX="{s}" android:scaleY="{s}">')
                    walk(el, indent + 4)
                    lines.append(f'{" " * indent}</group>')
                else:
                    walk(el, indent)
            elif tag == "path":
                emit_path(el, el.get("d"), indent)
            elif tag == "circle":
                emit_path(el, circle_d(float(el.get("cx")), float(el.get("cy")), float(el.get("r"))), indent)
            elif tag == "ellipse":
                emit_path(el, ellipse_d(*(float(el.get(k)) for k in ("cx", "cy", "rx", "ry"))), indent)
            elif tag == "rect":
                emit_path(el, rect_d(*(float(el.get(k, "0")) for k in ("x", "y", "width", "height", "rx"))), indent)
            else:
                raise SystemExit(f"unsupported element <{tag}> in {svg_path}")

    # Normalise the viewBox origin to 0,0 for VectorDrawable.
    x0, y0, w, h = vb
    if x0 or y0:
        lines.append(f'    <group android:translateX="{-x0}" android:translateY="{-y0}">')
        walk(root, 8)
        lines.append("    </group>")
    else:
        walk(root, 4)
    body = "\n".join(lines)
    xml = (f'<?xml version="1.0" encoding="utf-8"?>\n'
           f'<!-- Generated by design/artwork/build_assets.py from the matching .svg. Do not edit by hand. -->\n'
           f'<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
           f'    xmlns:aapt="http://schemas.android.com/aapt"\n'
           f'    android:width="{w:g}dp" android:height="{h:g}dp"\n'
           f'    android:viewportWidth="{w:g}" android:viewportHeight="{h:g}">\n{body}\n</vector>\n')
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(xml)


def to_ios_pdf(svg_path, name):
    folder = os.path.join(IOS_ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    subprocess.run(["rsvg-convert", "-f", "pdf", "-o", os.path.join(folder, f"{name}.pdf"), svg_path], check=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        f.write('{\n  "images" : [\n    {\n      "filename" : "%s.pdf",\n      "idiom" : "universal"\n    }\n  ],\n'
                '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  },\n'
                '  "properties" : {\n    "preserves-vector-representation" : true\n  }\n}\n' % name)


if __name__ == "__main__":
    build_duo()
    os.makedirs(ANDROID_DRAWABLE, exist_ok=True)
    for key, src in (("kj_car", "kherja_car.svg"), ("kj_moto", "kherja_moto.svg"), ("kj_duo", "kherja_duo.svg"),
                     ("kj_front", "kherja_front.svg")):
        to_vector_drawable(os.path.join(HERE, src), os.path.join(ANDROID_DRAWABLE, f"{key}.xml"))
        to_ios_pdf(os.path.join(HERE, src), key)
    print("ok")
