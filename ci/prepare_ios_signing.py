"""Install Apple signing material on an ephemeral macOS runner; never log secrets."""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import subprocess
import sys


def run(*args, capture=False, env=None):
    try:
        result = subprocess.run(args, check=True, capture_output=True, env=env)
    except subprocess.CalledProcessError:
        raise RuntimeError('Apple signing command failed: ' + args[0] + ' ' + args[1]) from None
    return result.stdout if capture else None


def decode_secret(name):
    value = os.environ.get(name, '')
    if not value:
        raise ValueError('Missing signing secret: ' + name)
    return base64.b64decode(''.join(value.split()), validate=True)


def validate_profile(profile, team, bundle, method):
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('IOS_TEAM_ID must be an Apple team ID.')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle):
        raise ValueError('IOS_BUNDLE_ID must be an explicit bundle identifier.')
    entitlements = profile.get('Entitlements', {})
    app_id = entitlements.get('application-identifier', '')
    if profile.get('TeamIdentifier', [None])[0] != team or not app_id.endswith('.' + bundle) or '*' in app_id:
        raise ValueError('Provisioning profile must match the configured team and explicit bundle identifier.')
    expiry = profile.get('ExpirationDate')
    if not expiry or expiry.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError('Provisioning profile has expired.')
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}', profile.get('UUID', '')):
        raise ValueError('Invalid provisioning profile UUID.')
    development = bool(entitlements.get('get-task-allow'))
    devices = bool(profile.get('ProvisionedDevices'))
    enterprise = bool(profile.get('ProvisionsAllDevices'))
    if method not in ('app-store-connect', 'release-testing', 'debugging') or enterprise:
        raise ValueError('Unsupported iOS export method/profile.')
    if (method == 'debugging') != development or (method == 'release-testing' and not devices) or (method == 'app-store-connect' and devices):
        raise ValueError('The provisioning profile does not match the selected export method.')


def cleanup(root):
    state_path = root / 'ios-signing-state.json'
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    if state.get('keychains'):
        run('security', 'list-keychains', '-d', 'user', '-s', *state['keychains'])
    keychain = root / 'mobile-signing.keychain-db'
    if keychain.exists():
        run('security', 'delete-keychain', str(keychain))
    profile = state.get('profile')
    if profile:
        Path(profile).unlink(missing_ok=True)
    for name in ('apple-certificate.p12', 'apple-profile.mobileprovision', 'ExportOptions.plist', 'ios-signing-state.json'):
        (root / name).unlink(missing_ok=True)


def main():
    root = Path(os.environ['RUNNER_TEMP'])
    if sys.argv[1:] == ['--cleanup']:
        cleanup(root)
        return
    team, bundle = os.environ.get('IOS_TEAM_ID', ''), os.environ.get('IOS_BUNDLE_ID', '')
    method = os.environ.get('IOS_EXPORT_METHOD', 'app-store-connect')
    certificate = root / 'apple-certificate.p12'
    provisioning = root / 'apple-profile.mobileprovision'
    certificate.write_bytes(decode_secret('IOS_CERTIFICATE_BASE64'))
    provisioning.write_bytes(decode_secret('IOS_PROFILE_BASE64'))
    certificate.chmod(0o600)
    provisioning.chmod(0o600)
    profile = plistlib.loads(run('security', 'cms', '-D', '-i', str(provisioning), capture=True))
    validate_profile(profile, team, bundle, method)
    uuid = profile['UUID']
    destination = Path.home() / 'Library/MobileDevice/Provisioning Profiles' / (uuid + '.mobileprovision')
    if destination.exists():
        raise ValueError('Refusing to replace an existing provisioning profile.')
    keychains = shlex.split(run('security', 'list-keychains', '-d', 'user', capture=True).decode())
    state_path = root / 'ios-signing-state.json'
    state_path.write_text(json.dumps({'keychains': keychains, 'profile': str(destination)}))
    state_path.chmod(0o600)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(provisioning.read_bytes())
    keychain = root / 'mobile-signing.keychain-db'
    password = secrets.token_hex(32)
    run('security', 'create-keychain', '-p', password, str(keychain))
    run('security', 'set-keychain-settings', '-lut', '3600', str(keychain))
    run('security', 'unlock-keychain', '-p', password, str(keychain))
    run('security', 'import', str(certificate), '-P', os.environ.get('IOS_CERTIFICATE_PASSWORD', ''), '-k', str(keychain), '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-k', password, str(keychain))
    run('security', 'list-keychains', '-d', 'user', '-s', str(keychain), *keychains)
    identities = run('security', 'find-identity', '-v', '-p', 'codesigning', str(keychain), capture=True).decode()
    available = re.findall(r'\b[0-9A-F]{40}\b', identities)
    allowed = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get('DeveloperCertificates', [])}
    identity = next((item for item in available if item in allowed), None)
    if not identity:
        raise ValueError('The imported private-key certificate does not match this profile.')
    environment = dict(os.environ, IOS_PROFILE_UUID=uuid, IOS_SIGNING_IDENTITY=identity)
    run('ruby', 'ci/configure_ios_signing.rb', env=environment)
    options = {'method': method, 'destination': 'export', 'teamID': team, 'signingStyle': 'manual', 'signingCertificate': identity,
               'provisioningProfiles': {bundle: uuid}, 'manageAppVersionAndBuildNumber': False}
    with (root / 'ExportOptions.plist').open('wb') as stream:
        plistlib.dump(options, stream)
    print('Apple signing profile and temporary keychain prepared.')


if __name__ == '__main__':
    main()
