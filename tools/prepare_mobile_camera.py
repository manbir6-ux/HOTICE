#!/usr/bin/env python3
"""Idempotently configure generated Flutter platform scaffolds for HOTICE.
The repository generates Android/iOS projects in CI, so these changes must
be re-applied every time. Never request microphone permission for stills.
"""
from pathlib import Path
import re

manifest = Path("android/app/src/main/AndroidManifest.xml")
if manifest.exists():
    raw = manifest.read_text()
    if 'android.permission.CAMERA' not in raw:
        raw = re.sub(r'(<manifest[^>]*>)',
            lambda m: m.group(1) + '\n    <uses-permission android:name="android.permission.CAMERA" />',
            raw, count=1)
    if 'android:allowBackup=' not in raw:
        raw = re.sub(r'<application\b',
            '<application android:allowBackup="false"', raw, count=1)
    manifest.write_text(raw)

gradle = Path("android/app/build.gradle.kts")
if gradle.exists():
    raw = gradle.read_text()
    raw = raw.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
    gradle.write_text(raw)

plist = Path("ios/Runner/Info.plist")
if plist.exists():
    raw = plist.read_text()
    if 'NSCameraUsageDescription' not in raw:
        raw = raw.replace('<dict>', '<dict>\n\t<key>NSCameraUsageDescription</key>\n\t<string>HOTICE uses the front camera for guided, on-device Actor photo capture when you choose to start it.</string>', 1)
    plist.write_text(raw)

podfile = Path("ios/Podfile")
if podfile.exists():
    raw = podfile.read_text()
    raw = re.sub(r"^#?\s*platform :ios, ['\"][^'\"]+['\"]", "platform :ios, '15.5'", raw, count=1, flags=re.M)
    if "platform :ios, '15.5'" not in raw:
        raw = "platform :ios, '15.5'\n" + raw
    podfile.write_text(raw)

print("HOTICE Android camera permission/SDK and iOS permission/target configured.")
