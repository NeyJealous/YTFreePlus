#!/usr/bin/env python3
import pathlib
import re
import urllib.request

SOURCE = "https://raw.githubusercontent.com/FOSWLY/vot.js/main/packages/shared/src/data/config.ts"
OUT = pathlib.Path("VOT/VOTGeneratedConfig.h")

text = urllib.request.urlopen(SOURCE, timeout=30).read().decode("utf-8")

def grab(name: str) -> str:
    pattern = rf'{name}:\s*"([^"]+)"'
    match = re.search(pattern, text, re.S)
    if not match:
        raise RuntimeError(f"Could not find {name} in {SOURCE}")
    return match.group(1)

def objc(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')

host = grab("host")
user_agent = grab("userAgent")
component = grab("componentVersion")
hmac = grab("hmac")

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(
    "#pragma once\n"
    f'#define VOT_GENERATED_HOST @"{objc(host)}"\n'
    f'#define VOT_GENERATED_USER_AGENT @"{objc(user_agent)}"\n'
    f'#define VOT_GENERATED_COMPONENT_VERSION @"{objc(component)}"\n'
    f'#define VOT_GENERATED_HMAC @"{objc(hmac)}"\n',
    encoding="utf-8",
)
print(f"Generated {OUT} from {SOURCE}")
