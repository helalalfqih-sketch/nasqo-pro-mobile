#!/usr/bin/env python3
"""Verify a signed QA Release shows one React WebView and no native Flutter
navigation chrome. Run only on an empty Android emulator; never a user phone."""
import json
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET

out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "qa-release-evidence")
out.mkdir(parents=True, exist_ok=True)
subprocess.run(["adb", "shell", "uiautomator", "dump", "/sdcard/nasqo-release-ui.xml"],
               check=True, capture_output=True, timeout=35)
xml = subprocess.run(["adb", "exec-out", "cat", "/sdcard/nasqo-release-ui.xml"],
                     check=True, capture_output=True, timeout=20).stdout
(out / "android-UI-hierarchy.xml").write_bytes(xml)
root = ET.fromstring(xml)
webviews = []
outside = []

def visit(node, in_webview=False):
    clazz = node.attrib.get("class", "")
    inside = in_webview or clazz == "android.webkit.WebView"
    if clazz == "android.webkit.WebView":
        webviews.append(node)
    if not inside:
        outside.append(node)
    for child in node:
        visit(child, inside)

visit(root)
if len(webviews) != 1:
    raise AssertionError(f"Expected a single React WebView, found {len(webviews)}")
native_nav_labels = {
    "الرئيسية", "الخدمات", "التقارير", "الإعدادات",
    "الملف الشخصي", "القائمة", "فتح القائمة",
}
bad = []
for node in outside:
    labels = [node.attrib.get("text", "").strip(),
              node.attrib.get("content-desc", "").strip()]
    if any(label in native_nav_labels for label in labels):
        bad.append({"class": node.attrib.get("class"), "labels": labels})
if bad:
    raise AssertionError(f"Duplicate native navigation outside React WebView: {bad}")
report = {
    "react_webview_count": len(webviews),
    "duplicate_native_navigation": bad,
    "checked_outside_nodes": len(outside),
    "one_react_surface": True,
}
(out / "react-only-navigation.json").write_text(
    json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("PASS: Single React WebView; no native Flutter navigation outside it", flush=True)
