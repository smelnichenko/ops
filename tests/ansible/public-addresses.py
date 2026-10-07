#!/usr/bin/env python3
"""public-addresses.py <name> - the name's public IPv4 addresses, as a public resolver (1.1.1.1) answers: every A
record, space-separated. The Vagrant isolation drops them and proves them unreachable (isolate-pis.yml,
upgrade/isolate-cluster.yml). Refuses (exit 1) when nothing answers or any answer is not a global address: a resolver
that answers the LAN's address (a router intercepting DNS) made the proof drop an address dropped already and probe it
- "blocked", with the public one still reachable."""
import ipaddress
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    name = sys.argv[1]
    r = subprocess.run(["dig", "+short", "@1.1.1.1", name, "A"], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"REFUSED: dig failed for {name} (exit {r.returncode}): {r.stderr.strip()}")
    addresses = []
    for line in r.stdout.split():
        try:
            address = ipaddress.IPv4Address(line)
        except ValueError:
            continue  # a CNAME on the way
        if not address.is_global:  # production's LAN (private) among them
            sys.exit(f"REFUSED: {name} read as {address} from 1.1.1.1 - not a public address (DNS intercepted?)")
        addresses.append(str(address))
    if not addresses:
        sys.exit(f"REFUSED: no A record for {name} from 1.1.1.1")
    print(" ".join(addresses))


if __name__ == "__main__":
    main()
