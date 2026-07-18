package com.colespringer.waxdeck

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service hosts the Flutter engine inside its media service so
// playback survives the activity; the activity base class comes from it.
class MainActivity : AudioServiceActivity()
