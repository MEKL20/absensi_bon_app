"""Decode a GitHub secret into the runner's temporary upload keystore."""
import base64
import os
from pathlib import Path


def main():
    required = ['ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD', 'ANDROID_KEYSTORE_PATH']
    application_id = os.environ.get('ANDROID_APPLICATION_ID', '')
    if not all(part.isidentifier() and part.isascii() for part in application_id.split('.')) or len(application_id.split('.')) < 2 or application_id.startswith('com.example.'):
        raise ValueError('ANDROID_APPLICATION_ID must be a production reverse-DNS identifier, not the sample com.example ID.')
    if any(not os.environ.get(name) for name in required):
        raise ValueError('Configure all four Android signing secrets before running signed builds.')
    target = Path(os.environ['ANDROID_KEYSTORE_PATH'])
    expected = Path(os.environ['RUNNER_TEMP']) / 'android-upload.jks'
    if target.resolve() != expected.resolve():
        raise ValueError('Signing output must use the runner temporary keystore path.')
    data = base64.b64decode(''.join(os.environ['ANDROID_KEYSTORE_BASE64'].split()), validate=True)
    if not data:
        raise ValueError('Android keystore is empty.')
    target.write_bytes(data)
    target.chmod(0o600)
    print('Temporary Android signing keystore prepared.')


if __name__ == '__main__':
    main()
