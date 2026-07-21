// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tool_task_page.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ToolTaskPage extends ToolTaskPage {
  @override
  final BuiltList<ToolTask> tasks;
  @override
  final String? nextCursor;

  factory _$ToolTaskPage([void Function(ToolTaskPageBuilder)? updates]) =>
      (ToolTaskPageBuilder()..update(updates))._build();

  _$ToolTaskPage._({required this.tasks, this.nextCursor}) : super._();
  @override
  ToolTaskPage rebuild(void Function(ToolTaskPageBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ToolTaskPageBuilder toBuilder() => ToolTaskPageBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ToolTaskPage &&
        tasks == other.tasks &&
        nextCursor == other.nextCursor;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, tasks.hashCode);
    _$hash = $jc(_$hash, nextCursor.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ToolTaskPage')
          ..add('tasks', tasks)
          ..add('nextCursor', nextCursor))
        .toString();
  }
}

class ToolTaskPageBuilder
    implements Builder<ToolTaskPage, ToolTaskPageBuilder> {
  _$ToolTaskPage? _$v;

  ListBuilder<ToolTask>? _tasks;
  ListBuilder<ToolTask> get tasks => _$this._tasks ??= ListBuilder<ToolTask>();
  set tasks(ListBuilder<ToolTask>? tasks) => _$this._tasks = tasks;

  String? _nextCursor;
  String? get nextCursor => _$this._nextCursor;
  set nextCursor(String? nextCursor) => _$this._nextCursor = nextCursor;

  ToolTaskPageBuilder() {
    ToolTaskPage._defaults(this);
  }

  ToolTaskPageBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _tasks = $v.tasks.toBuilder();
      _nextCursor = $v.nextCursor;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ToolTaskPage other) {
    _$v = other as _$ToolTaskPage;
  }

  @override
  void update(void Function(ToolTaskPageBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ToolTaskPage build() => _build();

  _$ToolTaskPage _build() {
    _$ToolTaskPage _$result;
    try {
      _$result =
          _$v ?? _$ToolTaskPage._(tasks: tasks.build(), nextCursor: nextCursor);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'tasks';
        tasks.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'ToolTaskPage',
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
