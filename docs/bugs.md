# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

[11-26-26] When downloading a youtube playlist, the tracks are not sent to the review queue until the entire playlist/task is finished. These should be sent to the queue as ready.

[11-26-26] When trying to download this song from youtube https://www.youtube.com/watch?v=DjPZQm4sC5E, there are some characters that do not appear correctly in the review queue. (see bad_characters.png) Weirdly, when you approve the track the characters appear correctly when you navigate to the track in the music section.

[11-26-26] When making a decision on a track in the review queue, the notification that pops up is in an awkward place. (see review_queue_bad_notification_placement.png)

[11-26-26] Notifcations don't seem to go away until you interact with them. They should show for a short period of time before going away. Users should still be able to see there are unread notications from the notification bell.

[11-26-26] I was able to break the navigation. I can't find out how to reproduce the problem though. I was on one albums page, clicked the home button, and was brought to a different albums page instead of the home page. This was saved through the browsers back and forward buttons. Clicking home again brought me back to the home page but no idea why it originally happened.

[11-26-26] The whole invite, request account system needs a revamp.

[11-26-26] When uploading a playlist through the add to library by URL, there should be interface options that allow you to create an identical playlist here and if you want to sync it (maybe even allowing to select sync period if the ui isnt too cluttered. if needed, the users can just go to the playlist and change that themselves).

[11-26-26] Tracks in the library with cover art will always have the "Art from the file" shown. This is not how its supposed to work. If the cover art is sourced from somewhere like the cover art archive, youtube, etc. then it should show where it came from. The "Art from the file" should only really be used for uploaded files that had cover art already attached. Furthermore, for example, if a user changes the artwork manually it should say "Art from USER". This needs some work in general to work properly given the various scenarios.

[11-26-26] Need to replace ";" throughout text with just normal punctuation. Seems to be the new em dash that AI agents will overuse. Stinky.

[11-26-26] When you try to edit an artist, you are given the ability to change artwork for an album? There are even options to pin the cover? Seems like mostly a copy and paste from the album editing page. Needs work (rework?). We should be able to edit the artist picture if desired.

[11-26-26] When you approve a new track for a new artist, the musicbrainz artist id is not automatically filled out for the artist. We should also have an ability to have this queued so you can try to automatically have these filled out.

[11-26-26] The listen log under listening stats doesnt user their artwork and instead just uses the initials glyph.

[11-26-26] Look into what counts as a play. I think it currently counts as ANY amount of time played. That would include skiping over tracks.

[11-27-26] When clicking the lyrics button in the minimized deck it opens from the sidebar and if the track doesn't have lyrics there is an "Add lyrics" button. If you click that button it brings you to the the edit metadata page for the track to add lyrics. However, the sidebar doesn't go away and you have to manually close it otherwise it just takes up a third of the screen (on web) for no reason. NOTE: This is mostly a problem if you are not in full screen. Lower width windows/screens have more of their usable space taken up for the lyrics sidebar. In fullscreen windows, it doesn't effect much if anything to have it open (at least at 1080p).

[11-27-26] When you go to Tasks it says "Tool tasks" in the upper left instead of just "Tasks". There is already a section under tasks called "Tool tasks".

[11-27-26] Individual library jobs under Tasks (and maybe tool tasks) don't have individual clear actions you can click. You always have to use the gargage icon to clear anything.

[11-27-26] It would be nice to have the number of active tasks appear next to the "Tasks" section in the sidebar. The number would only appear if there are active tasks not if there are none. Maybe even for the notifcations and review queue as well. not all pages have the notification bell in the upper right (should they?) [the bell should just show like a dot or something rather than the count if there are unread notifications if it isnt like that already]. This might only be a web/desktop thing. I haven't checked out it would work/look on mobile (small screens).

[11-27-26] Should change the order of sections in the lower half of the sidebar on the left. Listening stats should be at the bottom and App settings at the top at the very least. (this is just on web. might also need to be rearranged on mobile/desktop if they are also in this same order for their equivalent)

[11-27-26] Scrolling is laggy on the edit metadata page. Look into this problem in general in case it also shows in other places.