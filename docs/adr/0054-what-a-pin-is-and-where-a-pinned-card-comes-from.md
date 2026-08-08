# 54. What a pin is, and where a pinned card comes from

Date: 2026-08-08

## Status

Accepted.

## Context

Section 6.1 gives home two shelves: the ones the server derives from the
library, and one the listener curates. Only the first shipped (ADR-0038),
because the second is not a shelf problem. It wants two things: somewhere
to keep a list that belongs to a person rather than to a machine, and a
way to add to that list from every surface a thing can be looked at on.

The radio dial answered the first question a year earlier (ADR-0034): the
preference document holds an ordered list of station pids, so a pin made
on the desktop is on the phone and signing out takes it with the account.
Nothing about that reasoning is specific to radio.

The second question is where the work is, and it is also where the
decisions are.

## Decision

**A pin is a pid in `Prefs.pinned`**, the same shape and the same rules as
`radioFavorites`: ordered, client-set, shape-validated but never resolved
on write, upper-cased to the contract's pattern, capped at 64, absent
rather than `[]` when empty. A departed entity leaves its pid behind
rather than failing a preference write, and clients draw what they can
still resolve.

**Six prefixes may be pinned**: albums, artists, release groups,
playlists, podcast shows, and books. Two exclusions are decisions rather
than omissions.

Radio stations are excluded because the dial *is* radio's pin surface.
Two pin gestures for one station would be two places to unpin it from,
and the wording collides: the dial's control is a star and says
"favourite".

Tracks and episodes are excluded because a card opens a surface, and
neither has one worth opening from home - a track's card would be a play
button that lies about being a destination. A kept set of tracks is a
playlist, and playlists pin.

**Cards come from one batched read**, `POST /library/entities`, taking
the pid list in the body the way `POST /play-states` does and answering
in request order. The order is contractual end to end - prefs order,
request order, response order, shelf order - so a future drag-to-reorder
on the shelf is a client change against the same contract.

Anything that cannot be resolved is **silently omitted**: unknown,
deleted, merged away, unsubscribed, or outside the caller's granted
libraries all leave the list one card shorter. That is the radio dial's
own display-drop semantics, and it is what lets the preference document
hold a pid nothing resolves without the next preference write failing
over it.

No `artUrl` on the response. The artwork endpoint already accepts every
prefix here except `rg-`, which statically has none, so a client builds
the URL from the pid it is holding and a release group draws a monogram
without asking.

**The affordance is an overflow menu**, not a header toggle. Album and
artist screens gain a `WaxMenuButton` they did not have; playlist, book,
and show screens gain one row in the menu they already had. A menu row
can say "Pin to Home" and "Unpin from Home", which a glyph cannot, and
the album's new overflow immediately carries a second entry (ADR-0055).

**The shelf's own cards carry the gesture too** - `ShelfRow` gained an
`onMoreItem` that reaches the `MediaCard.onMore` already there, so a long
press or a right-click on a pinned card offers to unpin it. Without that,
a pin could only be undone from the screen it was made on, which is the
surface a listener pinned it precisely so they would not have to find
again. It opens a sheet rather than unpinning outright: the gestures that
trigger it announce nothing, and a card vanishing under a slipped press
would leave somebody guessing what they had lost.

The shelf draws **all** the pins, with no "Show all" door. Every other
shelf is a glance at something a listing enumerates properly; this one is
the listing, and a pin falling off the end of a twelve-card cap would
look like a pin that failed.

## Consequences

A pinned entity that is deleted or merged away is display-dropped, and
its pid stays in the document occupying one of the 64 slots with no card
to unpin it from. This is exactly the property the radio dial has today -
`radioDialProvider` display-drops and nothing prunes the stored list - so
"radio-dial drop semantics" is symmetric rather than a shortcut. The
clean fix is a resolver response that distinguishes *departed* from
*invisible*, so a client could prune precisely the first; that rides the
deferred entry for the listing-surface rollout rather than being guessed
at here.

The pin affordance is on the five detail screens and the pinned shelf's
own cards, and not on listing rows, index buckets, or search hits.
Recorded as deferred work: it is a wider rollout of the same menu item,
not a different feature.

`Prefs.copyWith` cannot null a field, so `clearTimezone` rebuilds the
document by hand and every new field has to be added to that literal. A
regression test now asserts the whole document survives a timezone clear,
because the failure mode for this particular field is a home shelf
emptying itself when somebody clears a timezone.

The glyph is `WaxIcons.home`. No pin glyph is vendored, and adding one
would couple this to a `make icons` regeneration for a menu row.
