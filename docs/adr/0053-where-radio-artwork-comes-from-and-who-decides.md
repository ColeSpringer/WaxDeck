# 53. Where radio artwork comes from, and who decides

Date: 2026-08-07

## Status

Accepted. Amends ADR-0052, which introduced the external rung off by
default.

## Context

ADR-0052 gave radio a two-rung artwork ladder: a match against this
library, then a MusicBrainz plus Cover Art Archive lookup on its miss.
The second rung shipped **off**, because it sends a string a station
chose off a self-hosted machine, and that read as a self-hoster's
decision to make rather than one to inherit.

A live survey then added a third rung between them: some stations
announce a picture in their own stream metadata (`StreamArtwork`, or the
older `StreamUrl`), and a few name a logo in an `icy-logo` connect
header. That needs no third party at all, and it landed on by default.

Two things came out of running the result against real stations.

The first is how thin the announced rung is. Roughly one station in
twenty announces a per-track picture. `.977 Country`, ANTENNE BAYERN and
most of the dial announce a title and nothing else, so the ladder fell
straight through to a rung that was switched off, and the full-screen
player drew a monogram with nothing on screen to say why. The setting
existed, was never mentioned where a listener met it, and looked like a
missing feature rather than a choice.

The second is that the rung had not been working anyway. It asked the
archive about the *first* release of a matched recording and stopped, so
a current single entered twice - once digital with no sleeve, once as
the album that has one - resolved nothing. And the normalization that
built the query treated an apostrophe as a word separator, so `That's
What Tequila Does` went upstream as `that s what tequila does` and
matched nothing at all. Both are fixed; the rung resolves covers now
where before it mostly did not.

## Decision

### The external rung is on by default

Off is still one switch away, and the switch keeps its full meaning:
turned off, nothing about a station's announced title leaves this server
and the station mark is what a listener sees.

What changed is which way round the default sits. The argument for off
was that the outbound call is the operator's decision. That still holds
for the operator who cares, and they get a setting. It does not hold for
the far larger group who install a music server, play a station, and see
a grey square: they never made a decision, they inherited one, and
nothing told them so.

**Existing installs are not pinned to their current effective value.** An
unset key reads as on, so a server upgraded into this starts using the
rung. That is deliberate rather than overlooked: a migration writing
`false` into every existing database would mean the people already
running WaxDeck - the ones who reported the grey square - are the only
ones the fix never reaches. The cost of being wrong here is a paced,
cached, server-side lookup of an artist and a title; the cost of the
other choice is the feature staying broken for everyone who already has
it. Operators who had explicitly saved the setting off keep it off,
because their key is set.

This is the only setting in the server that decides whether WaxDeck
talks to a third party at all, so it stays a setting, it stays
documented, and it stays in the admin console rather than becoming a
constant.

### A picture a station repeats is a logo, not a cover

The announced rung ranks above the external one, which is right for a
per-track cover and wrong for a channel logo - and a channel logo in
`StreamUrl` on every track is a whole class of station (SomaFM among
them). Ranked above, it would park one image on the full-screen face
forever and outrank the lookup that would have found the actual sleeve.

The discriminator is free: a cover changes when the title does, a mark
does not. When a station announces the same picture against a new song,
that picture is demoted to the logo rung - where it is genuinely wanted,
since it came from the station itself - and stops being offered as the
song's cover.

### An announced picture is keyed by URL *and* title

The first key was the URL alone, on the reasoning that it changes
exactly when the picture does. It does not: serving mutable bytes from
one stable path is a common automation, and under a URL-only key the
token never changed, so the image URL never changed, so one song's cover
stayed on the face behind a long `Cache-Control`. The announced line
rides the hash, raw rather than parsed, so a station whose line does not
split into an artist and a song still gets a key that moves.

## Consequences

- A default install now reaches musicbrainz.org and coverartarchive.org
  while somebody is listening to a station whose music it does not hold.
  Paced, cached server-side, and per-server rather than per-device.
- The release notes have to say so. A default that changes outbound
  behaviour on upgrade is exactly the kind an operator should not
  discover from a firewall log.
- The setting's prose everywhere it appears - the service type, the
  spec, the admin console - says on by default, and says what turning it
  off costs.
- Demoting a repeated picture takes two announcements to notice, so the
  first track on such a station draws the logo before the ladder
  settles. Once per station per process, not per session: the verdict is
  kept with the station's last announcement, which outlives the title's
  own freshness, so a later listener meets a station already judged.
  Cheaper than the alternative, which is deciding on the first
  announcement - and deciding it there means guessing, with the guess
  landing on whichever class of station it is wrong about. Guessing
  "cover" costs one logo-announcing station one track; guessing "logo"
  costs every per-track station its first cover.
