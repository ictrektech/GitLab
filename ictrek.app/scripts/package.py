#!/usr/bin/env python3
"""Render and verify a VOS pull package using the recorded profile images."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

import yaml

ROOT = Path(__file__).resolve().parents[2]


def validate_routers(text):
    routes = yaml.safe_load(text).get('routers', [])
    if len(routes) != 1 or routes[0].get('kind') != 'page' or routes[0].get('id') != 'gitlab' or routes[0].get('children'):
        raise ValueError('GitLab must expose one root page under the VOS application wrapper')
    page = routes[0]
    if page.get('iframe-src') != '/app/com.ictrek.gitlab/-/vos/app' or not page.get('entry-point') or not page.get('embed'):
        raise ValueError('The GitLab page must open the VOS integration shell')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--images-env', type=Path, help='Use a previously resolved Feishu .env file')
    args = parser.parse_args()
    version = os.environ.get('PACKAGE_VERSION', (ROOT / 'ictrek.app/VERSION').read_text().strip())
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?', version):
        parser.error('Invalid package version')
    output = Path.home() / 'dev/build/gitlab/packages' / version
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='stage-', dir=output) as temporary:
        stage = Path(temporary)
        if args.images_env:
            (stage / '.env').write_bytes(args.images_env.read_bytes())
        else:
            subprocess.run(['python3', str(ROOT / 'ictrek.app/scripts/resolve_feishu_images.py'),
                            '--output', str(stage / '.env')], check=True)
        images = dict(line.split('=', 1) for line in (stage / '.env').read_text().splitlines() if line.strip())
        for profile in ('AMD', 'ARM'):
            image = images[f'GITLAB_{profile}_IMAGE']
            if not re.fullmatch(r'swr\.cn-southwest-2\.myhuaweicloud\.com/ictrek/gitlab:' + profile.lower() + r'_[\w.-]+', image):
                raise SystemExit(f'Invalid image for profile {profile}')
        for source in (ROOT / 'ictrek.app/src').iterdir():
            destination = stage / source.name
            if source.suffix == '.png':
                destination.write_bytes(source.read_bytes())
                continue
            text = source.read_text().replace('__APP_VERSION__', version)
            if source.name == 'docker-compose.yml':
                for name, image in images.items():
                    text = text.replace('${' + name + '}', image)
            if re.search(r'__[A-Z0-9_]+__|\$\{[^}]*_IMAGE\}', text):
                raise SystemExit(f'Unresolved template in {source.name}')
            destination.write_text(text)
        subprocess.run(['python3', str(ROOT / 'ictrek.app/scripts/resolve_dependencies.py'),
                        str(stage / 'manifest.yml'), '--repositories',
                        str(ROOT / 'ictrek.app/dependencies.json')], check=True)
        validate_routers((stage / 'routers.yml').read_text())
        configs = yaml.safe_load((stage / 'configs.yml').read_text())['configs']
        for item in configs:
            for field in ('title', 'description'):
                value = item[field]
                if not isinstance(value, str) and (not isinstance(value, dict) or
                        not value or not all(isinstance(text, str) for text in value.values())):
                    raise SystemExit(f"Invalid localized {field} in {item['name']}")
        external_url = next(item for item in configs if item['name'] == 'GITLAB_EXTERNAL_URL')
        if 'default' in external_url or external_url.get('minLength', 0) < 1:
            raise SystemExit('The external HTTPS URL must be required during installation')
        paths = [item['name'] for item in configs if item['type'] == 'path']
        if paths != ['GITLAB_DATA_PATH']:
            raise SystemExit('Only the Data directory should have a user-selectable path')
        compose = (stage / 'docker-compose.yml').read_text()
        if 'runtime:' in compose or 'nvidia' in compose:
            raise SystemExit('GitLab CPU profiles must not require NVIDIA runtime')
        for profile in ('amd', 'arm'):
            validation_env = {**os.environ, 'GITLAB_EXTERNAL_URL': 'https://vos.example.com:1180/app/com.ictrek.gitlab',
                              'GITLAB_DATA_PATH': '/data/gitlab-package-check/data',
                              'VOS_APP_STORAGE_PATH': '/data/gitlab-package-check/managed',
                              'VOS_POSTGRES_PASSWORD': 'package-validation-placeholder'}
            subprocess.run(['docker', 'compose', '-f', str(stage / 'docker-compose.yml'),
                            '--profile', profile, 'config', '--quiet'], env=validation_env, check=True)
        inner = output / 'app.tar.gz'
        with tarfile.open(inner, 'w:gz') as archive:
            for source in sorted(stage.iterdir()):
                archive.add(source, arcname=source.name)
        with tarfile.open(inner) as archive:
            required = {'.env', 'manifest.yml', 'docker-compose.yml', 'configs.yml', 'routers.yml',
                        'README.zh-CN.md', 'README.en.md', 'icon.png'}
            if set(archive.getnames()) != required:
                raise SystemExit('Unexpected inner package files')
        outer = output / f'gitlab_{version}_pull.tar'
        with tarfile.open(outer, 'w') as archive:
            archive.add(inner, arcname='app.tar.gz')
        with tarfile.open(outer) as archive:
            if archive.getnames() != ['app.tar.gz']:
                raise SystemExit('Unexpected outer package files')
        print(outer)


if __name__ == '__main__':
    main()
