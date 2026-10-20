#!/usr/bin/env python3
"""Marks the exported Xcode project as iPhone-device-only (the template's simulator library has no arm64 code)."""
import pathlib

Path = pathlib.Path(__file__).parent / "XBoardTest.xcodeproj" / "project.pbxproj"
Text = Path.read_text()
if "SUPPORTED_PLATFORMS" not in Text:
    Text = Text.replace("SDKROOT = iphoneos;", "SDKROOT = iphoneos;\n\t\t\t\tSUPPORTED_PLATFORMS = iphoneos;")
    Path.write_text(Text)
    print("patched")
else:
    print("already patched")
