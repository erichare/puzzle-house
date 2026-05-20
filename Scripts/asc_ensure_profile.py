#!/usr/bin/env python3
"""Ensure an App Store provisioning profile exists for a Puzzle House
target, via the App Store Connect REST API.

Why: xcodebuild's "automatic" signing in Xcode 26 silently picks the
wrong profile type (iOS App Development on a CI runner with no
registered devices) and fails the archive with "Your team has no
devices". The reliable workaround is to drop to manual signing and
pre-create the App Store profile via the API.

Puzzle House has four targets that each need their own provisioning
profile, selected by env `PLATFORM`:

  PLATFORM=IOS_APP             (default — the main app)
  PLATFORM=IOS_SHARE_EXTENSION
  PLATFORM=IOS_MESSAGES
  PLATFORM=IOS_WIDGET

Common env (all flavors):
  AC_API_KEY_ID         — ASC API key id (10-char)
  AC_API_ISSUER_ID      — issuer UUID
  AC_API_KEY_P8_PATH    — path to the .p8 private key on disk
  ASC_CERT_SERIAL_NUMBER — optional local Apple Distribution cert serial;
                          when set, the ASC certificate must match it

Output:
  stdout — three lines:
             line 1: the profile name
             line 2: absolute path to the .mobileprovision on disk
             line 3: the profile UUID

Side effect:
  Writes the .mobileprovision into
  ~/Library/MobileDevice/Provisioning Profiles/<UUID>.mobileprovision
"""
from __future__ import annotations

import base64
import json
import os
import plistlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

try:
    import jwt
except ImportError:
    sys.exit("error: pip install pyjwt cryptography")


API = "https://api.appstoreconnect.apple.com/v1"


@dataclass(frozen=True)
class Flavor:
    """Per-target settings: profile type, cert type, bundle id env var,
    and a default profile name if PROFILE_NAME isn't overridden."""

    label: str
    profile_type: str
    cert_type: str
    bundle_env_var: str
    bundle_platform: str
    default_profile_name: str


FLAVORS: dict[str, Flavor] = {
    "IOS_APP": Flavor(
        label="Puzzle House iOS App Store",
        profile_type="IOS_APP_STORE",
        cert_type="DISTRIBUTION",
        bundle_env_var="IOS_APP_BUNDLE_ID",
        bundle_platform="IOS",
        default_profile_name="Puzzle House iOS App Store",
    ),
    "IOS_SHARE_EXTENSION": Flavor(
        label="Puzzle House Share Extension App Store",
        profile_type="IOS_APP_STORE",
        cert_type="DISTRIBUTION",
        bundle_env_var="IOS_SHARE_EXTENSION_BUNDLE_ID",
        bundle_platform="IOS",
        default_profile_name="Puzzle House Share Extension App Store",
    ),
    "IOS_MESSAGES": Flavor(
        label="Puzzle House Messages Extension App Store",
        profile_type="IOS_APP_STORE",
        cert_type="DISTRIBUTION",
        bundle_env_var="IOS_MESSAGES_BUNDLE_ID",
        bundle_platform="IOS",
        default_profile_name="Puzzle House Messages App Store",
    ),
    "IOS_WIDGET": Flavor(
        label="Puzzle House Widget App Store",
        profile_type="IOS_APP_STORE",
        cert_type="DISTRIBUTION",
        bundle_env_var="IOS_WIDGET_BUNDLE_ID",
        bundle_platform="IOS",
        default_profile_name="Puzzle House Widget App Store",
    ),
}


