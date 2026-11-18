import base64
import copy
import datetime
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from prepare_android_signing import main as prepare_android
from prepare_ios_signing import validate_profile, run
from validate_mobile_config import validate_api_url


class MobileBuildHelpersTest(unittest.TestCase):
    def test_https_configuration(self):
        self.assertEqual(validate_api_url('https://api.example.com'), 'https://api.example.com')
        for value in ['', 'http://api.example.com', 'https://u:p@api.example.com', 'https://api.example.com?x=y', ' https://api.example.com']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_api_url(value)

    def test_android_secret_decode_and_path_guard(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'android-upload.jks'
            environment = {'RUNNER_TEMP': directory, 'ANDROID_KEYSTORE_PATH': str(target),
                           'ANDROID_KEYSTORE_BASE64': base64.b64encode(b'test-keystore-bytes').decode(),
                           'ANDROID_KEYSTORE_PASSWORD': 'test', 'ANDROID_KEY_ALIAS': 'test', 'ANDROID_KEY_PASSWORD': 'test', 'ANDROID_APPLICATION_ID': 'com.example.testapp'}
            with patch.dict(os.environ, environment, clear=True):
                with self.assertRaises(ValueError):
                    prepare_android()
                os.environ['ANDROID_APPLICATION_ID'] = 'com.customer.absensi'
                prepare_android()
                self.assertEqual(target.read_bytes(), b'test-keystore-bytes')
                os.environ['ANDROID_KEYSTORE_PATH'] = str(Path(directory) / 'wrong.jks')
                with self.assertRaises(ValueError):
                    prepare_android()

    def profile(self):
        return {'TeamIdentifier': ['ABCDE12345'], 'UUID': '12345678-1234-1234-1234-123456789abc',
                'ExpirationDate': datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1),
                'Entitlements': {'application-identifier': 'ABCDE12345.com.example.mobile', 'get-task-allow': False}}

    def test_app_store_profile(self):
        validate_profile(self.profile(), 'ABCDE12345', 'com.example.mobile', 'app-store-connect')

    def test_wrong_profile_scope_and_expiry(self):
        for mutate in [lambda p: p.update(TeamIdentifier=['OTHER12345']),
                       lambda p: p.update(ExpirationDate=datetime.datetime(2000, 1, 1)),
                       lambda p: p['Entitlements'].update({'application-identifier': 'ABCDE12345.com.other.mobile'}),
                       lambda p: p['Entitlements'].update({'application-identifier': 'ABCDE12345.*'})]:
            profile = copy.deepcopy(self.profile())
            mutate(profile)
            with self.assertRaises(ValueError):
                validate_profile(profile, 'ABCDE12345', 'com.example.mobile', 'app-store-connect')

    def test_export_method_matches_profile(self):
        profile = self.profile()
        profile['ProvisionedDevices'] = ['test-device']
        validate_profile(profile, 'ABCDE12345', 'com.example.mobile', 'release-testing')
        with self.assertRaises(ValueError):
            validate_profile(profile, 'ABCDE12345', 'com.example.mobile', 'app-store-connect')
        profile['Entitlements']['get-task-allow'] = True
        validate_profile(profile, 'ABCDE12345', 'com.example.mobile', 'debugging')
        with self.assertRaises(ValueError):
            validate_profile(profile, 'ABCDE12345', 'com.example.mobile', 'release-testing')

    def test_invalid_bundle_separator(self):
        with self.assertRaises(ValueError):
            validate_profile(self.profile(), 'ABCDE12345', 'com/example/mobile', 'app-store-connect')

    def test_failed_subprocess_never_exposes_password(self):
        import subprocess
        failure = subprocess.CalledProcessError(1, ['security', 'import', '-P', 'private-password'])
        with patch('prepare_ios_signing.subprocess.run', side_effect=failure):
            with self.assertRaises(RuntimeError) as result:
                run('security', 'import', '-P', 'private-password')
            self.assertNotIn('private-password', str(result.exception))


if __name__ == '__main__':
    unittest.main()
