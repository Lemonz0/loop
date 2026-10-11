"""Check the built app's CallKit modes and privacy descriptions before shipping."""
import plistlib
import sys
from pathlib import Path

with Path(sys.argv[1]).open("rb") as source:
    info = plistlib.load(source)

modes = set(info.get("UIBackgroundModes", []))
missing = {"audio", "voip"} - modes
if missing:
    sys.exit("Missing required calling background modes: " + ", ".join(sorted(missing)))
for key in ("NSMicrophoneUsageDescription", "NSCameraUsageDescription"):
    if not isinstance(info.get(key), str) or not info[key].strip():
        sys.exit("Missing calling privacy description: " + key)
print("Archived app has CallKit background modes and calling privacy descriptions.")
