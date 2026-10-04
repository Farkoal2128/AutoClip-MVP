"""Verify the compiled installer's early refusal without replacing a real selection.

Run on the Windows test host with --exe <candidate.exe> --log <new-log-path>.
Requires no active host runtime. The temporary selection is removed only when
its bytes still match; installed setup files must retain their baseline hashes.
"""
import argparse
import hashlib
import os
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    assert args.exe.is_file() and not args.log.exists()
    base = Path(os.environ['LOCALAPPDATA'])/'AutoClip'
    active = base/'active.json'
    assert not active.exists(), 'Do not replace a real selection'
    sha = lambda raw: hashlib.sha256(raw).hexdigest()
    snapshot = {str(p):sha(p.read_bytes()) for p in (base/'Setup').rglob('*') if p.is_file()}
    raw = b'{"schema_version":1,"current":{"release_id":"v0.1.0-mvp-20261003-r1","archive_sha256":"a720dde04beacd287561bf43c0938dc5530feb801211dda416eb2a90ee6b86c4","manifest_sha256":"572a4fc6f9734331b484c8b3a3301f7dda6e2783695200962e2ba38bdd9a9970"},"previous":null}'
    with active.open('xb') as output:
        output.write(raw)
    try:
        result = subprocess.run([str(args.exe),'/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/LOG='+str(args.log)],timeout=60)
        contents = args.log.read_text('utf-8-sig')
        assert result.returncode != 0
        assert 'AutoClip-Update-v1.0.0.zip' in contents, 'Missing supported upgrade instruction'
        assert 'InitializeSetup returned False' in contents
        assert active.read_bytes() == raw
        assert all(Path(p).is_file() and sha(Path(p).read_bytes()) == digest for p,digest in snapshot.items())
        print('NATIVE_EXISTING_INSTALL_REFUSAL_PASS')
    finally:
        assert active.read_bytes() == raw, 'Selection changed; preserve it for investigation'
        active.unlink()


if __name__ == '__main__':
    main()
