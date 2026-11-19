import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:absensi_bon_app/api_client.dart';
import 'package:absensi_bon_app/pending_store.dart';
import 'package:absensi_bon_app/workspace_store.dart';

const user = {
  'id': 'employee-1',
  'name': 'Ayu',
  'username': 'ayu',
  'role': 'employee',
  'active': true,
};
const bonRecord = {
  'id': 'bon-1',
  'employeeId': 'employee-1',
  'employeeName': 'Ayu',
  'amount': 50000,
  'note': '',
  'status': 'pending',
  'repaidAmount': 0,
  'createdAt': '2026-11-17T00:00:00Z',
};
const attendanceRecord = {
  'id': 'attendance-1',
  'employeeId': 'employee-1',
  'employeeName': 'Ayu',
  'kind': 'check_in',
  'recordedAt': '2026-11-17T00:00:00Z',
  'photoPath': '/v1/attendance/attendance-1/photo',
};

http.Response receipt([Map<String, Object> record = bonRecord]) =>
    http.Response(jsonEncode({'ok': true, 'record': record}), 201);

const testWorkspaceId = '0123456789abcdef0123456789abcdef';

Future<ApiClient> testClient(
  Future<http.Response> Function(http.Request) transport, {
  PendingStore? store,
  String baseUrl = 'https://example.test',
  Map<String, Object> account = user,
}) async {
  final api = ApiClient(
    baseUrl: baseUrl,
    pendingStore: store ?? PendingStore.memory(),
    client: MockClient((request) async {
      if (request.url.path == '/v1/workspace') {
        return http.Response(
          jsonEncode({
            'id': testWorkspaceId,
            'name': 'Usaha Uji',
            'ready': true,
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/login')) {
        return http.Response(
          jsonEncode({'ok': true, 'token': 'session-token', 'user': account}),
          200,
        );
      }
      return transport(request);
    }),
  );
  try {
    parseWorkspaceOrigin(baseUrl);
    await api.switchWorkspace(
      WorkspaceConnection(
        origin: baseUrl,
        workspaceId: testWorkspaceId,
        name: 'Usaha Uji',
      ),
    );
  } catch (_) {
    // Invalid endpoints stay unpaired so gate tests can assert fail-closed behavior.
  }
  return api;
}

Matcher uncertain = isA<ApiException>().having(
  (e) => e.uncertain,
  'uncertain',
  true,
);

void main() {
  test(
    'credentials use JSON body and propagate bearer session without persistence',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'https://example.test',
        pendingStore: PendingStore.memory(),
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/v1/workspace') {
            return http.Response(
              jsonEncode({
                'id': testWorkspaceId,
                'name': 'Usaha Uji',
                'ready': true,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/login')) {
            return http.Response(
              jsonEncode({'ok': true, 'token': 'session-token', 'user': user}),
              200,
            );
          }
          return http.Response(jsonEncode({'ok': true, 'bon': []}), 200);
        }),
      );
      await api.switchWorkspace(
        const WorkspaceConnection(
          origin: 'https://example.test',
          workspaceId: testWorkspaceId,
          name: 'Usaha Uji',
        ),
      );
      await api.login(' ayu ', ' password & secret ');
      await api.bon();
      final loginRequest = requests.firstWhere(
        (request) => request.url.path.endsWith('/login'),
      );
      expect(loginRequest.method, 'POST');
      expect(loginRequest.url.query, isEmpty);
      expect(jsonDecode(loginRequest.body), {
        'username': 'ayu',
        'password': ' password & secret ',
      });
      expect(requests.last.headers['Authorization'], 'Bearer session-token');
    },
  );

  test(
    'bon sends amount and note with retry key, typed success clears and increments',
    () async {
      late http.Request sent;
      final api = await testClient((request) async {
        sent = request;
        return receipt();
      });
      await api.login('ayu', 'password');
      final result = await api.submitBon(
        amount: 50000,
        note: '',
        requestId: 'stable-key',
      );
      expect(result.status, 'pending');
      expect(result.outstanding, 0);
      expect(jsonDecode(sent.body), {'amount': 50000, 'note': ''});
      expect(sent.headers['Idempotency-Key'], 'stable-key');
      expect(api.hasPendingRequest, false);
      expect(api.revision, 2);
    },
  );

  test(
    'file store survives new store/client; recovery sends identical original body and key',
    () async {
      final directory = await Directory.systemTemp.createTemp('pending-api-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/pending.json');
      final sent = <http.Request>[];
      final first = await testClient((request) async {
        sent.add(request);
        throw http.ClientException('disconnected');
      }, store: PendingStore.file(file));
      await first.login('ayu', 'never-store-password');
      await expectLater(
        first.submitBon(
          amount: 50000,
          note: ' original ',
          requestId: 'original-id',
        ),
        throwsA(uncertain),
      );
      expect(first.hasPendingRequest, true);
      expect(first.revision, 1);
      final persisted = await file.readAsString();
      expect(persisted, contains('original-id'));
      expect(persisted, isNot(contains('never-store-password')));
      expect(persisted, isNot(contains('session-token')));
      first.close();
      final restarted = await testClient((request) async {
        sent.add(request);
        return receipt();
      }, store: PendingStore.file(file));
      expect(restarted.hasPendingRequest, false);
      await restarted.login('ayu', 'password');
      expect(restarted.hasPendingRequest, true);
      expect(await restarted.recoverPending(), contains('bon-1'));
      expect(sent.last.body, sent.first.body);
      expect(
        sent.last.headers['Idempotency-Key'],
        sent.first.headers['Idempotency-Key'],
      );
      expect(restarted.hasPendingRequest, false);
      expect(restarted.revision, 2);
      expect(
        await PendingStore.file(
          file,
        ).load('https://example.test', 'employee-1'),
        isNull,
      );
    },
  );

  for (final malformed in [
    {'ok': true},
    {
      'ok': true,
      'record': {...bonRecord, 'amount': 'not-a-number'},
    },
    {
      'ok': true,
      'record': {...bonRecord, 'createdAt': 'not-a-date'},
    },
  ]) {
    test(
      'malformed 200 receipt stays pending and conflicting payload is blocked: $malformed',
      () async {
        var sends = 0;
        var valid = false;
        final api = await testClient((_) async {
          sends++;
          return valid ? receipt() : http.Response(jsonEncode(malformed), 200);
        });
        await api.login('ayu', 'password');
        await expectLater(
          api.submitBon(amount: 1, note: '', requestId: 'key'),
          throwsA(uncertain),
        );
        expect(api.hasPendingRequest, true);
        expect(api.revision, 1);
        await expectLater(
          api.submitBon(amount: 2, note: '', requestId: 'key'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'pending_request',
            ),
          ),
        );
        await expectLater(
          api.bonAction('bon-1', 'approve', requestId: 'new-key'),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          api.saveEmployee(
            name: 'Another',
            username: 'another',
            password: 'secret',
          ),
          throwsA(isA<ApiException>()),
        );
        expect(sends, 1);
        valid = true;
        await api.recoverPending();
        expect(api.hasPendingRequest, false);
        expect(api.revision, 2);
      },
    );
  }

  for (final status in [200, 400, 409, 422]) {
    test(
      'definitive rejection $status releases pending for another mutation',
      () async {
        var reject = true;
        final api = await testClient(
          (_) async => reject
              ? http.Response(
                  jsonEncode({
                    'ok': false,
                    'error': {'code': 'rejected', 'message': 'Ditolak'},
                  }),
                  status,
                )
              : receipt(),
        );
        await api.login('ayu', 'password');
        await expectLater(
          api.submitBon(amount: 1, note: '', requestId: 'key'),
          throwsA(
            isA<ApiException>().having((e) => e.code, 'code', 'rejected'),
          ),
        );
        expect(api.hasPendingRequest, false);
        expect(api.revision, 1);
        reject = false;
        await api.submitBon(amount: 2, note: '', requestId: 'new-key');
        expect(api.revision, 2);
      },
    );
  }

  for (final status in [401, 500, 503]) {
    test('status $status retains pending across signout and relogin', () async {
      final store = PendingStore.memory();
      var fail = true;
      final api = await testClient((request) async {
        if (request.url.path.endsWith('/logout')) {
          return http.Response(
            jsonEncode({
              'ok': false,
              'error': {'code': 'unauthorized'},
            }),
            401,
          );
        }
        return fail
            ? http.Response(
                jsonEncode({
                  'ok': false,
                  'error': {'code': 'server'},
                }),
                status,
              )
            : receipt();
      }, store: store);
      await api.login('ayu', 'password');
      await expectLater(
        api.submitBon(amount: 1, note: '', requestId: 'key'),
        throwsA(uncertain),
      );
      await api.logout();
      expect(
        await store.load('https://example.test', 'employee-1', testWorkspaceId),
        isNotNull,
      );
      fail = false;
      await api.login('ayu', 'password');
      expect(api.hasPendingRequest, true);
      await api.recoverPending();
      expect(api.hasPendingRequest, false);
    });
  }

  test('timeout and invalid JSON retain original request', () async {
    for (final failure in [TimeoutException('timeout'), null]) {
      final api = await testClient((_) async {
        if (failure != null) throw failure;
        return http.Response('not JSON', 200);
      });
      await api.login('ayu', 'password');
      await expectLater(
        api.submitBon(amount: 1, note: '', requestId: 'key'),
        throwsA(uncertain),
      );
      expect(api.hasPendingRequest, true);
    }
  });

  test(
    'attendance stores photo bytes and recovers after original photo is gone',
    () async {
      final directory = await Directory.systemTemp.createTemp('pending-photo-');
      addTearDown(() => directory.delete(recursive: true));
      final photo = File('${directory.path}/photo.jpg');
      await photo.writeAsBytes([1, 2, 3, 4, 5]);
      final store = PendingStore.memory();
      final sent = <http.Request>[];
      final first = await testClient((request) async {
        sent.add(request);
        throw http.ClientException('offline');
      }, store: store);
      await first.login('ayu', 'password');
      await expectLater(
        first.submitAttendance(
          kind: 'check_in',
          photo: photo,
          requestId: 'photo-key',
        ),
        throwsA(uncertain),
      );
      final pending = (await store.load(
        'https://example.test',
        'employee-1',
        testWorkspaceId,
      ))!;
      expect(pending.photoBase64, base64Encode([1, 2, 3, 4, 5]));
      await photo.delete();
      final restarted = await testClient((request) async {
        sent.add(request);
        return receipt(attendanceRecord);
      }, store: store);
      await restarted.login('ayu', 'password');
      expect(await restarted.recoverPending(), contains('attendance-1'));
      for (final request in sent) {
        expect(request.headers['Idempotency-Key'], 'photo-key');
        expect(request.body, contains('check_in'));
        expect(request.bodyBytes, containsAllInOrder([1, 2, 3, 4, 5]));
      }
      expect(restarted.hasPendingRequest, false);
      expect(restarted.revision, 2);
    },
  );

  test(
    'attendance retains 2 MB limit before any transport or storage',
    () async {
      final directory = await Directory.systemTemp.createTemp('large-photo-');
      addTearDown(() => directory.delete(recursive: true));
      final photo = File('${directory.path}/photo.jpg');
      await photo.writeAsBytes(List.filled(2 * 1024 * 1024 + 1, 0));
      final api = await testClient(
        (_) async => throw StateError('must not send'),
      );
      await api.login('ayu', 'password');
      await expectLater(
        api.submitAttendance(kind: 'check_in', photo: photo, requestId: 'key'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'image_too_large'),
        ),
      );
      expect(api.hasPendingRequest, false);
    },
  );

  test(
    'bon action recovery preserves encoded path action and amount',
    () async {
      final store = PendingStore.memory();
      late http.Request original;
      final first = await testClient((request) async {
        original = request;
        throw http.ClientException('offline');
      }, store: store);
      await first.login('ayu', 'password');
      await expectLater(
        first.bonAction(
          'bon/1',
          'repay',
          amount: 25000,
          requestId: 'action-key',
        ),
        throwsA(uncertain),
      );
      final restarted = await testClient((request) async {
        expect(request.url, original.url);
        expect(request.body, original.body);
        expect(request.headers['Idempotency-Key'], 'action-key');
        return receipt({
          ...bonRecord,
          'status': 'disbursed',
          'repaidAmount': 25000,
        });
      }, store: store);
      await restarted.login('ayu', 'password');
      expect(await restarted.recoverPending(), contains('bon-1'));
    },
  );

  test('failed disk persistence prevents transport', () async {
    final directory = await Directory.systemTemp.createTemp('broken-store-');
    addTearDown(() => directory.delete(recursive: true));
    final blocker = File('${directory.path}/not-a-directory');
    await blocker.writeAsString('block');
    final api = await testClient(
      (_) async => throw StateError('must not send'),
      store: PendingStore.file(File('${blocker.path}/pending.json')),
    );
    await api.login('ayu', 'password');
    await expectLater(
      api.submitBon(amount: 1, note: '', requestId: 'key'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'pending_storage'),
      ),
    );
    expect(api.revision, 1);
  });

  test('only one write may be in flight', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    var sends = 0;
    final api = await testClient((_) {
      sends++;
      started.complete();
      return response.future;
    });
    await api.login('ayu', 'password');
    final first = api.submitBon(amount: 1, note: '', requestId: 'key');
    await started.future;
    await expectLater(
      api.submitBon(amount: 1, note: '', requestId: 'key'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'busy')),
    );
    await expectLater(api.recoverPending(), throwsA(isA<ApiException>()));
    expect(sends, 1);
    response.complete(receipt());
    await first;
    expect(api.revision, 2);
  });

  test('store scopes pending by normalized base URL and user', () async {
    final store = PendingStore.memory();
    await store.save(
      'https://example.test/',
      'employee-1',
      PendingRequest(path: '/v1/bon', requestId: 'key', payload: {'amount': 1}),
    );
    final otherUser = await testClient(
      (_) async => receipt(),
      store: store,
      account: {...user, 'id': 'employee-2'},
    );
    await otherUser.login('another', 'password');
    expect(otherUser.hasPendingRequest, false);
    final otherUrl = await testClient(
      (_) async => receipt(),
      store: store,
      baseUrl: 'https://other.test',
    );
    await otherUrl.login('ayu', 'password');
    expect(otherUrl.hasPendingRequest, false);
    expect(await store.load('https://example.test', 'employee-1'), isNotNull);
  });

  test(
    'production writes require login before touching persistence or transport',
    () async {
      final api = ApiClient(
        baseUrl: 'https://example.test',
        client: MockClient((_) async => throw StateError('must not send')),
      );
      await expectLater(
        api.submitBon(amount: 1, note: '', requestId: 'key'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'unauthorized'),
        ),
      );
    },
  );

  test('expired session can log out and history exposes next page', () async {
    final api = await testClient((request) async {
      if (request.url.path.endsWith('/logout')) {
        return http.Response(
          jsonEncode({
            'ok': false,
            'error': {'code': 'unauthorized', 'message': 'Expired'},
          }),
          401,
        );
      }
      expect(request.url.queryParameters['offset'], '100');
      return http.Response(
        jsonEncode({
          'ok': true,
          'bon': [],
          'pagination': {'hasMore': true, 'nextOffset': 200},
        }),
        200,
      );
    });
    await api.logout();
    await api.bon(offset: 100);
    expect(api.bonNextOffset, 200);
  });

  test(
    'employee writes parse typed receipts and never persist credentials',
    () async {
      final store = PendingStore.memory();
      final api = await testClient(
        (_) async => http.Response(jsonEncode({'ok': true, 'user': user}), 201),
        store: store,
      );
      await api.login('ayu', 'password');
      await api.saveEmployee(name: 'Ayu', username: 'ayu', password: 'secret');
      expect(api.revision, 2);
      expect(await store.load('https://example.test', 'employee-1'), isNull);
      expect(api.hasPendingRequest, false);
    },
  );

  test(
    'malformed employee receipt is uncertain and does not increment revision',
    () async {
      final api = await testClient(
        (_) async => http.Response(jsonEncode({'ok': true}), 200),
      );
      await api.login('ayu', 'password');
      await expectLater(
        api.saveEmployee(name: 'Ayu', username: 'ayu'),
        throwsA(uncertain),
      );
      expect(api.revision, 1);
    },
  );

  test('insecure and missing endpoints fail before transport', () async {
    for (final url in [
      '',
      'http://example.test',
      'https://example.test?token=secret',
    ]) {
      final api = ApiClient(
        baseUrl: url,
        pendingStore: PendingStore.memory(),
        client: MockClient((_) async => throw StateError('must not send')),
      );
      expect(api.isConfigured, false);
      await expectLater(api.bon(), throwsA(isA<ApiException>()));
    }
  });

  test('unverified workspace blocks login before transport', () async {
    final api = ApiClient(
      baseUrl: 'https://example.test',
      pendingStore: PendingStore.memory(),
      client: MockClient((_) async => throw StateError('must not send')),
    );
    await expectLater(
      api.login('ayu', 'password'),
      throwsA(isA<ApiException>()),
    );
    expect(api.hasVerifiedWorkspace, false);
  });

  test('unclaimed workspace cannot become active', () async {
    final api = ApiClient(
      baseUrl: 'https://example.test',
      pendingStore: PendingStore.memory(),
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'id': testWorkspaceId,
            'name': 'Usaha Uji',
            'ready': false,
          }),
          200,
        ),
      ),
    );
    await expectLater(
      api.switchWorkspace(
        const WorkspaceConnection(
          origin: 'https://example.test',
          workspaceId: testWorkspaceId,
          name: 'Usaha Uji',
        ),
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'workspace_unclaimed',
        ),
      ),
    );
    expect(api.hasVerifiedWorkspace, false);
  });

  test(
    'owner claim sends one-time setup token and validates receipt',
    () async {
      late http.Request sent;
      final api = ApiClient(
        baseUrl: 'https://example.test',
        pendingStore: PendingStore.memory(),
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'ok': true,
              'token': 'c' * 64,
              'user': {
                'id': 'owner-1',
                'name': 'Pemilik',
                'username': 'pemilik',
                'role': 'owner',
                'active': true,
              },
            }),
            201,
          );
        }),
      );
      final result = await api.claimWorkspaceOwner(
        const WorkspaceConnection(
          origin: 'https://example.test',
          workspaceId: testWorkspaceId,
          name: 'Usaha',
        ),
        setupToken: 'raw-setup-token',
        name: 'Pemilik',
        username: 'pemilik',
        password: 'password rahasia 12',
        workspaceName: 'Usaha',
      );
      expect(sent.url.path, '/v1/setup/owner');
      expect(sent.url.query, isEmpty);
      expect(jsonDecode(sent.body)['setupToken'], 'raw-setup-token');
      expect(result.$1.role, 'owner');
      expect(result.$2, 'c' * 64);
    },
  );
}
