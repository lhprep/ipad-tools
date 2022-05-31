from pprint import pprint

import magic

import os
import sys
import shutil

bkp = sys.argv[1]

types = []
i = 0

for root, dirs, files in os.walk(bkp):
    for file in files:
        path = root + "/" + file

        type = magic.from_file(path)

        if "PNG" in type:
            shutil.copy(path, f"./out/{i}.png")
            i += 1
            continue

        if "JPG" in type or "JPEG" in type:
            shutil.copy(path, f"./out/{i}.jpeg")
            i += 1
            continue

        if "GIF" in type:
            shutil.copy(path, f"./out/{i}.gif")
            i += 1
            continue

        if "Web/P" in type:
            shutil.copy(path, f"./out/{i}.webp")
            i += 1
            continue

        if ".MOV" in type:
            shutil.copy(path, f"./out/{i}.mov")
            i += 1
            continue

        if "MP4" in type:
            shutil.copy(path, f"./out/{i}.mp4")
            i += 1
            continue

        if "HEVC" in type:
            shutil.copy(path, f"./out/{i}.heic")
            i += 1
            continue

        if "M4A" in type:
            shutil.copy(path, f"./out/{i}.m4a")
            i += 1
            continue

        if "PDF" in type:
            shutil.copy(path, f"./out/{i}.pdf")
            i += 1
            continue

        if "Zip" in type:
            shutil.copy(path, f"./out/{i}.zip")
            i += 1
            continue

        if "SQLite" in type or "Unicode" in type or "ASCII" in type or "HTML" in type or "JSON" in type\
                or "property list" in type or "Matlab" in type or "font" in type.lower() or "no magic" in type:
            continue

        if type not in types:
            types.append(type)

pprint(types)
print(f"Found {i} files. Missing formats are above. ")
