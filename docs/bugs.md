# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

- [9-26-26] When editing metadata, the empty image artwork slots have an ugly "2(" as the image (that might just be for the track 2morrow as I did not check other tracks). We might want to standardize these empty images to something less ugly.

- [9-26-26] When editing metadata, the text for "Pin this cover" is too wordy.

- [9-26-26] You can't select / copy help text when editing metadata (such as the text attached to "Pin this cover"). Have not tested other areas but we need to look into it generally.

- [9-26-26] When on the homescreen, the arrow showing that a shelf has more to its row that you can click to scroll through is hard to see with dark artwork (at least in dark mode).

- [9-26-26] The layout when using the radio fullscreen on web is clunky looking. See screenshot fullscreen_radio_layout.png.

- [9-26-26] When playing the radio, the first track did not retrieve any cover art even though it played for a couple minutes. Was fine for the next tracks. Might have been a one off but need to look into.

- [9-26-26] Clicking the heart to "unsave" a radio song doesn't remove it from the saved from the radio playlist.

- [9-26-26] Radio titles (long titles in general?) are still cut off in the minimized deck. It attempts to scroll the text but 1. it doesn't scroll all the way for the entire title to show. its still cut off when it scrolls "all the way" to the right. 2. It attempts the scroll more than once but the pacing between scrolls is a little high. We might consider extending the area to the right a little bit as it currently feels like a more minor piece of the deck than it should be.

- [9-26-26] With the deck minimized, when you skip tracks the seek bar and other elements resize for every track. This seems due to some elements disapearring momentarily and the current and end times also disapearing and things being redrawn. we need to make this more stable so to not be so jarring.