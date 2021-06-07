#!/usr/bin/env python3

import requests
import wget

models = [
    ("iPad11,6", "8GEN"),
    ("iPad8,9", "TECHPRO"),
    ("iPad7,11", "7GEN"),
    ("iPad7,5", "6GEN"),
    ("iPad6,11", "5GEN"),
    ("iPad5,3", "AIR2"),
    ("AppleTV5,3", "ATV")
]


for model, name in models:
    resp = requests.get(f"https://api.ipsw.me/v2.1/{model}/latest/url")
    url = resp.text
    wget.download(url, f"/Users/Shared/ipsw/{name}.ipsw")

