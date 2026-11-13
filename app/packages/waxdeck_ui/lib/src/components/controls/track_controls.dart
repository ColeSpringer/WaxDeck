/// The slider, the seek bar and the pointer pipeline they share.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../../icons/wax_icon.dart';
import '../../l10n/wax_l10n.dart';
import '../../tokens/colors.dart';
import '../../tokens/radii.dart';
import '../../tokens/spacing.dart';
import 'focus_ring.dart';
import 'icon_button.dart';

part 'seek_bar.dart';
part 'slider.dart';
part 'track_gestures.dart';
