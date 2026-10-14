import 'dart:async';

import 'package:elly_mobile_app/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_backend.dart';

/// [FakeBackend] whose responses can be held back: [hold] makes the NEXT request to a path wait (its response is
/// computed when the request arrives, delivered when the returned completer completes). For "late response of the
/// previous session" races.
class GatedBackend extends FakeBackend {
  final Map<String, List<Completer<void>>> _holds = {};

  /// The next request to [path] (relative to /api/v1) is answered only after the returned completer completes.
  Completer<void> hold(String path) {
    final gate = Completer<void>();
    (_holds[path] ??= []).add(gate);
    return gate;
  }

  @override
  // ignore: overridden_fields
  late final ApiService api = ApiService(
    client: MockClient((req) async {
      requests.add(req);
      final path = req.url.path.replaceFirst(RegExp(r'^.*/api/v1'), '');
      final handler = routes[path];
      final response = handler == null ? http.Response('', 404) : handler(req);
      final queue = _holds[path];
      if (queue != null && queue.isNotEmpty) await queue.removeAt(0).future;
      return response;
    }),
  );
}
