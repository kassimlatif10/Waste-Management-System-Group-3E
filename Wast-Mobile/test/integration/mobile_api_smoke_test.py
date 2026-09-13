#!/usr/bin/env python3
"""Smoke-test critical mobile API flows against production or staging."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


BASE = 'https://54.172.240.192/api'
PHONE = '0507659441'
PASSWORD = 'gifty123'


def curl(args: list[str]) -> str:
    cmd = ['curl', '-sk', '--max-time', '25', *args]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout


def make_png(path: Path) -> None:
    import struct
    import zlib

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)

    width = height = 16
    raw = b''.join(b'\x00' + bytes((46, 125, 50)) * width for _ in range(height))
    png = (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw))
        + chunk(b'IEND', b'')
    )
    path.write_bytes(png)


def main() -> int:
    failures: list[str] = []

    login = json.loads(
        curl([
            '-X', 'POST', f'{BASE}/auth/phone-login/',
            '-H', 'Content-Type: application/json',
            '-d', json.dumps({'phone': PHONE, 'password': PASSWORD}),
        ])
    )
    token = login['tokens']['access']
    auth = ['-H', f'Authorization: Bearer {token}']

    me = json.loads(curl([f'{BASE}/auth/me/', *auth]))
    if 'profile_image' not in me:
        failures.append('/auth/me missing profile_image field (deploy latest backend)')

    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / 'profile.png'
        make_png(png)
        upload = json.loads(
            curl([
                '-X', 'PATCH', f'{BASE}/customer/profile/update/',
                *auth,
                '-F', 'first_name=Gifty',
                '-F', f'profile_image=@{png};type=image/png',
            ])
        )
        if upload.get('profile_image') in (None, ''):
            profile = json.loads(curl([f'{BASE}/customer/profile/update/', *auth]))
            image_url = profile.get('profile_image')
        else:
            image_url = upload['profile_image']

    if not image_url:
        failures.append('profile upload did not return profile_image URL')
    else:
        code = curl(['-o', '/dev/null', '-w', '%{http_code}', image_url])
        if code.strip() != '200':
            failures.append(f'profile image URL not reachable: {image_url} ({code.strip()})')

    try:
        geo_raw = curl([f'{BASE}/geo/search/?q=Takoradi', *auth])
        geo = json.loads(geo_raw)
        if not geo.get('results'):
            failures.append('geo search returned no Google place results')
    except json.JSONDecodeError:
        failures.append('geo search endpoint missing on server — deploy latest backend')

    if failures:
        print('FAILED:')
        for item in failures:
            print(f' - {item}')
        return 1

    print('OK: profile upload + image URL + geo search')
    return 0


if __name__ == '__main__':
    sys.exit(main())
