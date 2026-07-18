/// Web variant: nothing to initialize. just_audio ships its own web backend,
/// and keeping media_kit out of this compilation unit keeps ffi out of
/// WasmGC builds.
void ensureAudioEngineInitialized() {}
