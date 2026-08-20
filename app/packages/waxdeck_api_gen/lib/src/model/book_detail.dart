//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:waxdeck_api_gen/src/model/book_settings.dart';
import 'package:built_collection/built_collection.dart';
import 'package:waxdeck_api_gen/src/model/chapter_mark.dart';
import 'package:waxdeck_api_gen/src/model/art_source.dart';
import 'package:waxdeck_api_gen/src/model/book_part.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'book_detail.g.dart';

/// Full audiobook detail. All positions are book-timeline milliseconds spanning every part. 
///
/// Properties:
/// * [pid] - Book PID.
/// * [title] - Book title.
/// * [subtitle] - Subtitle, when known.
/// * [artSource] - Where the cover this book answers came from, for the mark under it. Absent when the book has no artwork, or when the answering image carries no attribution. 
/// * [authors] - Author display names, in credit order.
/// * [narrators] - Narrator display names, in credit order.
/// * [series] - Series name, when the book belongs to one.
/// * [seriesSequence] - Position within the series, as the source states it (decimals like `1.5` are preserved). 
/// * [publisher] - Publisher, when known.
/// * [asin] - Audible ASIN, when known.
/// * [isbn] - ISBN, when known.
/// * [edition] - Edition label, when known.
/// * [abridged] - Whether this edition is abridged, when known.
/// * [descriptionHtml] - Book description as sanitized HTML (server-side allowlist; safe to render directly). 
/// * [durationMs] - Total duration across all parts, in milliseconds.
/// * [artUrl] - Origin-relative URL of the book's artwork endpoint.
/// * [chapters] - Chapters on the book timeline, ordered by `startMs`.
/// * [parts] - Backing files in reading order.
/// * [settings] 
@BuiltValue()
abstract class BookDetail implements Built<BookDetail, BookDetailBuilder> {
  /// Book PID.
  @BuiltValueField(wireName: r'pid')
  String get pid;

  /// Book title.
  @BuiltValueField(wireName: r'title')
  String get title;

  /// Subtitle, when known.
  @BuiltValueField(wireName: r'subtitle')
  String? get subtitle;

  /// Where the cover this book answers came from, for the mark under it. Absent when the book has no artwork, or when the answering image carries no attribution. 
  @BuiltValueField(wireName: r'artSource')
  ArtSource? get artSource;

  /// Author display names, in credit order.
  @BuiltValueField(wireName: r'authors')
  BuiltList<String> get authors;

  /// Narrator display names, in credit order.
  @BuiltValueField(wireName: r'narrators')
  BuiltList<String> get narrators;

  /// Series name, when the book belongs to one.
  @BuiltValueField(wireName: r'series')
  String? get series;

  /// Position within the series, as the source states it (decimals like `1.5` are preserved). 
  @BuiltValueField(wireName: r'seriesSequence')
  String? get seriesSequence;

  /// Publisher, when known.
  @BuiltValueField(wireName: r'publisher')
  String? get publisher;

  /// Audible ASIN, when known.
  @BuiltValueField(wireName: r'asin')
  String? get asin;

  /// ISBN, when known.
  @BuiltValueField(wireName: r'isbn')
  String? get isbn;

  /// Edition label, when known.
  @BuiltValueField(wireName: r'edition')
  String? get edition;

  /// Whether this edition is abridged, when known.
  @BuiltValueField(wireName: r'abridged')
  bool? get abridged;

  /// Book description as sanitized HTML (server-side allowlist; safe to render directly). 
  @BuiltValueField(wireName: r'descriptionHtml')
  String? get descriptionHtml;

  /// Total duration across all parts, in milliseconds.
  @BuiltValueField(wireName: r'durationMs')
  int get durationMs;

  /// Origin-relative URL of the book's artwork endpoint.
  @BuiltValueField(wireName: r'artUrl')
  String? get artUrl;

  /// Chapters on the book timeline, ordered by `startMs`.
  @BuiltValueField(wireName: r'chapters')
  BuiltList<ChapterMark> get chapters;

  /// Backing files in reading order.
  @BuiltValueField(wireName: r'parts')
  BuiltList<BookPart> get parts;

  @BuiltValueField(wireName: r'settings')
  BookSettings? get settings;

  BookDetail._();

