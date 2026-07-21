// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kind_fields.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$KindFields extends KindFields {
  @override
  final MediaType kind;
  @override
  final BuiltList<EditableField> fields;
  @override
  final BuiltList<EditableField> creditRoles;

  factory _$KindFields([void Function(KindFieldsBuilder)? updates]) =>
      (KindFieldsBuilder()..update(updates))._build();

  _$KindFields._({
    required this.kind,
    required this.fields,
    required this.creditRoles,
  }) : super._();
  @override
  KindFields rebuild(void Function(KindFieldsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  KindFieldsBuilder toBuilder() => KindFieldsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is KindFields &&
        kind == other.kind &&
        fields == other.fields &&
        creditRoles == other.creditRoles;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, fields.hashCode);
    _$hash = $jc(_$hash, creditRoles.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'KindFields')
          ..add('kind', kind)
          ..add('fields', fields)
          ..add('creditRoles', creditRoles))
        .toString();
  }
}

class KindFieldsBuilder implements Builder<KindFields, KindFieldsBuilder> {
  _$KindFields? _$v;

  MediaType? _kind;
  MediaType? get kind => _$this._kind;
  set kind(MediaType? kind) => _$this._kind = kind;

  ListBuilder<EditableField>? _fields;
  ListBuilder<EditableField> get fields =>
      _$this._fields ??= ListBuilder<EditableField>();
  set fields(ListBuilder<EditableField>? fields) => _$this._fields = fields;

  ListBuilder<EditableField>? _creditRoles;
  ListBuilder<EditableField> get creditRoles =>
      _$this._creditRoles ??= ListBuilder<EditableField>();
  set creditRoles(ListBuilder<EditableField>? creditRoles) =>
      _$this._creditRoles = creditRoles;

  KindFieldsBuilder() {
    KindFields._defaults(this);
  }

  KindFieldsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _fields = $v.fields.toBuilder();
      _creditRoles = $v.creditRoles.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(KindFields other) {
    _$v = other as _$KindFields;
  }

  @override
  void update(void Function(KindFieldsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  KindFields build() => _build();

  _$KindFields _build() {
    _$KindFields _$result;
    try {
      _$result =
          _$v ??
          _$KindFields._(
            kind: BuiltValueNullFieldError.checkNotNull(
              kind,
              r'KindFields',
              'kind',
            ),
            fields: fields.build(),
            creditRoles: creditRoles.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'fields';
        fields.build();
        _$failedField = 'creditRoles';
        creditRoles.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'KindFields',
          _$failedField,
          e.toString(),
        );
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
