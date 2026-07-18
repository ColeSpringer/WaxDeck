//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_import

import 'package:one_of_serializer/any_of_serializer.dart';
import 'package:one_of_serializer/one_of_serializer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:built_value/iso_8601_date_time_serializer.dart';
import 'package:waxdeck_api_gen/src/date_serializer.dart';
import 'package:waxdeck_api_gen/src/model/date.dart';

import 'package:waxdeck_api_gen/src/model/discovery_list.dart';
import 'package:waxdeck_api_gen/src/model/error.dart';
import 'package:waxdeck_api_gen/src/model/health.dart';
import 'package:waxdeck_api_gen/src/model/item.dart';
import 'package:waxdeck_api_gen/src/model/item_page.dart';
import 'package:waxdeck_api_gen/src/model/item_summary.dart';
import 'package:waxdeck_api_gen/src/model/job.dart';
import 'package:waxdeck_api_gen/src/model/listen_ingest_result.dart';
import 'package:waxdeck_api_gen/src/model/listen_report.dart';
import 'package:waxdeck_api_gen/src/model/listen_session.dart';
import 'package:waxdeck_api_gen/src/model/login_request.dart';
import 'package:waxdeck_api_gen/src/model/login_response.dart';
import 'package:waxdeck_api_gen/src/model/lyrics.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:waxdeck_api_gen/src/model/play_info.dart';
import 'package:waxdeck_api_gen/src/model/play_state.dart';
import 'package:waxdeck_api_gen/src/model/play_state_update.dart';
import 'package:waxdeck_api_gen/src/model/rejected_listen.dart';
import 'package:waxdeck_api_gen/src/model/search_hit.dart';
import 'package:waxdeck_api_gen/src/model/search_results.dart';
import 'package:waxdeck_api_gen/src/model/session_info.dart';
import 'package:waxdeck_api_gen/src/model/synced_line.dart';
import 'package:waxdeck_api_gen/src/model/user.dart';

part 'serializers.g.dart';

@SerializersFor([
  DiscoveryList,
  Error,
  Health,
  Item,
  ItemPage,
  ItemSummary,$ItemSummary,
  Job,
  ListenIngestResult,
  ListenReport,
  ListenSession,
  LoginRequest,
  LoginResponse,
  Lyrics,
  MediaType,
  PlayInfo,
  PlayState,
  PlayStateUpdate,
  RejectedListen,
  SearchHit,
  SearchResults,
  SessionInfo,
  SyncedLine,
  User,
])
Serializers serializers = (_$serializers.toBuilder()
      ..add(ItemSummary.serializer)
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer())
    ).build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