  factory BookDetail([void updates(BookDetailBuilder b)]) = _$BookDetail;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookDetailBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookDetail> get serializer => _$BookDetailSerializer();
}

class _$BookDetailSerializer implements PrimitiveSerializer<BookDetail> {
  @override
  final Iterable<Type> types = const [BookDetail, _$BookDetail];

  @override
  final String wireName = r'BookDetail';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'pid';
    yield serializers.serialize(
      object.pid,
      specifiedType: const FullType(String),
    );
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.subtitle != null) {
      yield r'subtitle';
      yield serializers.serialize(
        object.subtitle,
        specifiedType: const FullType(String),
      );
    }
    if (object.artSource != null) {
      yield r'artSource';
      yield serializers.serialize(
        object.artSource,
        specifiedType: const FullType(ArtSource),
      );
    }
    yield r'authors';
    yield serializers.serialize(
      object.authors,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'narrators';
    yield serializers.serialize(
      object.narrators,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.series != null) {
      yield r'series';
      yield serializers.serialize(
        object.series,
        specifiedType: const FullType(String),
      );
    }
    if (object.seriesSequence != null) {
      yield r'seriesSequence';
      yield serializers.serialize(
        object.seriesSequence,
        specifiedType: const FullType(String),
      );
    }
    if (object.publisher != null) {
      yield r'publisher';
      yield serializers.serialize(
        object.publisher,
        specifiedType: const FullType(String),
      );
    }
    if (object.asin != null) {
      yield r'asin';
      yield serializers.serialize(
        object.asin,
        specifiedType: const FullType(String),
      );
    }
    if (object.isbn != null) {
      yield r'isbn';
      yield serializers.serialize(
        object.isbn,
        specifiedType: const FullType(String),
      );
    }
    if (object.edition != null) {
      yield r'edition';
      yield serializers.serialize(
        object.edition,
        specifiedType: const FullType(String),
      );
    }
    if (object.abridged != null) {
      yield r'abridged';
      yield serializers.serialize(
        object.abridged,
        specifiedType: const FullType(bool),
      );
    }
    if (object.descriptionHtml != null) {
      yield r'descriptionHtml';
      yield serializers.serialize(
        object.descriptionHtml,
        specifiedType: const FullType(String),
      );
    }
    yield r'durationMs';
    yield serializers.serialize(
      object.durationMs,
      specifiedType: const FullType(int),
    );
    if (object.artUrl != null) {
      yield r'artUrl';
      yield serializers.serialize(
        object.artUrl,
        specifiedType: const FullType(String),
      );
    }
    yield r'chapters';
    yield serializers.serialize(
      object.chapters,
      specifiedType: const FullType(BuiltList, [FullType(ChapterMark)]),
    );
    yield r'parts';
    yield serializers.serialize(
      object.parts,
      specifiedType: const FullType(BuiltList, [FullType(BookPart)]),
    );
    if (object.settings != null) {
      yield r'settings';
      yield serializers.serialize(
        object.settings,
        specifiedType: const FullType(BookSettings),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BookDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookDetailBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'pid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pid = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'subtitle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.subtitle = valueDes;
          break;
        case r'artSource':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ArtSource),
          ) as ArtSource;
          result.artSource.replace(valueDes);
          break;
        case r'authors':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.authors.replace(valueDes);
          break;
        case r'narrators':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.narrators.replace(valueDes);
          break;
        case r'series':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.series = valueDes;
          break;
        case r'seriesSequence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.seriesSequence = valueDes;
          break;
        case r'publisher':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.publisher = valueDes;
          break;
        case r'asin':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.asin = valueDes;
          break;
        case r'isbn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.isbn = valueDes;
          break;
        case r'edition':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.edition = valueDes;
          break;
        case r'abridged':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.abridged = valueDes;
          break;
        case r'descriptionHtml':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.descriptionHtml = valueDes;
          break;
        case r'durationMs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationMs = valueDes;
          break;
        case r'artUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.artUrl = valueDes;
          break;
        case r'chapters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ChapterMark)]),
          ) as BuiltList<ChapterMark>;
          result.chapters.replace(valueDes);
          break;
        case r'parts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(BookPart)]),
          ) as BuiltList<BookPart>;
          result.parts.replace(valueDes);
          break;
        case r'settings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BookSettings),
          ) as BookSettings;
          result.settings.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookDetail deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookDetailBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

