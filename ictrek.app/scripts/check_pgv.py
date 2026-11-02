#!/usr/bin/env python3
"""Check PGV capacity or explicitly apply/restore settings with a shared-service restart."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--apply-and-restart', action='store_true', help='Changes shared PGV and disconnects all its clients briefly')
    group.add_argument('--restore-and-restart', action='store_true', help='Restores the saved settings and restarts shared PGV')
    args = parser.parse_args()
    names = subprocess.check_output(['docker', 'ps', '--format', '{{.Names}}'], text=True).splitlines()
    matches = [name for name in names if name.startswith('vos-app-com-ictrek-pgv-') and
               name.endswith(('-ictrek-pgv-amd-1', '-ictrek-pgv-arm-1'))]
    if len(matches) != 1:
        raise RuntimeError('Expected exactly one installed PGV database container')
    container = matches[0]
    config = json.loads(subprocess.check_output(['docker', 'inspect', container], text=True))[0]
    env = dict(item.split('=', 1) for item in config['Config']['Env'] if '=' in item)
    process_env = {**os.environ, 'PGPASSWORD': env['POSTGRES_PASSWORD']}

    def sql(statement):
        command = ['docker', 'exec', '-i', '--env', 'PGPASSWORD', container, 'psql', '-X', '-A', '-t',
                   '-v', 'ON_ERROR_STOP=1', '-U', env.get('POSTGRES_USER', 'postgres'), '-d', 'postgres']
        return subprocess.check_output(command, input=statement, text=True, env=process_env, stderr=subprocess.PIPE).strip()

    current = json.loads(sql("SELECT json_build_object('max_connections', current_setting('max_connections'), "
                             "'shared_buffers', current_setting('shared_buffers'), "
                             "'shared_buffers_bytes', pg_size_bytes(current_setting('shared_buffers')), "
                             "'max_locks_per_transaction', current_setting('max_locks_per_transaction'));"))
    print(json.dumps(current, indent=2))
    if not args.apply_and_restart and not args.restore_and_restart:
        ready = int(current['max_connections']) >= 400 and int(current['shared_buffers_bytes']) >= 2 * 1024**3
        print('READY' if ready else 'PGV needs an operator-approved configuration change and restart before GitLab installation')
        return 0 if ready else 2
    build = Path.home() / 'dev/build/gitlab'
    build.mkdir(parents=True, exist_ok=True)
    backup = build / 'pgv-config-backup.json'
    if args.restore_and_restart:
        target = json.loads(backup.read_text())
    else:
        if not backup.exists():
            backup.write_text(json.dumps(current, indent=2) + '\n')
            backup.chmod(0o600)
        target = {'max_connections': str(max(int(current['max_connections']), 400)),
                  'shared_buffers': current['shared_buffers'] if int(current['shared_buffers_bytes']) >= 2 * 1024**3 else '2GB'}
    for setting in ('max_connections', 'shared_buffers'):
        value = str(target[setting])
        if not re.fullmatch(r'\d+(?:kB|MB|GB)?', value):
            raise RuntimeError('Unsupported saved PostgreSQL parameter value')
        sql(f"ALTER SYSTEM SET {setting} = '{value}';")
    subprocess.run(['docker', 'restart', '-t', '60', container], stdout=subprocess.DEVNULL, check=True)
    for _ in range(60):
        try:
            sql('SELECT 1;')
            print('PGV restarted and accepts connections. Rerun the capacity check before continuing installation.')
            return 0
        except subprocess.CalledProcessError:
            time.sleep(2)
    raise RuntimeError('PGV did not become ready after the restart')


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
        # Command stderr can contain database connection details.
        print(f'PGV configuration operation failed: {type(error).__name__}', file=sys.stderr)
        sys.exit(1)
