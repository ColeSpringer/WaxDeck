# R8 keep rules for the release build.
#
# Empty on purpose. R8 has always run on this app's release builds
# (Flutter's Gradle plugin defaults minify + shrinkResources), and the
# plugins in the graph ship their own consumer rules, so nothing here is
# needed today. The file exists so that the next thing R8 strips has an
# obvious place to be kept, instead of the fix being "turn minification
# off".
#
# The one already known: background_downloader resolves its callbacks
# reflectively, and if a download starts failing only in release with a
# ClassNotFoundException, this is the rule:
#
#   -keep class com.bbflight.background_downloader.** { *; }
#
# Resources are a separate shrinker with a separate escape hatch -
# res/raw/keep.xml, which is where the notification icon is held.
