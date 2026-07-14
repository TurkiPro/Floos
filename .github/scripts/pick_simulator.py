#!/usr/bin/env python3
"""Pick the best iPhone simulator available on this runner.

Never hard-code a simulator name in the workflow: which iPhones exist depends on
the Xcode baked into the runner image, and that image moves. `macos-latest`
rolled to macOS 26 mid-flight, the iPhone 16 family disappeared, and a
hard-coded preference list matched nothing at all.

So ask the runner what it actually has and rank it: newest model first, then
Pro Max > Plus > Pro > base. That is Apple's primary screenshot slot (the
biggest iPhone), and it keeps working across image bumps.

Reads `xcrun simctl list devices available -j` on stdin.
Prints "<udid>\t<name>" on success; exits 1 if there is no iPhone at all.
"""

import json
import re
import sys


def main() -> int:
    devices = json.load(sys.stdin)["devices"]

    candidates = []
    for runtime, devs in devices.items():
        # Skip watchOS / visionOS / tvOS runtimes.
        if "iOS" not in runtime:
            continue
        for dev in devs:
            name = dev["name"]
            if not name.startswith("iPhone"):
                continue

            match = re.search(r"iPhone (\d+)", name)
            model = int(match.group(1)) if match else 0

            if "Pro Max" in name:
                size = 3
            elif "Plus" in name:
                size = 2
            elif "Pro" in name:
                size = 1
            else:
                size = 0

            candidates.append((model, size, name, dev["udid"]))

    if not candidates:
        print("No iPhone simulator found in the available device list.",
              file=sys.stderr)
        return 1

    candidates.sort(reverse=True)
    _, _, name, udid = candidates[0]
    print(f"{udid}\t{name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
