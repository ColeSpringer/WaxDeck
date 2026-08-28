// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'commit_credits.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CommitCredits extends CommitCredits {
  @override
  final String role;
  @override
  final BuiltList<String> names;

  factory _$CommitCredits([void Function(CommitCreditsBuilder)? updates]) =>
      (CommitCreditsBuilder()..update(updates))._build();

  _$CommitCredits._({required this.role, required this.names}) : super._();
  @override
  CommitCredits rebuild(void Function(CommitCreditsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CommitCreditsBuilder toBuilder() => CommitCreditsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CommitCredits && role == other.role && names == other.names;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, names.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CommitCredits')
          ..add('role', role)
          ..add('names', names))
        .toString();
  }
}

class CommitCreditsBuilder
    implements Builder<CommitCredits, CommitCreditsBuilder> {
  _$CommitCredits? _$v;

  String? _role;
  String? get role => _$this._role;
  set role(String? role) => _$this._role = role;

  ListBuilder<String>? _names;
  ListBuilder<String> get names => _$this._names ??= ListBuilder<String>();
  set names(ListBuilder<String>? names) => _$this._names = names;

  CommitCreditsBuilder() {
    CommitCredits._defaults(this);
  }

  CommitCreditsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _role = $v.role;
      _names = $v.names.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CommitCredits other) {
    _$v = other as _$CommitCredits;
  }

  @override
  void update(void Function(CommitCreditsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CommitCredits build() => _build();

  _$CommitCredits _build() {
    _$CommitCredits _$result;
    try {
      _$result =
          _$v ??
          _$CommitCredits._(
            role: BuiltValueNullFieldError.checkNotNull(
              role,
              r'CommitCredits',
              'role',
            ),
            names: names.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'names';
        names.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CommitCredits',
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