def jwt_token() -> str:
    """Build a 10-minute JWT for the ASC API."""
    key_id = os.environ["AC_API_KEY_ID"]
    issuer = os.environ["AC_API_ISSUER_ID"]
    key_path = os.environ["AC_API_KEY_P8_PATH"]
    with open(key_path, "rb") as f:
        key = f.read()
    return jwt.encode(
        {"iss": issuer, "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def _query(params: dict[str, str]) -> str:
    return "&".join(
        f"{k}={urllib.parse.quote(str(v), safe='')}" for k, v in params.items()
    )


def request(method: str, path: str, body: dict | None = None) -> dict:
    token = jwt_token()
    url = path if path.startswith("https://") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            text = r.read().decode("utf-8")
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        sys.stderr.write(
            f"ASC API {method} {path} -> {e.code}\n"
            f"  body: {e.read().decode('utf-8', 'ignore')[:600]}\n"
        )
        raise


def find_bundle_id_resource(bundle_id: str, platform: str) -> str:
    """Return the ASC resource id for our bundle id. Creates if missing
    (requires Admin role on the API key). If creation is forbidden, exits
    with a precise developer-portal URL the maintainer should visit."""
    res = request(
        "GET",
        "/bundleIds?" + _query({"filter[identifier]": bundle_id, "limit": 200}),
    )
    for entry in (res.get("data") or []):
        if (entry.get("attributes") or {}).get("identifier") == bundle_id:
            return entry["id"]

    sys.stderr.write(f"    bundleId {bundle_id} not registered — creating ({platform})\n")
    try:
        res = request(
            "POST",
            "/bundleIds",
            body={
                "data": {
                    "type": "bundleIds",
                    "attributes": {
                        "identifier": bundle_id,
                        "name": bundle_id.replace(".", " "),
                        "platform": platform,
                    },
                }
            },
        )
    except urllib.error.HTTPError as e:
        if e.code == 403:
            sys.exit(
                "\n"
                "  ⚠️  ASC API rejected POST /v1/bundleIds with 403 FORBIDDEN.\n"
                "\n"
                f"  Bundle id '{bundle_id}' isn't registered, and your ASC API\n"
                "  key can't create one (needs Admin role).\n"
                "\n"
                "  Register it manually, once:\n"
                "    https://developer.apple.com/account/resources/identifiers/list/bundleId\n"
                "    • '+' → App IDs → App\n"
                f"    • Description: 'Puzzle House {platform}'\n"
                "    • Bundle ID: Explicit\n"
                f"    • Identifier: '{bundle_id}'\n"
                "    • Capabilities: enable iCloud + App Groups +\n"
                "      Push Notifications (and attach the\n"
                "      iCloud.com.jestats.PuzzleHouse container)\n"
                "\n"
                "  Then re-run; the script's GET path will pick it up.\n"
            )
        raise
    return res["data"]["id"]


def find_certificate_id(cert_type: str) -> str:
    res = request(
        "GET",
        "/certificates?" + _query({"filter[certificateType]": cert_type, "limit": 200}),
    )
    data = res.get("data") or []
    if not data:
        sys.exit(
            f"error: no {cert_type} certificate found on the team.\n"
            "  Create one once via Xcode → Settings → Accounts → Manage\n"
            "  Certificates → '+' → 'Apple Distribution', then re-run."
        )

    expected_serial = normalized_serial(os.environ.get("ASC_CERT_SERIAL_NUMBER"))
    if expected_serial:
        for cert in data:
            attrs = cert.get("attributes") or {}
            if normalized_serial(attrs.get("serialNumber")) == expected_serial:
                return cert["id"]

        found = ", ".join(
            normalized_serial((cert.get("attributes") or {}).get("serialNumber"))
            or "<missing>"
            for cert in data
        )
        sys.exit(
            f"error: no {cert_type} certificate in ASC matches local serial "
            f"{expected_serial}.\n"
            f"  ASC returned serials: {found}\n"
            "  Re-export the Apple Distribution .p12 from the certificate "
            "shown in developer.apple.com, or revoke the stale cert/profile."
        )
    return data[0]["id"]


def normalized_serial(serial: str | None) -> str:
    hex_serial = "".join(ch for ch in (serial or "").upper() if ch in "0123456789ABCDEF")
    return hex_serial.lstrip("0") or ("0" if hex_serial else "")


def find_or_create_profile(
    name: str,
    profile_type: str,
    bundle_id_resource: str,
    cert_id: str,
) -> tuple[str, str]:
    res = request("GET", "/profiles?" + _query({"filter[name]": name, "limit": 10}))
    stale_same_name_profile = False
    for p in res.get("data") or []:
        attrs = p.get("attributes", {})
        if (
            attrs.get("name") == name
            and attrs.get("profileType") == profile_type
            and attrs.get("profileState") == "ACTIVE"
        ):
            profile_id = p["id"]
            if profile_matches(profile_id, bundle_id_resource, cert_id):
                return name, profile_id
            sys.stderr.write(
                f"    profile {name!r} ({profile_id}) is active but tied to "
                "a different bundle id or certificate — creating a fresh one\n"
            )
            stale_same_name_profile = True

    if stale_same_name_profile:
        scoped_name = profile_name_for_certificate(name, cert_id)
        res = request("GET", "/profiles?" + _query({"filter[name]": scoped_name, "limit": 10}))
        for p in res.get("data") or []:
            attrs = p.get("attributes", {})
            if (
                attrs.get("name") == scoped_name
                and attrs.get("profileType") == profile_type
                and attrs.get("profileState") == "ACTIVE"
            ):
                profile_id = p["id"]
                if profile_matches(profile_id, bundle_id_resource, cert_id):
                    return scoped_name, profile_id
        sys.stderr.write(f"    using cert-specific profile name {scoped_name!r}\n")
        name = scoped_name

    sys.stderr.write(f"    profile {name!r} ({profile_type}) missing — creating\n")
    try:
        res = request(
            "POST",
            "/profiles",
            body={
                "data": {
                    "type": "profiles",
                    "attributes": {"name": name, "profileType": profile_type},
                    "relationships": {
                        "bundleId": {
                            "data": {"type": "bundleIds", "id": bundle_id_resource}
                        },
                        "certificates": {
                            "data": [{"type": "certificates", "id": cert_id}]
                        },
                    },
                }
            },
        )
    except urllib.error.HTTPError as e:
        if e.code == 403:
            sys.exit(
                "\n"
                "  ⚠️  ASC API rejected POST /v1/profiles with 403 FORBIDDEN.\n"
                "\n"
                "  Profile creation requires the Admin role on the API key.\n"
                "\n"
                "  (a) FAST — pre-create the profile manually, once:\n"
                f"      • https://developer.apple.com/account/resources/profiles/add\n"
                f"      • Type matching {profile_type} (e.g. Distribution → App Store)\n"
                f"      • App ID: the bundle id this script just used\n"
                "      • Certificate: your Apple Distribution cert\n"
                f"      • Profile Name: '{name}'  (must match exactly)\n"
                "\n"
                "  (b) PROPER — recreate the ASC API key with Admin role:\n"
                "      https://appstoreconnect.apple.com/access/integrations/api\n"
                "      Generate API Key → Access: Admin → download .p8\n"
                "      Update GitHub secrets AC_API_KEY_ID and AC_API_KEY_P8_BASE64.\n"
            )
        raise
    return name, res["data"]["id"]


def profile_matches(profile_id: str, bundle_id_resource: str, cert_id: str) -> bool:
    bundle = request("GET", f"/profiles/{profile_id}/relationships/bundleId")
    if ((bundle.get("data") or {}).get("id")) != bundle_id_resource:
        return False
    certs = request("GET", f"/profiles/{profile_id}/relationships/certificates")
    return any(cert.get("id") == cert_id for cert in certs.get("data") or [])


def profile_name_for_certificate(base_name: str, cert_id: str) -> str:
    serial = normalized_serial(os.environ.get("ASC_CERT_SERIAL_NUMBER"))
    suffix = (serial[-8:] if serial else cert_id[:8]).upper()
    return f"{base_name} {suffix}"


def download_profile(profile_id: str) -> tuple[str, str]:
    res = request("GET", f"/profiles/{profile_id}")
    content_b64 = res["data"]["attributes"]["profileContent"]
    raw = base64.b64decode(content_b64)

    uuid = parse_uuid(raw)
    dest_dir = Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles"
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / f"{uuid}.mobileprovision"
    dest.write_bytes(raw)
    return str(dest), uuid


def parse_uuid(raw: bytes) -> str:
    start = raw.find(b"<?xml")
    end = raw.find(b"</plist>")
    if start < 0 or end < 0:
        sys.exit("error: profile bytes don't contain an XML plist")
    plist = plistlib.loads(raw[start : end + len(b"</plist>")])
    uuid = plist.get("UUID")
    if not uuid:
        sys.exit("error: profile plist has no UUID")
    return uuid


def main() -> int:
    platform = (os.environ.get("PLATFORM") or "IOS_APP").upper()
    if platform not in FLAVORS:
        sys.exit(
            f"error: PLATFORM must be one of {sorted(FLAVORS)}, got {platform!r}"
        )
    flavor = FLAVORS[platform]

    bundle_id = os.environ.get(flavor.bundle_env_var)
    if not bundle_id:
        sys.exit(f"error: {flavor.bundle_env_var} env var not set")
    profile_name = os.environ.get("PROFILE_NAME") or flavor.default_profile_name

    sys.stderr.write(
        f"==> Ensuring {flavor.label} profile {profile_name!r} for {bundle_id}\n"
    )

    bundle_resource = find_bundle_id_resource(bundle_id, flavor.bundle_platform)
    sys.stderr.write(f"    bundleId resource: {bundle_resource}\n")

    cert_id = find_certificate_id(flavor.cert_type)
    sys.stderr.write(f"    {flavor.cert_type} cert: {cert_id}\n")

    name, profile_id = find_or_create_profile(
        profile_name, flavor.profile_type, bundle_resource, cert_id
    )
    sys.stderr.write(f"    profile: {name} ({profile_id})\n")

    dest, uuid = download_profile(profile_id)
    sys.stderr.write(f"    installed: {dest}\n")

    print(name)
    print(dest)
    print(uuid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
