#!/usr/bin/env python3
"""Build one CPU architecture from the authoritative, rsynced local checkout."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PROFILES = {'AMD_with_cuda': ('amd', 'amd64'), 'ARM_with_cuda': ('arm', 'arm64')}
REGISTRY = 'swr.cn-southwest-2.myhuaweicloud.com/ictrek/gitlab'
BASE = 'gitlab/gitlab-ee@sha256:fb51b202d69ffb97cb2aeaf3558cb653147d0c7014fe1855b752cb5675bd4a6e'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sheet', choices=PROFILES, required=True)
    parser.add_argument('--source-commit', required=True, help='Commit resolved on the local development machine')
    parser.add_argument('--base-image', default=BASE)
    parser.add_argument('--no-push', action='store_true')
    parser.add_argument('--no-feishu', action='store_true')
    args = parser.parse_args()
    if not 7 <= len(args.source_commit) <= 40 or any(c not in '0123456789abcdef' for c in args.source_commit):
        parser.error('--source-commit must be a hexadecimal source commit ID')
    profile, arch = PROFILES[args.sheet]
    version = (ROOT / 'VERSION').read_text().strip()
    tag = f'{profile}_{version}_{args.source_commit[:12]}'
    image = f'{REGISTRY}:{tag}'
    build = Path.home() / 'dev/build/gitlab' / tag
    context = build / 'context'
    context.mkdir(parents=True, exist_ok=True)
    for relative in ('lib/gitlab/auth/vos', 'lib/omni_auth/strategies/vos.rb',
                     'app/controllers/vos', 'app/views/vos', 'config/initializers/0_vos.rb'):
        source = ROOT / relative
        target = context / 'overlay' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target, dirs_exist_ok=True)
        else:
            shutil.copy2(source, target)
    for name in ('Dockerfile', 'vos-init', 'vos-config.rb', 'prepare-pgv.rb'):
        shutil.copy2(ROOT / 'ictrek.app/docker' / name, context / name)
    command = ['docker', 'buildx', 'build', '--load', '--provenance=false', '--sbom=false',
               '--platform', f'linux/{arch}', '--build-arg', f'BASE_IMAGE={args.base_image}',
               '--build-arg', f'GITLAB_VERSION={version}', '--build-arg', f'SOURCE_COMMIT={args.source_commit}',
               '-t', image, str(context)]
    with (build / 'build.log').open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print(f'Build failed. See {build / "build.log"}', file=sys.stderr)
        return result.returncode
    if not args.no_push:
        subprocess.run(['docker', 'push', image], check=True)
        subprocess.run(['docker', 'manifest', 'inspect', image], stdout=subprocess.DEVNULL, check=True)
        if not args.no_feishu:
            subprocess.run(['python3', str(ROOT / 'ictrek.app/scripts/feishu_release.py'),
                            '--sheet', args.sheet, '--tag', tag, '--component', 'gitlab',
                            '--repository', REGISTRY], check=True)
    (build / 'image.json').write_text(json.dumps({'image': image, 'profile': profile, 'arch': arch,
        'base_image': args.base_image, 'source_commit': args.source_commit}, indent=2) + '\n')
    print(image)
    return 0


if __name__ == '__main__':
    sys.exit(main())
