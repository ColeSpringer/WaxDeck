#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <string>
#include <vector>

#include "my_application.h"

namespace {

// Whether a server takes a connection on a socket named the way
// libpipewire names one: a path, or "@" and an abstract name.
bool answers(const std::string& name) {
  sockaddr_un addr = {};
  if (name.empty() || name.size() >= sizeof(addr.sun_path)) return false;
  addr.sun_family = AF_UNIX;
  memcpy(addr.sun_path, name.c_str(), name.size() + 1);
  socklen_t size = offsetof(sockaddr_un, sun_path) + name.size() + 1;
  if (name[0] == '@') {
    addr.sun_path[0] = '\0';
    size--;
  }
  // Non-blocking, as libpipewire dials, which reads a full backlog as a
  // connection pending; it also keeps a wedged server from holding up the
  // start.
  int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
  if (fd < 0) return false;
  bool up = connect(fd, reinterpret_cast<sockaddr*>(&addr), size) == 0 ||
            errno == EAGAIN;
  close(fd);
  return up;
}

// The remote names libpipewire tries: PIPEWIRE_REMOTE, which may be a
// JSON array of them (relaxed: bare or quoted, by commas or spaces), or
// else pipewire-0.
std::vector<std::string> remotes() {
  const char* env = getenv("PIPEWIRE_REMOTE");
  std::string value = env != nullptr && env[0] != '\0' ? env : "pipewire-0";
  if (value[0] != '[') return {value};
  std::vector<std::string> names;
  size_t i = 1;
  while (i < value.size() && value[i] != ']') {
    if (strchr(", \t\r\n", value[i]) != nullptr) {
      i++;
      continue;
    }
    std::string name;
    if (value[i] == '"') {
      for (i++; i < value.size() && value[i] != '"'; i++) {
        if (value[i] == '\\' && i + 1 < value.size()) i++;
        name += value[i];
      }
      i++;
    } else {
      for (; i < value.size() && strchr(", \t\r\n]", value[i]) == nullptr; i++)
        name += value[i];
    }
    if (!name.empty()) names.push_back(name);
  }
  return names;
}

// Whether a PipeWire server answers where libpipewire looks for one: each
// remote name as given when it is a path or an abstract name, else in
// PIPEWIRE_RUNTIME_DIR (or XDG_RUNTIME_DIR, or USERPROFILE) and then in
// /run/pipewire.
bool pipewire_answers() {
  const char* dir = getenv("PIPEWIRE_RUNTIME_DIR");
  if (dir == nullptr) dir = getenv("XDG_RUNTIME_DIR");
  if (dir == nullptr) dir = getenv("USERPROFILE");
  for (const std::string& name : remotes()) {
    if (name[0] == '/' || name[0] == '@') {
      if (answers(name)) return true;
    } else if ((dir != nullptr && answers(std::string(dir) + "/" + name)) ||
               answers("/run/pipewire/" + name)) {
      return true;
    }
  }
  return false;
}

}  // namespace

int main(int argc, char** argv) {
  // mpv tries PipeWire first, at every audio output it opens and every
  // device list media_kit reads. With no PipeWire server, each try starts
  // libpipewire's loop thread and stops it at once, and a stop that races
  // the thread's start can be lost (loop_queue_invoke runs it on the
  // caller, unsignalled): mpv then waits on that thread forever, the player
  // never loads, and disposing it freezes the app, as media_kit destroys
  // mpv on this thread. Without its plugins libpipewire makes no loop, so
  // each try fails before a thread starts and mpv moves on to PulseAudio;
  // PIPEWIRE_DEBUG=0 keeps that failure from being logged at every try.
  //
  // Both reach the whole process and everything it launches, so nothing in
  // it or started from it - the pipewire-alsa plugin, a browser opened for
  // sign-in - gets PipeWire this run. With no server that costs nothing,
  // but it is decided once: a server that starts later goes unused until a
  // restart (and nothing plays if it has no pipewire-pulse), and one that
  // stops later reopens the race.
  if (getenv("SPA_PLUGIN_DIR") == nullptr && !pipewire_answers()) {
    setenv("SPA_PLUGIN_DIR", "/nonexistent", 1);
    setenv("PIPEWIRE_DEBUG", "0", 0);
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
