# Bugs

List of current bugs or correctness issues.

- [7-31-2026] volume doesnt change as you drag it. only changes when you pick a spot on the slider.

- [7-31-2026] Appearance defaults to Dark instead of System Default.

- [7-31-2026] Tool tasks dont have a way to click and bring you to the finished item.

- [7-31-2026] No way to clear tool tasks. Done button is not clickable. No X indicator or anything.

- [8-1-2026] Volume slider is at the top of the screen when playing radio. It is under the "Radio" text. This is on the web when using the toggle device emulation button in dev tools. The slider doesn't go away when you undo the toggle device emulation and return to the regular web and the slider is operational (this is on top of the regular volume slider in the deck). Goes away on refresh. See out_of_place_volume_slider.png.

- [8-1-2026] When you start playing a radio station from the radio section there is a visual bug that occurs. See web_radio_visual_bug.png.

- [8-1-2026] The radio page doesnt have the same "Add a show" button in the middle of the page as podcasts. "Add a station" button. They both have the plus sign in the top right. On the same note, the homepage uses a plus button on the buttom right instead of the button in the middle or the plus sign at the top. Need to fix the inconsistency.

- [8-1-2026] When you select the music section, it bring you to a page that is just a visual representation of the drop down menu items that show. This needs to be something else. An expansion of what shows on the home page? Default to playlists?

- [8-1-2026] The popup window for adding a podcast has inconsistent sizing for the buttons when selecting "RSS" or "Youtube" as source.

- [8-1-2026] Make clicking the volume slider a little more forgiving. Need to be too accurate. (this is actually the case for all sliders as the same issue occurs when trying to click the track place when playing music)