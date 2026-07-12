#!/usr/bin/env python3
"""Verify demo-user can list DEMO templates in portal after OAuth login."""
import json
import re
import subprocess
import sys
import urllib.parse

PORTAL = sys.argv[1] if len(sys.argv) > 1 else (
    "redhat-rhaap-portal-rhaap-portal.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com"
)
USER = sys.argv[2] if len(sys.argv) > 2 else "demo-user"
PASSWORD = sys.argv[3] if len(sys.argv) > 3 else ""

ROUTER_IP = subprocess.check_output(
    ["dig", "+short", "router-default.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com"],
    text=True,
).splitlines()[0]
RESOLVE = ["--resolve", f"{PORTAL}:443:{ROUTER_IP}"]
JAR = "/tmp/verify-portal-oauth-cookies.txt"


def curl(args, *, write_body=None):
    cmd = ["curl", "-sk", "-c", JAR, "-b", JAR, *RESOLVE, *args]
    if write_body is not None:
        cmd.extend(["-o", write_body])
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def main() -> int:
    if not PASSWORD:
        print("Set demo-user password as third argument", file=sys.stderr)
        return 2

    subprocess.run(["rm", "-f", JAR], check=False)

    start = curl(
        [
            "-D",
            "-",
            "-o",
            "/dev/null",
            f"https://{PORTAL}/api/auth/rhaap/start?scope=openid%20profile%20email%20offline_access"
            f"&origin=https%3A%2F%2F{PORTAL}%2F&flow=popup&env=production",
        ]
    )
    match = re.search(r"location:\s*(\S+)", start.stdout, re.I)
    if not match:
        print("OAuth start failed:", start.stdout[:400], file=sys.stderr)
        return 1
    auth_url = match.group(1)

    login_page = curl([auth_url], write_body="/tmp/portal-login.html")
    html = open("/tmp/portal-login.html").read()

    csrf_match = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', html)
    if not csrf_match:
        # Gateway may redirect to another login host
        follow = subprocess.run(
            ["curl", "-sk", "-L", "-c", JAR, "-b", JAR, *RESOLVE, "-o", "/tmp/portal-login.html", auth_url],
            capture_output=True,
            text=True,
        )
        html = open("/tmp/portal-login.html").read()
        csrf_match = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', html)

    if csrf_match:
        csrf = csrf_match.group(1)
        action_match = re.search(r'<form[^>]+action="([^"]+)"', html)
        action = action_match.group(1) if action_match else auth_url.replace("/authorize/", "/login/")
        if action.startswith("/"):
            action = "https://aap-aap.apps.cluster-jmvv9.jmvv9.sandbox3400.opentlc.com" + action
        payload = (
            f"csrfmiddlewaretoken={urllib.parse.quote(csrf)}"
            f"&username={urllib.parse.quote(USER)}"
            f"&password={urllib.parse.quote(PASSWORD)}"
            f"&next="
        )
        curl(["-L", "-X", "POST", "-d", payload, action])

    refresh = curl(
        [
            "-X",
            "POST",
            f"https://{PORTAL}/api/auth/rhaap/refresh?env=production",
            "-H",
            "Content-Type: application/json",
            "-H",
            "X-Requested-With: XMLHttpRequest",
            "-d",
            "{}",
        ]
    )
    try:
        data = json.loads(refresh.stdout)
    except json.JSONDecodeError:
        print("Refresh failed:", refresh.stdout[:500], file=sys.stderr)
        return 1

    token = (
        data.get("backstageIdentity", {}).get("token")
        or data.get("providerInfo", {}).get("accessToken")
        or data.get("token")
    )
    if not token:
        print("No backstage token:", json.dumps(data, indent=2)[:800], file=sys.stderr)
        return 1

    catalog = curl(
        [
            "-H",
            f"Authorization: Bearer {token}",
            f"https://{PORTAL}/api/catalog/entities?filter=kind=template",
        ]
    )
    try:
        entities = json.loads(catalog.stdout)
    except json.JSONDecodeError:
        print("Catalog query failed:", catalog.stdout[:500], file=sys.stderr)
        return 1

    names = sorted(e.get("metadata", {}).get("name", "?") for e in entities)
    demo = [n for n in names if "demo" in n.lower()]
    print(f"demo-user catalog templates: {len(names)} total, {len(demo)} DEMO-like")
    for name in names:
        print(f"  - {name}")

    if len(demo) < 6:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
