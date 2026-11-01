# Bugs

List of current bugs or correctness issues. Also an area for me to keep my rambling where what I want to add is not clear.

[10-16-26] - In general, there is too much explanatory text when visuals and intuitive UI design should suffice.

[10-23-26] Inconsistent button sizing when downloading. See screenshot wide_download.png

[10-23-26] Inconsistent sizing under Admin console page. See inconsistent_admin.png.

[10-23-26] In general, need a more consistent UI experience.

[10-23-26] The books section doesn't appear until you upload a book. Inconsistent with the other sections that will always show even if empty (which is what we want since you can go to a section and upload files specfiic to that section. doing it on home requires you to select what youre uploading)

[10-23-26] In the books section home page, if you click the play button of an audiobook it brings it to the informational page and doesnt just start playing. There is a play button that appears. Even when you pause and attempt to yout the continue listening function is goes to the informational page instead of just resuming where you left off. We need a way for people to be able to just play the book or to go to the informational page if they want. Currently the always have to go to the informatinal page before they can start/resume the book.

[10-23-26] The books section doesn't have a genre or author sub sections like music has.

[10-31-26] Each chapter (separate files) of a book now shows up in the recently added and never played sections under home. If a book contains a bunch of separate files it should really only show as the full book just like how it would if it were just in a singular file.

[10-31-26] When adding music from a url, there should be a way to just accept the top / best match when choosing to identify against musicbrainz instead of putting it in the queue for the user.

[10-31-26] When approving a track against musicbrainz that was obtained from a youtube url (https://www.youtube.com/watch?v=N_qasjqcpjw&list=RDN_qasjqcpjw&start_radio=1), the album artwork used the youtube version rather than the approved version (https://musicbrainz.org/release/20e580f2-1c9c-4df6-af67-f410956cceec). Also, it claims that the music artwork came from the file when it actually came from youtube (but was supposed to come from musicbrainz or some other official artwork store). The youtube artwork should be used when the user doesn't want to do a match or if there isnt a match that was found. So it should pretty much always retrieved but should be overwritten with better sources when possible.

[10-31-26] For 1 url download from youtube, there were a total of 5 notifications (3 of which were the same "Review queue: Waiting for a review"). Thats too many. Need to polish the notification system.

[10-31-26] When you looking at the album page, the number of plays for a track is in an awkward place and it is not visually distinct/obvious enough for what it is. It can kind of seen as blending in with the track time.

[10-31-26] When downloading track from youtube, if there is no match or the user just wants to mark as unofficial, the " - Topic" should always be removed. There is no reason to ever keep that as its something youtube adds to the end of a page name for music artists.

[10-31-26] The tools tasks can have a bunch of the same task completed showing even though each was for something different. For example, the same completed tool task will show under tool tasks under tasks for 2 separate tracks that were download and there is no way to tell they were for different things. Either simplify this to just show a number of those tasks completed (maybe allowing to click on to see more information about each of the related tasks) or for the tool tasks to always show their unique information.

[10-31-26] The notifications page will show notifications that are completed (with the check mark showing so) but you can still click them and it will take you to where the noticiation would have taken you if the task still needed to be completed. For example, if you complete the waiting for review tasks, go to the notifications section, click on the notification, it will take you to the pending queue but the tasks it was for is not actually there. (side note: we need to make a proper back system. the situtation as explainted in this item does not have an obvious way to get back to where you just were even though you clicked a notification from 1 page to bring you there.)

[10-31-26] When listening to music, you can get audiobooks as part of your queue. When listening to music, you should get music (same with the others).

[10-31-26] The mouse on web (probably desktop too) doesn't change to the hand selection when you run it over parts of the minimized dock to bring it to full screen. In full screen it correctly does this when you run your mouse over blank areas that allow you to click to minimize full screen to just the dock. On a related note, the area that you are allowed to click when minimized to go full screen only appears to be from the very far left up until the current time in the song you are playing. Any blank area beyond that to the far right you cant click to full screen.

[10-31-26] Switching theme appearances is very laggy. Or maybe it just doesn't update at a high frame rate so it just looks laggy? Either way its not pleasant visually.