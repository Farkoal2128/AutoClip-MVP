"""Create a separate, unpublished CPU successor; preserve the source candidate."""
import argparse
import copy
import hashlib
import io
import json
import re
import runpy
import tempfile
import zipfile
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]


def verifier():
    return runpy.run_path(str(ROOT / 'scripts/verify-installer-manifest.py'))


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def pinned(path, expected=None):
    helper = runpy.run_path(str(ROOT / 'installer/install-cpu-native-artifact.py'))
    path = helper['checked_path'](path)
    raw = path.read_bytes()
    if expected is not None and sha(raw) != expected:
        raise ValueError('Input SHA-256 differs: ' + str(path))
    return raw


def build(*, base, base_sha256, outer, native, disposition, disposition_sha256,
          report, report_sha256, bootstrap, release_id, release_url, native_url,
          output, manifest_output, bootstrap_output, outer_sha256=None,
          bootstrap_sha256=None, nvidia_native=None, nvidia_url=None,
          nvidia_disposition=None, nvidia_disposition_sha256=None, nvidia_report=None,
          nvidia_report_sha256=None, allow_local_candidate=False):
    gpu_inputs = (nvidia_url, nvidia_disposition, nvidia_disposition_sha256, nvidia_report, nvidia_report_sha256)
    if nvidia_native is None and any(value is not None for value in gpu_inputs):
        raise ValueError('NVIDIA input pins supplied without native artifact')
    if nvidia_native is not None and (any(value is None for value in gpu_inputs) or
            not all(re.fullmatch(r'[a-f0-9]{64}', value or '') for value in (nvidia_disposition_sha256, nvidia_report_sha256))):
        raise ValueError('NVIDIA candidate requires exact report and disposition input pins')
    outputs = [Path(output), Path(manifest_output), Path(bootstrap_output)]
    if len({p.resolve() for p in outputs}) != 3 or any(p.exists() for p in outputs):
        raise ValueError('Outputs must be three distinct new immutable files')
    gate = verifier()
    helper = runpy.run_path(str(ROOT / 'installer/install-cpu-native-artifact.py'))
    for p in outputs:
        helper['checked_path'](p)
    if not re.fullmatch(r'[a-z0-9][a-z0-9._-]{1,127}', release_id):
        raise ValueError('Unsafe release identity')
    for url in (release_url, native_url):
        gate['check_url'](url)
        if urlsplit(url).hostname != 'github.com' or '/releases/download/' not in urlsplit(url).path:
            raise ValueError('Successor needs a versioned GitHub asset URL')
    if urlsplit(release_url).path.rsplit('/', 1)[-1] != outputs[0].name or urlsplit(native_url).path.rsplit('/', 1)[-1] != Path(native).name:
        raise ValueError('Asset URL filename differs')
    base_raw = pinned(base, base_sha256)
    outer_raw = pinned(outer, outer_sha256)
    bootstrap_raw = pinned(bootstrap, bootstrap_sha256)
    review_raw = pinned(disposition, disposition_sha256)
    report_raw = pinned(report, report_sha256)
    native_raw = pinned(native)
    with zipfile.ZipFile(io.BytesIO(base_raw)) as z:
        for item in z.infolist():
            gate['check_zip_member'](item, str(base), z)
        files = helper['zip_files'](base_raw, directories=True)
    release_raw = files.pop('release-manifest.json')
    release = json.loads(release_raw)
    indexed = release.get('files', [])
    if release.get('schema_version') != 3 or len(indexed) != len(files) or {r['path'] for r in indexed} != set(files):
        raise ValueError('Base archive index differs')
    for row in indexed:
        raw = files[row['path']]
        if len(raw) != row['bytes'] or sha(raw) != row['sha256']:
            raise ValueError('Base indexed member differs: ' + row['path'])
    if 'Start-AutoClip.ps1' not in files:
        raise ValueError('Base console launcher missing')
    review = json.loads(review_raw)
    native_manifest = helper['document'](helper['zip_files'](native_raw)[helper['MARKER']])
    runtime_id = native_manifest['runtime_id']
    helper['validate'](native_raw, runtime_id)
    identity = dict(runtime_id=runtime_id, filename=Path(native).name,
                    bytes=len(native_raw), sha256=sha(native_raw))
    if review.get('schema_version') != 1 or review.get('disposition') != 'QUALIFIED_COMPONENT_DISTRIBUTION' or any(review.get('artifact', {}).get(k) != identity[k] for k in ('runtime_id', 'bytes', 'sha256')) or Path(review['artifact'].get('path', '')).name != identity['filename']:
        raise ValueError('Original component disposition differs from exact native bytes')
    prefix = 'notices-and-source/publisher-cpu/'
    if release.get("native_build", {}).get("cpu_artifact"):
        prefix += release_id + "/"
    additions = {prefix + 'original-component-disposition.json': review_raw,
                 prefix + 'original-component-report.md': report_raw,
                 prefix + 'base-release-manifest.json': release_raw}
    receipt_path = prefix + 'consuming-component-receipt.json'
    additions[receipt_path] = encoded(dict(schema_version=1, decision=review['disposition'],
        artifact=identity, scope=review.get('scope'),
        original_disposition=dict(path=prefix + 'original-component-disposition.json', sha256=sha(review_raw)),
        original_report=dict(path=prefix + 'original-component-report.md', sha256=sha(report_raw)),
        limits='Component distribution only; Setup, clean-machine application, lifecycle, uninstall and publication remain pending.'))
    descriptor = dict(identity, identity=runtime_id, url=native_url, profile='cpu',
        delivery_classification='DIRECT_RECIPIENT_DOWNLOAD',
        redirect_hosts=['github.com', 'release-assets.githubusercontent.com'],
        qualification_receipt_path=receipt_path,
        qualification_receipt_sha256=sha(additions[receipt_path]))
    additions[prefix + 'README.md'] = (
        '# CPU native libraries, notices and corresponding source\n\n'
        'CPU uses publisher-built PyAV and CTranslate2. NVIDIA is optional and uses its separate source route.\n'
        'FFmpeg is licensed under LGPL 2.1 or later; this build excludes GPL and nonfree options.\n'
        'Installed source, complete notices and build/replacement instructions are in '
        '`publisher-wheels/cpu/native-artifact/sources`, including '
        '`notices/ffmpeg-COPYING.LGPLv2.1.txt` and `build-instructions/FFmpeg-replacement.md`.\n'
        'You may modify and replace these libraries and debug those modifications. '
        'The exact native ZIP also contains the corresponding source and notices:\n\n'
        + native_url + '\n\nSHA-256: ' + identity['sha256'] + '\n').encode()
    controls = [Path(bootstrap), ROOT / 'scripts/build-publisher-cpu-release.py',
                ROOT / 'scripts/verify-installer-manifest.py', ROOT / 'scripts/build-inno.py',
                ROOT / 'update.ps1', ROOT / 'Start-AutoClip.ps1',
                *sorted((ROOT / 'installer').glob('*.ps1')),
                *sorted((ROOT / 'installer').glob('*.py')), ROOT / 'installer/AutoClip.iss']
    control_rows = []
    for path in controls:
        raw = bootstrap_raw if path == Path(bootstrap) else pinned(path)
        name = prefix + 'producer-inputs/' + ('bootstrap-input.ps1' if path == Path(bootstrap) else path.relative_to(ROOT).as_posix())
        additions[name] = raw
        control_rows.append(dict(path=name, bytes=len(raw), sha256=sha(raw)))
    additions[prefix + 'provenance.json'] = encoded(dict(schema_version=1,
        base_archive=dict(filename=Path(base).name, sha256=sha(base_raw), bytes=len(base_raw)),
        outer_input_sha256=sha(outer_raw), producer_inputs=control_rows,
        publication_state='UNPUBLISHABLE_REVIEW_PENDING'))
    if set(additions) & set(files):
        raise ValueError('Successor evidence would overwrite existing history')
    files['Start-AutoClip.ps1'] = additions[prefix + 'producer-inputs/Start-AutoClip.ps1']
    files.update(additions)
    release['native_build'] = dict(release['native_build'], delivery='publisher_cpu_with_source_nvidia', cpu_artifact=descriptor)
    if nvidia_native is not None:
        gate['check_url'](nvidia_url)
        if urlsplit(nvidia_url).hostname != 'github.com' or '/releases/download/' not in urlsplit(nvidia_url).path or urlsplit(nvidia_url).path.rsplit('/', 1)[-1] != Path(nvidia_native).name:
            raise ValueError('NVIDIA successor needs a versioned exact GitHub asset URL')
        gpu_raw = pinned(nvidia_native)
        gpu_manifest = helper['document'](helper['zip_files'](gpu_raw)[helper['MARKER']])
        gpu_id = gpu_manifest['runtime_id']
        helper['validate'](gpu_raw, gpu_id, 'nvidia')
        if gpu_id == runtime_id:
            raise ValueError('CPU and NVIDIA runtime identities must differ')
        gpu_review_raw = pinned(nvidia_disposition, nvidia_disposition_sha256)
        gpu_report_raw = pinned(nvidia_report, nvidia_report_sha256)
        gpu_review = json.loads(gpu_review_raw)
        gpu_identity = dict(runtime_id=gpu_id, filename=Path(nvidia_native).name,
                            bytes=len(gpu_raw), sha256=sha(gpu_raw))
        qualification = gpu_review.get('disposition')
        if qualification == 'UNQUALIFIED_CANDIDATE' and not allow_local_candidate:
            raise ValueError('Unqualified NVIDIA local candidate requires explicit opt-in')
        if gpu_review.get('schema_version') != 1 or qualification not in ('QUALIFIED_COMPONENT_DISTRIBUTION', 'UNQUALIFIED_CANDIDATE') or any(gpu_review.get('artifact', {}).get(k) != gpu_identity[k] for k in ('runtime_id', 'bytes', 'sha256')) or Path(gpu_review.get('artifact', {}).get('path', '')).name != gpu_identity['filename']:
            raise ValueError('NVIDIA component disposition differs from exact native bytes')
        gpu_prefix = 'notices-and-source/publisher-nvidia/' + release_id + '/'
        gpu_receipt_path = gpu_prefix + 'consuming-component-receipt.json'
        gpu_additions = {
            gpu_prefix + 'original-component-disposition.json': gpu_review_raw,
            gpu_prefix + 'original-component-report.md': gpu_report_raw,
            gpu_receipt_path: encoded(dict(schema_version=1, decision=qualification,
                artifact=gpu_identity, scope=gpu_review.get('scope'),
                original_disposition=dict(path=gpu_prefix + 'original-component-disposition.json', sha256=sha(gpu_review_raw)),
                original_report=dict(path=gpu_prefix + 'original-component-report.md', sha256=sha(gpu_report_raw)),
                limits='Local candidate testing does not establish distribution qualification or publication authorization.')),
            gpu_prefix + 'README.md': ('# NVIDIA native artifact\n\nControlled wheels, complete source, original notices and static CUDA runtime provenance are installed under `publisher-wheels/nvidia/native-artifact`.\nDisposition: ' + qualification + '\nArtifact: ' + nvidia_url + '\nSHA-256: ' + gpu_identity['sha256'] + '\n').encode(),
        }
        if set(gpu_additions) & set(files):
            raise ValueError('NVIDIA successor evidence would overwrite existing history')
        files.update(gpu_additions)
        gpu_descriptor = dict(gpu_identity, identity=gpu_id, url=nvidia_url, profile='nvidia',
            qualification=qualification, delivery_classification='DIRECT_RECIPIENT_DOWNLOAD',
            redirect_hosts=['github.com', 'release-assets.githubusercontent.com'],
            qualification_receipt_path=gpu_receipt_path,
            qualification_receipt_sha256=sha(gpu_additions[gpu_receipt_path]))
        release['native_build'].update(delivery='publisher_native_artifacts', nvidia_artifact=gpu_descriptor)
        additions[prefix + 'README.md'] = additions[prefix + 'README.md'].replace(
            b'NVIDIA is optional and uses its separate source route.',
            b'NVIDIA is optional and uses its separate controlled native artifact.')
        files[prefix + 'README.md'] = additions[prefix + 'README.md']
        files.pop('build-native-from-source.ps1', None)
    release['runtime_id'] = runtime_id
    release['release_id'] = release_id
    inventory = json.loads(files['distribution-inventory.json'])
    if inventory['publisher_wheels'] != [r['filename'] for r in release['publisher_wheels']] or inventory.get('publisher_wheel_identities', release['publisher_wheels']) != release['publisher_wheels']:
        raise ValueError('Base publisher inventory differs')
    inventory['native_build'] = copy.deepcopy(release['native_build'])
    files['distribution-inventory.json'] = encoded(inventory)
    release['files'] = [dict(path=p, bytes=len(raw), sha256=sha(raw)) for p, raw in sorted(files.items())]
    files['release-manifest.json'] = encoded(release)
    result = io.BytesIO()
    with zipfile.ZipFile(result, 'w', zipfile.ZIP_DEFLATED) as z:
        for p, raw in sorted(files.items()):
            z.writestr(p, raw)
    archive_raw = result.getvalue()
    selected = json.loads(outer_raw)
    target = selected['target_release']
    target.update(id=release_id, url=release_url, bytes=len(archive_raw), sha256=sha(archive_raw),
        manifest_sha256=sha(files['release-manifest.json']),
        distribution_inventory_sha256=sha(files['distribution-inventory.json']),
        review_scope='Unpublished successor; qualified CPU component only, final Setup and release review pending',
        delivery_classification='DIRECT_RECIPIENT_DOWNLOAD', redirect_hosts=['github.com', 'release-assets.githubusercontent.com'])
    if 'prerequisite-terms.json' in files:
        target['prerequisite_terms_sha256'] = sha(files['prerequisite-terms.json'])
    selected['cpu_native_artifact'] = descriptor
    if nvidia_native is not None:
        selected['nvidia_native_artifact'] = gpu_descriptor
        selected['qualification'] = qualification
        target['review_scope'] = 'Unpublished dual native artifact successor; NVIDIA ' + qualification
    selected['publisher_wheels'].update(count=len(release['publisher_wheels']), sha256=sha(files[selected['publisher_wheels']['manifest_path']]))
    if {gate['identity'](r) for r in selected['external_assets']} != {gate['identity'](r) for r in release['external_assets']}:
        raise ValueError('Base external assets differ from policy')
    tools = {'Visual Studio 2022 Build Tools', 'Windows SDK', 'Git for Windows', 'MSYS2', 'CUDA Toolkit', 'NVIDIA CUDA Toolkit build components'}
    if nvidia_native is not None:
        selected['native_build_assets'] = []
        selected['build_prerequisites'] = [row for row in selected['build_prerequisites'] if row['identity'] not in tools]
        for row in selected['build_prerequisites']:
            if row['identity'] == 'NVIDIA GPU and driver':
                row['license_evidence'] = 'Existing user-provided NVIDIA driver; this installer does not redistribute or install it.'
                row['post_install_check'] = 'CTranslate2 CUDA device and float16 compute capability check'
        selected['setup_payload'] = [row for row in selected.get('setup_payload', []) if row['path'] in files]
    else:
        for row in selected['native_build_assets']:
            row['profile'] = 'nvidia'
        for row in selected['build_prerequisites']:
            if row['identity'] in tools:
                row['profile'] = 'nvidia'
    for row in selected.get('setup_payload', []):
        row['sha256'] = sha(files[row['path']])
    text = bootstrap_raw.decode('utf-8-sig')
    for variable, value in [('releaseUrl', release_url), ('expectedArchiveSha256', sha(archive_raw)),
                            ('expectedManifestSha256', target['manifest_sha256']), ('releaseId', release_id)]:
        text, count = re.subn(r"(?m)^\$" + variable + r" = '[^']*'", lambda _: "$" + variable + " = '" + value + "'", text)
        if count != 1:
            raise ValueError('Bootstrap pin assignment missing or duplicated: ' + variable)
    payloads = [archive_raw, encoded(selected), text.encode('utf-8')]
    # Validate staged exact bytes before publishing any immutable output.
    with tempfile.TemporaryDirectory() as temporary:
        candidate = Path(temporary) / outputs[0].name
        policy = Path(temporary) / 'manifest.json'
        candidate.write_bytes(archive_raw)
        policy.write_bytes(payloads[1])
        gate['check'](policy, candidate, 'cpu', True, Path(native),
                        Path(nvidia_native) if nvidia_native is not None else None, allow_local_candidate)
        if nvidia_native is not None:
            gate['check'](policy, candidate, 'nvidia', True, Path(native), Path(nvidia_native), allow_local_candidate)
    for path, raw in zip(outputs, payloads):
        with path.open('xb') as stream:
            stream.write(raw)
    return dict(publication_state='UNPUBLISHABLE_REVIEW_PENDING', release_id=release_id,
                runtime_id=runtime_id, qualification=qualification if nvidia_native is not None else 'UNVERIFIED_CANDIDATE',
                outputs=[dict(path=str(p), bytes=len(raw), sha256=sha(raw)) for p, raw in zip(outputs, payloads)])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('base', 'outer', 'native', 'disposition', 'report', 'bootstrap', 'output', 'manifest-output', 'bootstrap-output'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('base-sha256', 'outer-sha256', 'disposition-sha256', 'report-sha256', 'bootstrap-sha256', 'release-id', 'release-url', 'native-url'):
        parser.add_argument('--' + name, required=True)
    for name in ('nvidia-native', 'nvidia-disposition', 'nvidia-report'):
        parser.add_argument('--' + name, type=Path)
    for name in ('nvidia-url', 'nvidia-disposition-sha256', 'nvidia-report-sha256'):
        parser.add_argument('--' + name)
    parser.add_argument('--allow-local-candidate', action='store_true')
    print(json.dumps(build(**vars(parser.parse_args())), indent=2))


if __name__ == '__main__':
    main()
