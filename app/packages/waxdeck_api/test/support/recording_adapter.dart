import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// One request as it reached the transport: the wire, not the call.
class Sent {
  Sent(this.options, this.body);

  final RequestOptions options;

  /// The bytes of the request body, drained from the transport's stream.
  final List<int> body;

  String get method => options.method;

  /// The path below `/api/v1`.
  String get path => options.uri.path.replaceFirst('/api/v1', '');

  /// The query as it was sent: every key to every value of it, as text.
  Map<String, List<String>> get query => options.uri.queryParametersAll;

  /// The body decoded as JSON, null when none was sent.
  Object? get json => body.isEmpty ? null : jsonDecode(utf8.decode(body));

  String? get contentType => options.contentType;

  String? get contentLength =>
      options.headers[Headers.contentLengthHeader]?.toString();

  Duration? get receiveTimeout => options.receiveTimeout;
}

/// Records every request a client sends and answers it: with the queued
/// answers in order, then with [body] at [status], as JSON. A null [body]
/// answers an empty body.
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter({this.status = 200, this.body});

  /// An adapter that refuses every request as the server does.
  RecordingAdapter.refusing()
    : status = 400,
      body = const {'code': 'invalid-request', 'message': 'refused'};

  int status;
  Object? body;

  /// Every request, in the order it was sent.
  final List<RequestOptions> requests = [];

  /// The same requests with their bodies read.
  final List<Sent> sent = [];

  final List<(int, Object?)> _queued = [];

  /// Answers the next request not yet answered with [status] and [body].
  void enqueue(int status, [Object? body]) => _queued.add((status, body));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    requests.add(options);
    sent.add(Sent(options, bytes));
    final (answerStatus, answerBody) = _queued.isEmpty
        ? (status, body)
        : _queued.removeAt(0);
    return ResponseBody.fromString(
      answerBody == null ? '' : jsonEncode(answerBody),
      answerStatus,
      headers: {
        if (answerBody != null)
          Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A client whose transport is [adapter].
WaxDeckClient clientOn(
  HttpClientAdapter adapter, {
  String baseUrl = 'http://host:4420',
  Duration chunkStall = WaxDeckClient.defaultChunkStall,
}) => WaxDeckClient(
  baseUrl: baseUrl,
  dio: Dio()..httpClientAdapter = adapter,
  chunkStall: chunkStall,
);

/// The one request [call] sends, for a call whose answer is not under
/// test: an answer the client cannot read is let through, so the request is
/// what is left to look at. The server answers [answer] (an empty object
/// unless given).
Future<Sent> requestOf(
  Future<Object?> Function(WaxDeckClient client) call, {
  Object? answer = const <String, Object?>{},
}) async {
  final adapter = RecordingAdapter(body: answer);
  try {
    await call(clientOn(adapter));
  } on WaxDeckApiException {
    // Not an answer the call can read.
  }
  return adapter.sent.single;
}
