#!/usr/bin/env python3
"""Idempotent mobile camera/privacy setup after Flutter scaffolding generation."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
android = root / "android/app/src/main/AndroidManifest.xml"
if android.exists():
    data = android.read_text()
    if "android.permission.CAMERA" not in data:
        data = data.replace(
            "<application",
            '<uses-permission android:name="android.permission.CAMERA" />\n'
            '    <uses-feature android:name="android.hardware.camera.front" '
            'android:required="false" />\n'
            "    <application",
            1,
        )
    android.write_text(data)

info = root / "ios/Runner/Info.plist"
if info.exists():
    data = info.read_text()
    if "NSCameraUsageDescription" not in data:
        data = data.replace(
            "</dict>",
            "    <key>NSCameraUsageDescription</key>\n"
            "    <string>HOTICE uses your selfie camera to capture "
            "consented face-reference photos locally.</string>\n"
            "</dict>",
            1,
        )
    info.write_text(data)

pod = root / "ios/Podfile"
if pod.exists():
    data = pod.read_text()
    rule = r"^\s*#?\s*platform\s+:ios\s*,\s*['\"][^'\"]+['\"]"
    if re.search(rule, data, re.MULTILINE):
        data = re.sub(rule, "platform :ios, '15.5'", data,
                      count=1, flags=re.MULTILINE)
    else:
        data = "platform :ios, '15.5'\n" + data
    pod.write_text(data)

xcode = root / "ios/Runner.xcodeproj/project.pbxproj"
if xcode.exists():
    data = xcode.read_text()
    data = re.sub(
        r"IPHONEOS_DEPLOYMENT_TARGET = (?:[0-9]+\.)+[0-9]+;",
        "IPHONEOS_DEPLOYMENT_TARGET = 15.5;",
        data,
    )
    xcode.write_text(data)
print("Configured Android camera permission and iOS minimum 15.5.")
