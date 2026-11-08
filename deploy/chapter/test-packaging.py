#!/usr/bin/env python3
"""No Docker required: real setup isolation, exclusive creation and wrapper args."""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='chapter-packaging-') as temporary:
    directory = Path(temporary)
    config = directory / 'fixture.env'
    env = dict(os.environ, CHAPTER_ENV_FILE=str(config))
    subprocess.run([str(root / 'deploy/chapter/init.sh')], env=env, check=True, capture_output=True)
    assert stat.S_IMODE(config.stat().st_mode) == 0o600
    original = hashlib.sha256(config.read_bytes()).digest()
    values = dict(line.split('=',1) for line in config.read_text().splitlines())
    assert len(values['POSTGRES_PASSWORD']) == 48
    assert len(values['S3_SECRET_KEY']) == 48
    assert len(values['ADMIN_TOKEN']) == 64
    assert values['REQUIRE_APPROVAL'] == 'true' and values['CHAPTER_BIND'] == '127.0.0.1'
    again = subprocess.run([str(root / 'deploy/chapter/init.sh')], env=env, capture_output=True)
    assert again.returncode != 0 and hashlib.sha256(config.read_bytes()).digest() == original
    # Stub Docker only for argument verification, never claiming container success.
    docker = directory / 'docker'
    docker.write_text('#!/usr/bin/env python3\nimport json,os,sys\nprint(json.dumps({"args":sys.argv[1:],"source":os.environ["CHAPTER_SOURCE_DIR"]}))\n')
    docker.chmod(0o700)
    env.update(PATH=str(directory)+os.pathsep+os.environ['PATH'], CHAPTER_PROJECT='chapter-fixture-test')
    result = json.loads(subprocess.check_output([str(root/'deploy/chapter/chapter.sh'),'up','--no-build'],env=env))
    assert result['source'] == str(root)
    assert result['args'][:3] == ['compose','--project-name','chapter-fixture-test']
    assert str(config) in result['args'] and result['args'][-2:] == ['up','--no-build']
    assert not any(secret in json.dumps(result) for secret in [values['ADMIN_TOKEN'],values['POSTGRES_PASSWORD'],values['S3_SECRET_KEY']])
compose=(root/'deploy/chapter/compose.yml').read_text()
assert 'ghcr.io/mneme-blog/' not in compose and 'minio/minio:' not in compose
assert 'UPDATE_CHECK: "off"' in compose and 'UPDATE_SPOOL_DIR: ""' in compose
assert 'docker.sock' not in compose and 'privileged:' not in compose
print('PASS: exclusive 0600 secret setup, no overwrite/leak, isolated wrapper, Chapter image names and disabled upstream updater. Container execution is a separate CI gate.')
