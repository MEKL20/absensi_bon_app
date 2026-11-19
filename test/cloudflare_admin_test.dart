import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:absensi_bon_app/cloudflare_admin.dart';

http.Response success([Object? result]) => http.Response(
  jsonEncode({'success': true, 'result': result, 'errors': [], 'messages': []}),
  200,
);

CloudflareAdmin adminWith(http.Client client) => CloudflareAdmin(
  clientId: 'client-id',
  redirectUri: 'absensi-bon://oauth',
  client: client,
);

final session = CloudflareSession(
  accessToken: 'token',
  expiresAt: DateTime(2030, 1, 1),
);

const migrations = [
  CloudflareMigration(
    tag: '0001_initial',
    sql: 'CREATE TABLE users (id TEXT);',
  ),
  CloudflareMigration(
    tag: '0002_workspace',
    sql: 'CREATE TABLE workspace_setup (id INTEGER);',
  ),
];

String keyOf(http.Request request) =>
    '${request.method} ${request.url.path.replaceFirst('/client/v4', '')}';

void main() {
  test('pkce challenge is stable base64url without padding', () {
    final admin = adminWith(MockClient((_) async => success()));
    expect(admin.challengeFor('verifier-value'), isNot(contains('=')));
    expect(
      admin.challengeFor('verifier-value'),
      admin.challengeFor('verifier-value'),
    );
    expect(admin.newPkceVerifier().length, greaterThanOrEqualTo(43));
  });

  test('authorize url carries pkce, state and scopes', () {
    final admin = adminWith(MockClient((_) async => success()));
    final url = admin.authorizeUrl(
      state: 'state-1',
      codeChallenge: 'challenge-1',
      scopeIds: ['a', 'b'],
    );
    expect(url.host, 'dash.cloudflare.com');
    expect(url.path, '/oauth2/auth');
    expect(url.queryParameters['code_challenge_method'], 'S256');
    expect(url.queryParameters['state'], 'state-1');
    expect(url.queryParameters['scope'], 'a b');
    expect(url.queryParameters['redirect_uri'], 'absensi-bon://oauth');
  });

  test('exchange code posts pkce verifier and parses session', () async {
    late http.Request sent;
    final admin = adminWith(
      MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'access_token': 'access',
            'refresh_token': 'refresh',
            'expires_in': 3600,
          }),
          200,
        );
      }),
    );
    final result = await admin.exchangeCode(
      code: 'code-1',
      codeVerifier: 'verifier-1',
    );
    expect(sent.url.path, '/oauth2/token');
    expect(sent.body, contains('code_verifier=verifier-1'));
    expect(sent.body, contains('grant_type=authorization_code'));
    expect(result.accessToken, 'access');
    expect(result.refreshToken, 'refresh');
  });

  test(
    'provision creates d1, r2, migrations, worker, secret and workers.dev origin in order',
    () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        final key = keyOf(request);
        calls.add(key);
        if (key == 'GET /accounts') {
          return success([
            {'id': 'acc-1', 'name': 'Owner'},
          ]);
        }
        if (key == 'GET /accounts/acc-1/d1/database') return success([]);
        if (key == 'POST /accounts/acc-1/d1/database') {
          return success({'uuid': 'db-1', 'name': 'absensi-bon'});
        }
        if (key == 'GET /accounts/acc-1/r2/buckets') return success([]);
        if (key == 'POST /accounts/acc-1/r2/buckets') {
          return success({'name': 'photos'});
        }
        if (key == 'POST /accounts/acc-1/d1/database/db-1/query') {
          final body = jsonDecode(request.body);
          if (body is List && body.length == 1) {
            return success([
              {'results': []},
            ]);
          }
          expect(body, hasLength(2));
          return success([
            {'results': []},
            {'results': []},
          ]);
        }
        if (key == 'PUT /accounts/acc-1/workers/scripts/absensi-bon-api') {
          expect(request.body, contains('"main_module":"worker.js"'));
          expect(request.body, contains('"id":"db-1"'));
          expect(request.body, contains('"bucket_name":"photos"'));
          expect(request.body, contains('WORKER_BUNDLE_BYTES'));
          expect(request.headers['Authorization'], 'Bearer token');
          return success();
        }
        if (key ==
            'PUT /accounts/acc-1/workers/scripts/absensi-bon-api/secrets') {
          final body = jsonDecode(request.body);
          expect(body['name'], 'OWNER_SETUP_TOKEN_SHA256');
          expect(body['text'], 'digest-1');
          expect(body['type'], 'secret_text');
          return success();
        }
        if (key == 'GET /accounts/acc-1/workers/subdomain') {
          return http.Response(
            jsonEncode({
              'success': false,
              'result': null,
              'errors': [
                {'code': 404, 'message': 'not found'},
              ],
            }),
            404,
          );
        }
        if (key == 'PUT /accounts/acc-1/workers/subdomain') {
          return success({'subdomain': 'acct-sub'});
        }
        if (key ==
            'POST /accounts/acc-1/workers/scripts/absensi-bon-api/subdomain') {
          expect(request.body, contains('"enabled":true'));
          return success();
        }
        return http.Response(
          jsonEncode({
            'success': false,
            'errors': [
              {'code': 0, 'message': 'unexpected call'},
            ],
          }),
          500,
        );
      });
      final admin = adminWith(client);
      final steps = <String>[];
      final result = await admin.provision(
        session: session,
        workerName: 'absensi-bon-api',
        databaseName: 'absensi-bon',
        bucketName: 'photos',
        workerBundle: Uint8List.fromList(utf8.encode('WORKER_BUNDLE_BYTES')),
        migrations: migrations,
        vars: const {'BUSINESS_TIMEZONE': 'Asia/Jakarta'},
        crons: const ['17 3 * * *'],
        compatibilityDate: '2026-08-06',
        setupDigest: 'digest-1',
        onProgress: steps.add,
      );
      expect(result.origin, 'https://absensi-bon-api.acct-sub.workers.dev');
      expect(result.databaseId, 'db-1');
      expect(calls, [
        'GET /accounts',
        'GET /accounts/acc-1/d1/database',
        'POST /accounts/acc-1/d1/database',
        'GET /accounts/acc-1/r2/buckets',
        'POST /accounts/acc-1/r2/buckets',
        'POST /accounts/acc-1/d1/database/db-1/query',
        'POST /accounts/acc-1/d1/database/db-1/query',
        'PUT /accounts/acc-1/workers/scripts/absensi-bon-api',
        'PUT /accounts/acc-1/workers/scripts/absensi-bon-api/secrets',
        'GET /accounts/acc-1/workers/subdomain',
        'PUT /accounts/acc-1/workers/subdomain',
        'POST /accounts/acc-1/workers/scripts/absensi-bon-api/subdomain',
      ]);
      expect(steps.first, 'Membaca akun Cloudflare');
      expect(steps.last, 'Selesai');
    },
  );

  test(
    'provision reuses existing resources and skips applied migrations',
    () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        final key = keyOf(request);
        calls.add(key);
        if (key == 'GET /accounts') {
          return success([
            {'id': 'acc-1'},
          ]);
        }
        if (key == 'GET /accounts/acc-1/d1/database') {
          return success([
            {'name': 'absensi-bon', 'uuid': 'db-existing'},
          ]);
        }
        if (key == 'GET /accounts/acc-1/r2/buckets') {
          return success([
            {'name': 'photos'},
          ]);
        }
        if (key == 'POST /accounts/acc-1/d1/database/db-existing/query') {
          return success([
            {
              'results': [
                {'name': 'workspace_setup'},
              ],
            },
          ]);
        }
        if (key == 'PUT /accounts/acc-1/workers/scripts/absensi-bon-api') {
          return success();
        }
        if (key ==
            'PUT /accounts/acc-1/workers/scripts/absensi-bon-api/secrets') {
          return success();
        }
        if (key == 'GET /accounts/acc-1/workers/subdomain') {
          return success({'subdomain': 'acct-sub'});
        }
        if (key ==
            'POST /accounts/acc-1/workers/scripts/absensi-bon-api/subdomain') {
          return success();
        }
        return http.Response(
          jsonEncode({
            'success': false,
            'errors': [
              {'code': 0, 'message': 'unexpected call'},
            ],
          }),
          500,
        );
      });
      final admin = adminWith(client);
      final result = await admin.provision(
        session: session,
        workerName: 'absensi-bon-api',
        databaseName: 'absensi-bon',
        bucketName: 'photos',
        workerBundle: Uint8List.fromList(utf8.encode('bundle')),
        migrations: migrations,
        vars: const {},
        crons: const [],
        compatibilityDate: '2026-08-06',
        setupDigest: 'digest-1',
      );
      expect(result.databaseId, 'db-existing');
      expect(calls, isNot(contains('POST /accounts/acc-1/d1/database')));
      expect(calls, isNot(contains('POST /accounts/acc-1/r2/buckets')));
      expect(calls.where((c) => c.endsWith('/query')), hasLength(1));
    },
  );

  test('r2 billing failure is mapped to an actionable error', () async {
    final client = MockClient((request) async {
      final key = keyOf(request);
      if (key == 'GET /accounts') {
        return success([
          {'id': 'acc-1'},
        ]);
      }
      if (key == 'GET /accounts/acc-1/d1/database') {
        return success([
          {'name': 'absensi-bon', 'uuid': 'db-1'},
        ]);
      }
      if (key == 'GET /accounts/acc-1/r2/buckets') return success([]);
      if (key == 'POST /accounts/acc-1/r2/buckets') {
        return http.Response(
          jsonEncode({
            'success': false,
            'errors': [
              {'code': 10038, 'message': 'R2 requires an active subscription'},
            ],
          }),
          403,
        );
      }
      return success();
    });
    final admin = adminWith(client);
    await expectLater(
      admin.provision(
        session: session,
        workerName: 'w',
        databaseName: 'absensi-bon',
        bucketName: 'photos',
        workerBundle: Uint8List(0),
        migrations: migrations,
        vars: const {},
        crons: const [],
        compatibilityDate: '2026-08-06',
        setupDigest: 'd',
      ),
      throwsA(
        isA<CloudflareAdminException>().having(
          (e) => e.code,
          'code',
          'r2_billing',
        ),
      ),
    );
  });
}
