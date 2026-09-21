# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

- [9-21-26] The bell's menu can go away on its own, taking unread news with it.
  In the 2026-09-21 soak (actions run 35601054527, pass 3) the menu
  opened with an upload row in it, the row was gone under five seconds
  later with nothing touching it, and home refetched every shelf in the
  same window. Not reproduced locally, so the trace is the only
  evidence and the mechanism is unknown; what makes it worth keeping is
  that a hint leaves the bell once it has been drawn, so a menu that
  closes by itself reads the news on the reader's behalf.
