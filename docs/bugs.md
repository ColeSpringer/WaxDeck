# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

- [9-27-26] For the minimized deck, after the update to give the currently playing audio more space to see their full information, we now have off center controls and scrunched together buttons/volume. We did not redo/update the spacing after giving the title more space. This is most obvious when playing a radio station where the controls are off center and there is a lot of dead space. See screenshots min_deck_music_track.png and min_deck_radio.png.

- [9-27-26] When playing tracks with multiple artworks in fullscreen, we should have the user be able to click the artwork to cycle through each artwork we have for the track/book whatever. We might also consider that it slowly cycles through them automatically (probably just a web/desktop feature). Obviously with the ability to turn off somewhere. This is not meant to be a radio feature.

- [9-27-26] Under library health, I'm not sure that the "Fix missing lyrics" button does anything? There is not clear feedback on what is actually occuring. There was no confirm action when you click the button it just automatically seems to do it (or at least try). Nothing seems to be queued up. No notifications pop up. No tasks appear. We need to look into this feature. More generally, we need to work on feedback for the user when they click to do something to make sure they can check or see what is happening. Needs to be done is a more subtle (proportional?) way though as we don't want to be overly in their face with every little action taken. 

- [9-27-26] Under admin console Libraries, "ItemsMatching" is 1 word and its contents are not spaced properly.

- [9-27-26] Organize files lets you preview even if you haven't changed anything. After you click preview, there is no way to cancel. You only have the ability to apply. Also, there is no actual way to change the organization. There is just the option to select waxbin-native which is the default anyway.

- [9-27-26] When playing a radio station in fullscreen, there is a lot of dead space between the album artwork and the station, title, controls, below it. we should move the things below the artwork up a little for radio. Music tracks seem OK. I did not check podcasts or audiobooks so maybe check those.