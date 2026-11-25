"""Convert the Android strings.xml (en + ar) into iOS Localizable.strings.
Usage: python scripts/gen_strings.py <android_res_dir>
"""
import re, sys, os
import xml.etree.ElementTree as ET

res = sys.argv[1]
out_root = os.path.join(os.path.dirname(__file__), "..", "Resources")

def convert(value: str) -> str:
    v = value.replace("\'", "'").replace('\\"', '"').replace("\n", "\n")
    v = re.sub(r"%(\d+)\$s", r"%\1$@", v)
    v = re.sub(r"(?<!%)%s", "%@", v)
    v = v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\n")
    return v

for lang, folder in (("en", "values"), ("ar", "values-ar")):
    tree = ET.parse(os.path.join(res, folder, "strings.xml"))
    lines = []
    for el in tree.getroot().iter("string"):
        text = "".join(el.itertext())
        lines.append('"%s" = "%s";' % (el.get("name"), convert(text)))
    d = os.path.join(out_root, f"{lang}.lproj")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "Localizable.strings"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(lang, len(lines))
