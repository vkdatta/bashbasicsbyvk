declare -F _lt_b >/dev/null 2>&1 || { _lt_b(){ :; }; _lt_e(){ :; }; _lt_enter(){ :; }; _lt_ready(){ :; }; _lt_mark(){ :; }; }   # loadtime hooks: no-ops when the recorder is not loaded
# bashbasicsbyvk_settings_desc.sh — a plain-words explanation of EVERY Settings screen and row
# ════════════════════════════════════════════════════════════════════════════
#  Shown above the suggestion row (the dim row right above "Select:") of every Settings screen: the text of the HIGHLIGHTED row,
#  or of the screen itself while nothing is highlighted.  Written for a person who has never heard of a "buffer" or a "nuke time":
#  what it does, when to change it, what is safe.  Type  ?  +  Enter on a Settings screen to read the whole text when it is long.
#
#  Keys are  <screen title>|<row tag>  (the title and tags are the ones the screen gives _st_run / _st_add) and  <screen title>|*  for the screen.
#  A key can be made specific with a prefix:  "<parent screen>›<title>|<tag>"  or, inside Menu specific,  "<menu name>›<title>|<tag>".
#  A new setting needs ONE line here; without a line the screen simply shows no description (nothing breaks).
#  Lazy: the table is built the first time a Settings screen is drawn, never at start-up.
# ════════════════════════════════════════════════════════════════════════════
declare -gA _ST_DESC=()
_ST_DESC_LOADED=0
_st_desc_load() {
  (( _ST_DESC_LOADED )) && return 0
  _ST_DESC_LOADED=1
  local k t
  while IFS=$'\t' builtin read -r k t; do [ -n "$k" ] && _ST_DESC["$k"]="$t"; done <<'BVK_DESC_EOF'
Settings|*	This is the control room of the program. Every item below opens a smaller screen where you can change how the program looks, what it hides, how it sorts things and how it behaves when it talks to the cloud. Nothing here changes your files. Choices are saved the moment you make them and are remembered the next time you start the program. Move with the arrow keys or type a number and press Enter to open an item; type u to go back one step, or q to leave Settings completely.
Settings|display	Everything about how your list of files looks on the screen: whether files whose names start with a dot are visible, the order they are listed in, which extra details are written after each name, how files are grouped, how many items count as a big folder, and whether you can use mouse or touch. Open this if the list looks wrong, too crowded, or hard to read. None of these options changes, moves or deletes any of your files.
Settings|filters	Two helpers that narrow a long list down to the few items you care about. The Display filter hides every item that does not match a rule you write. The Search filter is the quick search you start by typing an equals sign. Open this screen to decide how strict those searches are and whether the Display filter should be remembered. Filters only change what you see on the screen, never the files themselves.
Settings|colors	Choose the colour of the terminal background and of the text. This is useful if the default black-and-white look is hard on your eyes, if you use the program outdoors, or if you simply prefer a different style. The colours are also written into your shell start-up file so they come back automatically the next time you open the terminal. Nothing about your files is touched.
Settings|files	Settings for zip and compressed files. Here you decide which kind of compressed file the program makes when you pack files together (zip, tar, tar.gz, tar.xz, tar.bz2, 7z, tar.zst, tar.lz4, skill, or ask each time) and whether hidden files that sit inside a folder you are packing should be included. Open this when you share archives with people who use a different kind of computer, or when your archives seem to be missing files.
Settings|buffers	A buffer is a waiting room where the program holds a set of items you collected, ready for a later copy, move, shortcut, bookmark or selection. Each set has a name. This screen decides what happens when you save a new set under a name that is already used inside that same waiting room: add the new items to the old set, replace the old set, refuse, or ask you every time. It protects you from accidentally mixing up or overwriting sets.
Settings|findrep	Find and replace searches inside many files at once and can change the text it finds. Every little decision it needs, such as whether capital letters matter or whether sub-folders are included, can be fixed here once so you are not asked every time, or you can choose Ask every time to stay in control. Open this screen if the search finds too much, too little, or asks too many questions.
Settings|fileapi	File API is the online part of the program: temporary share links, backups, saved files and background snapshots stored in the cloud. Open this to decide how long things stay online before they delete themselves, whether you want a price warning before something that costs credits, and whether files are backed up before they are deleted. If you never use the cloud features you can leave all of this alone.
Settings|menuspec	Some screens, such as your list of links, your backups or your pending uploads, can be sorted in their own way, separate from the normal file list. Each item here belongs to exactly one such screen. Changing it only affects that one screen and leaves the order of your normal folders and all other screens as they are. Choose a screen to pick how its list is ordered.
Settings|system	Settings about your device rather than about the program: which timezone the clock in the program follows, and a one-time helper that adds comfortable defaults to the nano text editor. Open this if times shown by the program are off by some hours, or if you want nano to behave in a friendlier way.
Settings|reset	Puts every setting back to the value it had when you first installed the program. Use it if you changed many things and the program now behaves in a way you do not like and cannot undo one by one. Your files, links, backups and cloud data are not touched; only the choices made in Settings are forgotten. You will be asked which text colour to finish with.
Reset all settings|*	This is the big undo button for Settings. Choosing one of the two rows puts every choice back to the original value: hidden files, sort order, details, grouping, filters, buffers, find and replace, upload and zip choices, cloud timings and colours. The only question is which text colour you want afterwards. Your files and everything stored online stay exactly as they are.
Reset all settings|normal	Reset everything to the original choices and use the normal white text on a black background. Pick this when you want the standard look. All your own choices in Settings are forgotten, but none of your files, links or backups are touched. There is no second question, so be sure before you choose it.
Reset all settings|coder	Reset everything to the original choices but use green text on a black background, the classic hacker look. Pick this if you like the coder style or want better contrast on a dark screen. All your own choices in Settings are forgotten, but none of your files, links or backups are touched. There is no second question, so be sure before you choose it.
Display|*	How the list of files looks and behaves. Choose a row to open it. Each row shows its current value on the right. Nothing here can change, move or delete a file; it only changes what you see.
Display|hidden	Decides whether hidden files are shown. On computers like yours, any file or folder whose name starts with a dot, such as .config or .bashrc, is hidden on purpose because it usually holds technical settings that should not be touched by accident. Hiding them keeps the list short and tidy; showing them lets you see and open everything. This also affects searches and uploads that are set to follow this choice.
Display|sort	Decides the order in which files and folders are listed: alphabetical, reverse alphabetical, newest or oldest first, or biggest or smallest first. A good order saves a lot of scrolling, for example newest first when you look for a file you just downloaded. This is the general order for normal folders; some special screens have their own order under Menu specific.
Display|details	Chooses which small facts are written after each file name in the list, such as the file type, its size, the time it was last changed, or how many things are inside a folder. More details make the list wider, so on a narrow phone screen fewer is easier to read. You can also pick how the time is written, from just the year up to the full date and clock time.
Display|group	Groups a long list under headings so that you scroll less. You can group by file type, by year, by month or by exact date, and you can use several levels at once, for example year and then month. This is very helpful for photos, downloads or documents that pile up over time. Grouping only changes how things are displayed; files are never moved.
Display|index	Sets how many items a folder may hold before the program stops listing everything and instead shows short groups, for example by first letters, so the screen stays quick and readable. A folder with thousands of files would otherwise be slow and endless to scroll. A higher number shows more at once but can feel slower; a lower number switches to groups sooner. The usual value is 200.
Display|anim	Chooses how screens appear. Both styles that exist today show the new screen immediately, so you will not see a difference in speed. The setting is kept so that the look of screen changes can be extended in the future. If you are unsure, leave it as it is; changing it cannot affect your files or the program's behaviour.
Display|mouse	Turns mouse and touch control on or off. When it is on, you can tap or click a number to pick it, tap twice to open it, and scroll by swiping or with the mouse wheel. When it is off, only the keyboard works and your terminal keeps its own normal copy-and-paste selection. Turn it off if taps open things by accident or if you want to select text freely.
Hidden files|*	Choose whether hidden files and folders, the ones whose names start with a dot, appear in your lists. They are hidden by default because they usually contain technical settings that are easy to damage. Your choice is saved immediately and also influences uploads, zips and searches that are set to follow this setting.
Hidden files|hide	Keep dot-files and dot-folders out of sight. The lists are shorter and cleaner, and you cannot accidentally open or change a technical settings file. This is the safest choice for everyday use and the right one if you are not sure. You can switch to showing them at any time.
Hidden files|show	Show everything, including files and folders that start with a dot. Choose this when you need to edit a settings file such as .bashrc, check what a program left behind, or clean up. Lists become longer, and it is easier to open or delete something important by mistake, so be careful.
Sort order|*	Decide how the items in this list are put in order. The row with the mark is the order in use now. The change happens immediately and is remembered. It only changes the order on the screen; no file is renamed or moved.
Sort order|az	Alphabetical order from A to Z, like a dictionary. Good for finding something when you know its name.
Sort order|za	Reverse alphabetical order, from Z back to A. Useful when the names you want tend to be near the end of the alphabet, for example files named with dates that count upwards.
Sort order|new	The most recently changed items are at the top. This is the best choice when you are looking for something you just downloaded, saved or edited.
Sort order|old	The items that have not been touched for the longest time are at the top. Useful for finding old files you may want to clean up or archive.
Sort order|big	The biggest files are at the top. Helpful when your phone is running out of space and you want to see what uses the most room.
Sort order|small	The smallest items are at the top and the biggest at the bottom. Handy to spot empty or tiny files that may be leftovers.
Sort order|cr_old	Sorted by the date the entry was created, oldest first. You read the list from the beginning of its history to the present.
Sort order|cr_new	Sorted by the date the entry was created, newest first, so the things you made most recently are always on top.
Sort order|mo_old	Sorted by the date the entry was last changed, oldest first. Good for spotting things that have not been touched for a long time.
Sort order|mo_new	Sorted by the date the entry was last changed, newest first, so recent activity is at the top.
Sort order|size_big	Largest first. You see immediately which entries take the most space.
Sort order|size_small	Smallest first. You see the tiny entries on top and the large ones at the bottom.
Sort order|exp_long	Entries that will stay online longest are at the top. Good to see what is safe for a long time.
Sort order|exp_short	Entries that are about to expire are at the top, so you can extend or save them before they disappear. A good default if you worry about losing something.
Sort order|from_az	Sorted by the sender's name from A to Z, so everything sent to you by the same person sits together.
Sort order|from_za	Sorted by the sender's name from Z back to A.
Sort order|seen_old	Devices you have not used for the longest time are at the top, which helps you find computers you no longer use.
Sort order|seen_new	Devices you used most recently are at the top, which is usually the one you are working on now.
Sort order|snaps_most	The device with the most saved snapshots is first. Useful to see where most of your backup history lives.
Sort order|snaps_few	The device with the fewest snapshots is first. Useful to find devices that are hardly protected.
Sort order|last_old	The folder whose last snapshot is oldest is first, so the ones that have not been protected for a while come first.
Sort order|last_new	The folder with the most recent snapshot is first, so the ones just protected are on top.
Sort order|srv	No sorting of your own: the list stays in the order it arrives in, which is the program's normal order.
Sort order|pct_high	Uploads that are closest to finished are at the top, so you can see which ones will complete soon.
Sort order|pct_low	Uploads that have barely started are at the top, so you can see which ones need the most attention.
Pending uploads (pn)›Sort order|srv	This computer's own unfinished uploads are shown first, followed by the ones only the server knows about. It is the usual order and a good starting point because the items you started yourself are the ones you most likely want to continue.
Snapshots › Paths of a device›Sort order|srv	The list stays in the order the server delivers it, with no extra sorting. Pick one of the other orders if you want the most recently or least recently protected folders on top.
File details|*	Pick the small facts written after each name in the list. Tick as many as you want; the ones with a cross are shown. Below them you can choose how a date and time is written. Everything is only a matter of display and has no effect on your files.
File details|sfx:ext	Shows the file type, for example txt, jpg or pdf, after the name. It tells you at a glance what kind of file something is without opening it. Folders do not have a type.
File details|sfx:size	Shows how big each file is, for example 12 KB or 3 MB. Useful to spot very large files that fill up your storage, or to judge if a download is complete.
File details|sfx:time	Shows when each item was last changed. It helps you tell old and new versions apart and find the file you edited yesterday. How the time is written is decided by the time format below.
File details|sfx:children	For folders, shows how many items are inside. This lets you see which folders are empty or very full without opening them. Plain files do not show a number.
File details|tf:year	Time is shown as the year only, such as 2026. The shortest form, good on narrow screens when only the age of a file matters.
File details|tf:month	Time is shown as the month only. Short and tidy, but without the year you cannot tell two years apart.
File details|tf:date	Time is shown as the day of the month only. Very short; best used together with grouping by month.
File details|tf:datetime	Time is shown as the day plus the clock time. Good for files changed recently, when the exact hour matters.
File details|tf:monthdate	Time is shown as month and day plus the clock time. A balance between short and informative for things changed this year.
File details|tf:full	The complete date with year plus the clock time. The longest and most exact form, ideal when you need to know precisely when something was changed.
Group by|*	Group the file list under headings. Tick the levels you want; with more than one, the order matters and you can change it with the left and right arrow keys. Grouping only changes how things are shown. It does not move files.
Group by|ext	Group the items by file type, so all photos, all documents and all archives sit under their own heading. Great for tidying a mixed download folder with your eyes.
Group by|year	Group the items by the year they were last changed. Helps you find old things quickly and gives long lists a clear structure.
Group by|month	Group the items by month of the year. Combine it with year to see where a long run of files from one period starts and ends.
Group by|date	Group the items by exact day. Perfect for photos or notes made daily, because each day gets its own heading.
Big-folder limit|*	When a folder holds more items than this number, the program shows short groups instead of the whole list, which keeps the screen fast and readable. You can change the number or put it back to the usual value of 200.
Big-folder limit|set	Type a new number of items. Pick a larger value if your phone is fast and you like to see everything at once, or a smaller value if long lists are slow or tiring to scroll. It must be a whole number above zero.
Big-folder limit|reset	Put the limit back to the standard 200 items. Use it if you changed the number and the lists now feel too long or too short.
Animation|*	Choose how screens appear, separately for the main screens and for the inner screens such as functions and switching. At the moment both styles show the screen instantly, so you will see no difference.
Animation|o:pop	For the main screens: the whole screen appears at once. This is quick and clear and is the standard.
Animation|o:carpet	For the main screens: the screen is drawn in a rolling style that today still appears instantly. No delay is added.
Animation|i:pop	For the inner screens such as functions and switching: the whole screen appears at once. This is the standard.
Animation|i:carpet	For the inner screens such as functions and switching: a rolling drawing style that today still appears instantly.
Mouse / touch|*	Decide whether you can use a mouse or your finger. It only changes how you operate the program, not what it does.
Mouse / touch|v:on	Mouse and touch work: tap or click a number to pick it, tap twice quickly to open it, and swipe or use the wheel to scroll. To select and copy text on screen you may need to hold the Shift key. Recommended for phones.
Mouse / touch|v:off	Only the keyboard is used. Taps and clicks go back to your terminal, so selecting and copying text works in the usual way. Choose this if taps open things you did not mean to open.
Filters|*	Two ways of narrowing a long list. The Display filter hides everything that does not match a rule. The Search filter is the quick search started by typing an equals sign. Choose a row to set up how each one behaves.
Filters|dfilter	The Display filter shows only the items that match a rule you write, for example only csv files or only files smaller than 3 MB, and hides the rest in the folder you are in. Open it to set, clear or save a filter as a preset, or to decide whether it is remembered. The hidden items are not deleted, they are just not shown.
Filters|filter	The Search filter is the live search you start by typing an equals sign followed by a few letters. Open this to choose how closely names must match, how hidden files are treated, and whether the search also looks inside sub-folders. It never changes your files.
Display filter  (.d)|*	Control the Display filter, which shows only the items in the current folder that match a rule and hides the others. You can set a rule, clear it, apply or delete a saved preset, and decide whether the filter is kept when the program restarts.
Display filter  (.d)|set	Type a rule, such as the file type csv or a size limit, and from then on only matching items are listed in this folder. It is a quick way to concentrate on one kind of file. The other items are only hidden from view, not removed.
Display filter  (.d)|clear	Remove the active filter so that every item of the folder is shown again. Use this when you cannot find a file and suspect that a filter is hiding it.
Display filter  (.d)|run	Apply a filter you saved earlier by picking its name from a list. Saves typing when you use the same rule often, for example your photo or document filter.
Display filter  (.d)|save	Save the filter that is active now under a name of your choice so that you can apply it again in one step later. Good for rules you use regularly.
Display filter  (.d)|del	Remove a saved filter preset from the list. Only the saved rule is deleted; no file is touched. Use it to keep your list of presets short and tidy.
Display filter  (.d)|persist	Tick this to keep the active filter when you close and reopen the program. Leave it unticked, the standard, and the filter is cleared at every start, so a forgotten filter can never hide files from you next time.
Display filter  (.d)|help	Show a short guide with examples of how to write filter rules. Read it if you do not know what to type in Set filter.
Apply a preset|*	A preset is a filter rule you saved before. Once you have saved some, they appear here so you can apply one with a single choice.
Delete a preset|*	Pick a saved filter preset to remove it. Only the saved rule is removed; none of your files are changed.
Search filter  (=)|*	These choices control the quick search that starts when you type an equals sign and some letters: how exactly names must match, how hidden files are handled, and whether sub-folders are searched too.
Search filter  (=)|m:partial	A name matches if it contains your letters anywhere. Type rep and you also find report and prepare. It finds more and is the easiest for everyday use.
Search filter  (=)|m:exact	A name matches only if it begins with the letters you typed. It finds fewer items and is better when a folder is full of similar names.
Search filter  (=)|h:respect	The search follows your general Hidden files setting, so hidden files appear in results only if you chose to show them. Predictable and the standard.
Search filter  (=)|h:include	Hidden files are always searched, even if they are hidden in your normal lists. Use it when you hunt for settings files.
Search filter  (=)|h:exclude	Hidden files are never part of the results, whatever your general setting says. Keeps results clean.
Search filter  (=)|r:false	The search looks only at the folder you are viewing. It is fast and the results are easy to understand.
Search filter  (=)|r:true	The search also looks inside every sub-folder below the current one. You find a file wherever it hides, but a big folder tree may take a moment, and a loading bar tells you it is working.
Colors|*	Choose the background and the text colour of the terminal. Changes apply immediately and are saved for the next start. Your files are not affected.
Colors|bg	Pick the colour behind the text. The standard is black. A dark background is easier on the eyes at night; you may prefer something lighter outdoors. You can also type your own colour code.
Colors|fg	Pick the colour of the letters. White is the standard, green gives the classic coder look. Choose a colour that stands out clearly from your background so the text stays easy to read.
Background color|*	Set the colour behind the text. Pick black for the standard look or choose Custom to type any colour as a six-character code such as 1E1E1E.
Background color|default	Return to the standard pure black background. A safe choice with good contrast for almost any text colour.
Background color|custom	Type your own colour as a six-character hex code, for example 202020 for dark grey. If the code is not valid the old colour stays. Make sure the text colour is still easy to read on it.
Text color|*	Set the colour of the letters. White is normal, green is the coder look, or choose Custom to type any six-character colour code.
Text color|normal	Use plain white text, the standard. Very readable on dark backgrounds.
Text color|coder	Use green text, the classic coder look. Pleasant at night and recognisable, but make sure the background stays dark.
Text color|custom	Type your own text colour as a six-character hex code, such as FFD700 for gold. If it is invalid the old colour stays. Pick something that contrasts well with your background.
Files & archives|*	Settings for compressed files: which kind the program creates and what it does with hidden files when it packs a folder.
Files & archives|compress	Decide which kind of compressed file is created when you pack items with z-. A zip opens everywhere, including on Windows and phones; tar.gz is common on Linux; tar.xz, 7z and tar.zst squeeze harder or faster; .skill is a zip for AI assistants. You can also be asked every time.
Files & archives|ziphidden	Decide whether hidden files that sit inside a folder you pack are included in the compressed file. Items you pick yourself are always included; the setting only covers hidden files found inside folders.
Compress format  (z-)|*	Choose the kind of compressed file made when you pack items with z-. The mark shows what is used now.
Compress format  (z-)|zip	Always make a .zip file. Zip opens on practically every device, including Windows, Mac and phones, so it is the safest choice for sharing.
Compress format  (z-)|targz	Always make a .tar.gz file. It is the usual format on Linux, keeps file permissions and is often a little smaller, but it is less familiar to people on Windows.
Compress format  (z-)|tar	Always make a .tar file. A tar only bundles the files into one, it does not make them smaller, so use it when the files are already compressed or you want the fastest packing.
Compress format  (z-)|tarxz	Always make a .tar.xz file. It squeezes harder than most other kinds but takes noticeably longer to pack, so it suits files you keep for a long time or send over a slow link.
Compress format  (z-)|tarbz2	Always make a .tar.bz2 file. An older kind that compresses well, a little slower than tar.gz and a little smaller. Pick it when someone asks for bz2.
Compress format  (z-)|7z	Always make a .7z file. It compresses very well and can be locked with a password, but it needs the 7-Zip tool installed and is less known outside of Windows.
Compress format  (z-)|tarzst	Always make a .tar.zst file. A modern kind that packs and unpacks very fast and still compresses about as well as tar.gz. It needs the zstd tool installed.
Compress format  (z-)|tarlz4	Always make a .tar.lz4 file. The fastest kind to pack and unpack, but it makes files only a little smaller. It needs the lz4 tool installed.
Compress format  (z-)|skill	Always make a .skill file. It is an ordinary zip file with the ending .skill, the form in which AI assistants hand out their skills.
Compress format  (z-)|ask	Ask which kind to make each time you pack something. This is the standard and gives you control, at the price of one more question.
Zip hidden files  (z-)|*	Decide whether hidden files found inside folders are included when you pack items into an archive with z-. Items you pick by hand are always included; this setting only decides about the hidden files and folders found inside the folders you picked.
Zip hidden files  (z-)|follow	Do what your general Hidden files setting says: if hidden files are shown there they are included, if hidden there they are left out. One place controls everything. This is the standard.
Zip hidden files  (z-)|always	Always include hidden files and folders found inside the folders you choose. Use it when you need a complete copy including technical settings files, but note that private files may be packed too.
Zip hidden files  (z-)|never	Never include hidden files and folders found inside the folders you choose. Keeps the result small and avoids leaking private settings or credentials by accident.
Zip hidden files  (z-)|ask	Ask every time, but only when a chosen folder really contains hidden files. Gives full control without needless questions.
Upload hidden files  (up-)|*	Decide whether hidden files found inside folders are included when you create a share link with up-. Items you pick by hand are always included; this setting only decides about the hidden files and folders found inside the folders you picked.
Upload hidden files  (up-)|follow	Do what your general Hidden files setting says: if hidden files are shown there they are included, if hidden there they are left out. One place controls everything. This is the standard.
Upload hidden files  (up-)|always	Always include hidden files and folders found inside the folders you choose. Use it when you need a complete copy including technical settings files, but note that private files may be uploaded too.
Upload hidden files  (up-)|never	Never include hidden files and folders found inside the folders you choose. Keeps the result small and avoids leaking private settings or credentials by accident.
Upload hidden files  (up-)|ask	Ask every time, but only when a chosen folder really contains hidden files. Gives full control without needless questions.
Upload hidden files  (ux-)|*	Decide whether hidden files found inside folders are included when you send items with ux- to Cloud Surf. Items you pick by hand are always included; this setting only decides about the hidden files and folders found inside the folders you picked.
Upload hidden files  (ux-)|follow	Do what your general Hidden files setting says: if hidden files are shown there they are included, if hidden there they are left out. One place controls everything. This is the standard.
Upload hidden files  (ux-)|always	Always include hidden files and folders found inside the folders you choose. Use it when you need a complete copy including technical settings files, but note that private files may be uploaded too.
Upload hidden files  (ux-)|never	Never include hidden files and folders found inside the folders you choose. Keeps the result small and avoids leaking private settings or credentials by accident.
Upload hidden files  (ux-)|ask	Ask every time, but only when a chosen folder really contains hidden files. Gives full control without needless questions.
Buffers — same name twice  (c- m- k- b- s-)|*	A buffer keeps named sets of items for later. When you try to save a set under a name that already exists in the same buffer, the program needs to know what to do. Choose a buffer to set the rule for it.
Buffers — same name twice  (c- m- k- b- s-)|cp	Sets the rule for the copy buffer (c-): what happens when you save a set under a name already used in this buffer. Open it to pick: add to the old set, replace it, refuse, or ask each time. It prevents a copy list from being overwritten by mistake.
Copy buffer (c-)|*	What should happen when a copy set with the same name already exists in the c- buffer? Pick one of the four answers. The change applies the next time you save such a set.
Copy buffer (c-)|v:add	The new items join the existing set, which then holds both the old and the new items. Choose this if you build a list bit by bit under one name.
Copy buffer (c-)|v:replace	The new items take the place of the old ones; the old items are forgotten. Choose this when the newest list is always the one that counts. The old content cannot be recovered.
Copy buffer (c-)|v:deny	Nothing changes: the existing set is kept exactly as it is and the new items are not saved. The safest choice if you never want an existing set to be touched.
Copy buffer (c-)|v:ask	You are asked every time, and you may even choose another name. Safest for beginners and the standard, at the cost of one extra question.
Buffers — same name twice  (c- m- k- b- s-)|mv	Sets the rule for the move buffer (m-): what happens when you save a set under a name already used in this buffer. Open it to pick: add to the old set, replace it, refuse, or ask each time. It prevents a move list from being overwritten by mistake.
Move buffer (m-)|*	What should happen when a move set with the same name already exists in the m- buffer? Pick one of the four answers. The change applies the next time you save such a set.
Move buffer (m-)|v:add	The new items join the existing set, which then holds both the old and the new items. Choose this if you build a list bit by bit under one name.
Move buffer (m-)|v:replace	The new items take the place of the old ones; the old items are forgotten. Choose this when the newest list is always the one that counts. The old content cannot be recovered.
Move buffer (m-)|v:deny	Nothing changes: the existing set is kept exactly as it is and the new items are not saved. The safest choice if you never want an existing set to be touched.
Move buffer (m-)|v:ask	You are asked every time, and you may even choose another name. Safest for beginners and the standard, at the cost of one extra question.
Buffers — same name twice  (c- m- k- b- s-)|sc	Sets the rule for the shortcut buffer (k-): what happens when you save a set under a name already used in this buffer. Open it to pick: add to the old set, replace it, refuse, or ask each time. It prevents a shortcut list from being overwritten by mistake.
Shortcut buffer (k-)|*	What should happen when a shortcut set with the same name already exists in the k- buffer? Pick one of the four answers. The change applies the next time you save such a set.
Shortcut buffer (k-)|v:add	The new items join the existing set, which then holds both the old and the new items. Choose this if you build a list bit by bit under one name.
Shortcut buffer (k-)|v:replace	The new items take the place of the old ones; the old items are forgotten. Choose this when the newest list is always the one that counts. The old content cannot be recovered.
Shortcut buffer (k-)|v:deny	Nothing changes: the existing set is kept exactly as it is and the new items are not saved. The safest choice if you never want an existing set to be touched.
Shortcut buffer (k-)|v:ask	You are asked every time, and you may even choose another name. Safest for beginners and the standard, at the cost of one extra question.
Buffers — same name twice  (c- m- k- b- s-)|bm	Sets the rule for the bookmark buffer (b-): what happens when you save a set under a name already used in this buffer. Open it to pick: add to the old set, replace it, refuse, or ask each time. It prevents a bookmark list from being overwritten by mistake.
Bookmark buffer (b-)|*	What should happen when a bookmark set with the same name already exists in the b- buffer? Pick one of the four answers. The change applies the next time you save such a set.
Bookmark buffer (b-)|v:add	The new items join the existing set, which then holds both the old and the new items. Choose this if you build a list bit by bit under one name.
Bookmark buffer (b-)|v:replace	The new items take the place of the old ones; the old items are forgotten. Choose this when the newest list is always the one that counts. The old content cannot be recovered.
Bookmark buffer (b-)|v:deny	Nothing changes: the existing set is kept exactly as it is and the new items are not saved. The safest choice if you never want an existing set to be touched.
Bookmark buffer (b-)|v:ask	You are asked every time, and you may even choose another name. Safest for beginners and the standard, at the cost of one extra question.
Buffers — same name twice  (c- m- k- b- s-)|sl	Sets the rule for the selection buffer (s-): what happens when you save a set under a name already used in this buffer. Open it to pick: add to the old set, replace it, refuse, or ask each time. It prevents a selection list from being overwritten by mistake.
Select buffer (s-)|*	What should happen when a selection set with the same name already exists in the s- buffer? Pick one of the four answers. The change applies the next time you save such a set.
Select buffer (s-)|v:add	The new items join the existing set, which then holds both the old and the new items. Choose this if you build a list bit by bit under one name.
Select buffer (s-)|v:replace	The new items take the place of the old ones; the old items are forgotten. Choose this when the newest list is always the one that counts. The old content cannot be recovered.
Select buffer (s-)|v:deny	Nothing changes: the existing set is kept exactly as it is and the new items are not saved. The safest choice if you never want an existing set to be touched.
Select buffer (s-)|v:ask	You are asked every time, and you may even choose another name. Safest for beginners and the standard, at the cost of one extra question.
Find & replace|*	Every question that Find and replace may ask can be fixed here. Open a row and pick either a fixed answer, so it never asks again, or Ask every time. Rows are grouped into how you search, what is searched and how replacing is done.
Find & replace|case	Fixes whether capital and small letters count as different. With exact case, Apple and apple are different words; with any case they match. Open it to set a permanent answer or choose Ask every time.
Find & replace|regex	Fixes whether what you type is plain text or a pattern language called a regular expression, for experts who need wildcards and rules. Open it to set a permanent answer or choose Ask every time.
Find & replace|depth	Fixes whether only the current folder is searched or all folders below it too. Open it to set a permanent answer or choose Ask every time.
Find & replace|word	Fixes whether the text must appear as a complete word, so that cat does not match category. Open it to set a permanent answer or choose Ask every time.
Find & replace|input	Fixes whether you search for one text, or for many texts at once from a CSV table. Open it to set a permanent answer or choose Ask every time.
Find & replace|hidden	Fixes whether files whose names start with a dot are searched. Open it to set a permanent answer or choose Ask every time.
Find & replace|target	Fixes whether the search looks at files, at folders or both. Open it to set a permanent answer or choose Ask every time.
Find & replace|binary	Fixes whether files that are not readable text, such as images, programs and archives, are looked into. Open it to set a permanent answer or choose Ask every time.
Find & replace|maxsize	Fixes the size above which files are skipped to keep the search quick. Open it to set a permanent answer or choose Ask every time.
Find & replace|vcs	Fixes whether the hidden folders where version-control programs keep their history are searched. Open it to set a permanent answer or choose Ask every time.
Find & replace|confirm	Fixes whether you see a preview of every change and must confirm before text is replaced. Open it to set a permanent answer or choose Ask every time.
Find & replace|limit	Fixes how many matches are printed on the screen. Open it to set a permanent answer or choose Ask every time.
Find & replace|threads	Fixes how many parts of the processor work on the search at the same time. Open it to set a permanent answer or choose Ask every time.
Find & replace›Match case|*	Choose whether capital and small letters count as different. With exact case, Apple and apple are different words; with any case they match. Pick one answer; it is saved at once and used by every future search.
Find & replace›Regex|*	Choose whether what you type is plain text or a pattern language called a regular expression, for experts who need wildcards and rules. Pick one answer; it is saved at once and used by every future search.
Find & replace›Flat / recursive|*	Choose whether only the current folder is searched or all folders below it too. Pick one answer; it is saved at once and used by every future search.
Find & replace›Whole words|*	Choose whether the text must appear as a complete word, so that cat does not match category. Pick one answer; it is saved at once and used by every future search.
Find & replace›Single / CSV|*	Choose whether you search for one text, or for many texts at once from a CSV table. Pick one answer; it is saved at once and used by every future search.
Find & replace›Hidden files|*	Choose whether files whose names start with a dot are searched. Pick one answer; it is saved at once and used by every future search.
Find & replace›Files / folders|*	Choose whether the search looks at files, at folders or both. Pick one answer; it is saved at once and used by every future search.
Find & replace›Binary files|*	Choose whether files that are not readable text, such as images, programs and archives, are looked into. Pick one answer; it is saved at once and used by every future search.
Find & replace›Big files|*	Choose the size above which files are skipped to keep the search quick. Pick one answer; it is saved at once and used by every future search.
Find & replace›.git / .hg / .svn|*	Choose whether the hidden folders where version-control programs keep their history are searched. Pick one answer; it is saved at once and used by every future search.
Find & replace›Preview first|*	Choose whether you see a preview of every change and must confirm before text is replaced. Pick one answer; it is saved at once and used by every future search.
Find & replace›Results shown|*	Choose how many matches are printed on the screen. Pick one answer; it is saved at once and used by every future search.
Find & replace›CPU threads|*	Choose how many parts of the processor work on the search at the same time. Pick one answer; it is saved at once and used by every future search.
Find & replace›Match case|v:ask	You are asked every time you search. Flexible, but one more question each time. This is the standard.
Find & replace›Match case|v:exact	Capital and small letters count as different: Apple will not find apple. Use it for precise work such as code.
Find & replace›Match case|v:any	Capital and small letters are treated alike: Apple, APPLE and apple all match. Easiest for normal text.
Find & replace›Regex|v:off	What you type is searched as plain text, letter for letter. Safe and simple, and the standard.
Find & replace›Regex|v:on	What you type is read as a pattern with special characters like dot and star. Powerful, but characters such as a dot may match more than you expect.
Find & replace›Regex|v:ask	You are asked every time whether to use a pattern.
Find & replace›Flat / recursive|v:ask	You are asked every time whether to search sub-folders. Standard.
Find & replace›Flat / recursive|v:flat	Only the folder you are in is searched. Fast and focused.
Find & replace›Flat / recursive|v:recursive	The folder and all folders below it are searched. Thorough, but can take longer on big trees and may change many files when replacing.
Find & replace›Whole words|v:off	Text can match anywhere, even inside longer words: cat matches category. Standard.
Find & replace›Whole words|v:on	The text must be a complete word. cat will match cat but not category. Good for avoiding unwanted replacements.
Find & replace›Whole words|v:ask	You are asked every time.
Find & replace›Single / CSV|v:ask	You are asked every time whether you search one text or a table of many. Standard.
Find & replace›Single / CSV|v:single	You always work with one search text and one replacement. Simple and direct.
Find & replace›Single / CSV|v:csv	You always supply a CSV table with many search and replacement pairs that are processed in one go. Efficient for large clean-ups.
Find & replace›Hidden files|v:follow	Follow your general Hidden files setting from Display. Standard.
Find & replace›Hidden files|v:include	Always search hidden files too, even if they are hidden in your lists. Use it when you hunt for settings files.
Find & replace›Hidden files|v:exclude	Never touch hidden files. Safest when replacing, because technical settings stay untouched.
Find & replace›Files / folders|v:both	Look at both file names and folder names. Standard.
Find & replace›Files / folders|v:files	Look only at files and leave folders out.
Find & replace›Files / folders|v:folders	Look only at folders and leave files out.
Find & replace›Binary files|v:skip	Files that are not readable text, such as images and programs, are skipped. Safe: replacing text inside such files could damage them. Standard.
Find & replace›Binary files|v:include	Binary files are searched too. Use it with great care: replacing inside them can break them for good.
Find & replace›Big files|v:50	Files bigger than 50 MB are skipped. Fastest, but large files may be missed.
Find & replace›Big files|v:200	Files bigger than 200 MB are skipped. A good balance and the standard.
Find & replace›Big files|v:1000	Files bigger than 1 GB are skipped. Thorough, but slow and heavy on a phone.
Find & replace›Big files|v:0	No size limit at all; every file is searched. May take very long or use a lot of memory.
Find & replace›.git / .hg / .svn|v:skip	The hidden history folders of version-control programs are skipped. Safe, because changing their inner files can corrupt a project's history. Standard.
Find & replace›.git / .hg / .svn|v:include	These folders are searched too. Only for experts; replacing there can corrupt a project.
Find & replace›Preview first|v:preview	You see a list of what would change and must confirm before anything is replaced. Safest and the standard.
Find & replace›Preview first|v:direct	Text is replaced immediately without a preview. Quick, but mistakes are hard to undo.
Find & replace›Results shown|v:100	Only the first 100 matches are printed. Short and quick to read; the search itself still covers everything.
Find & replace›Results shown|v:300	The first 300 matches are printed. A good balance and the standard.
Find & replace›Results shown|v:1000	The first 1000 matches are printed. Good for big jobs, but a long scroll.
Find & replace›Results shown|v:0	Every match is printed, however many there are. The screen may flood with lines.
Find & replace›CPU threads|v:auto	The program picks the number of workers to suit your device. Recommended and the standard.
Find & replace›CPU threads|v:1	One worker only. Slowest but gentle on battery and heat.
Find & replace›CPU threads|v:2	Two workers. A moderate speed-up for older phones.
Find & replace›CPU threads|v:4	Four workers. Fast on most modern phones.
Find & replace›CPU threads|v:8	Eight workers. Fastest on powerful devices but can make the phone warm and use more battery.
File API|*	The online features of the program: share links, Cloud Surf shares, backups, saved items and background snapshots. Some of them cost credits, and everything stored online disappears by itself after a time you choose. Open a row to adjust it.
File API|credits	Decide whether the program shows you the price in credits before it does something that costs money, such as uploading, backing up or saving. A price of one credit never asks. Open it if you want to be warned, or if the warnings annoy you.
File API|links	Settings for temporary share links made with up- and c2c-: how long a new link stays alive before it is deleted automatically, and whether hidden files inside shared folders are included.
File API|shares	Settings for Cloud Surf shares made with ux-: how long a new share stays online before it deletes itself, and whether hidden files inside shared folders are included.
File API|backup	Settings for the safety copy the program can make in the cloud before you delete something: whether it makes one, and how long the copy is kept before it disappears.
File API|saved	Decide how long an item stays online after you saved it with save-. After this time it is deleted automatically, so choose a longer time for things you want to keep for long.
File API|snapshots	Snapshots are automatic copies of chosen files or folders made in the background while the program is open. Open it to switch them on or off, to choose how often they are taken and how long they are kept.
Credits|*	Choose whether you are warned about the price in credits before a cloud action. Credits are the small payment units of the online features. The server still refuses an action if you do not have enough credits.
Credits|v:show	Ask first. When an action costs more than one credit, you see the price and can continue, change the plan to cost less, increase it, or stop. Actions that cost exactly one credit just go ahead. Recommended, because you never pay by surprise.
Credits|v:skip	Never ask. The action goes straight ahead without showing the price. Faster, but you could spend more credits than you expected. The server still stops you if your balance is too low.
Links (up- / c2c-)|*	Settings for temporary links created with up- and c2c-. Open a row to change how long a link lives and whether hidden files are included.
Links (up- / c2c-)|nuke	Choose how long a new link stays online. When the time is over, the link and the files behind it are deleted by themselves, which is called nuking. Short is safer for private files; longer is better when the receiver needs time.
Links (up- / c2c-)|uphidden	Decide whether hidden files found inside folders you share with up- are uploaded too. Your own picks are always sent.
Cloud Surf shares (ux-)|*	Settings for Cloud Surf shares made with ux-. Open a row to change how long a share lives and whether hidden files are included.
Cloud Surf shares (ux-)|uxnuke	Choose how long a new Cloud Surf share stays online before it deletes itself. The standard is thirty days, which is also the maximum.
Cloud Surf shares (ux-)|uxhidden	Decide whether hidden files found inside folders you send with ux- are included. Your own picks are always sent.
Nuke time|*	Choose how long a new link stays online before it is deleted automatically. This is often called the nuke time. Pick a ready choice, or Custom to type your own time such as 90m or 3 days. Links under one hour are billed as one hour.
Nuke time|custom	Type your own time with a unit: s for seconds, m for minutes, h for hours, d for days or w for weeks, for example 90m, 2d12h or 1 week. The time must be between one minute and thirty days. If it cannot be read, the old value stays.
Nuke time|p:3600	Keep a new link for one hour. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Nuke time|p:21600	Keep a new link for six hours. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Nuke time|p:86400	Keep a new link for one day. A comfortable middle length for most uses.
Nuke time|p:604800	Keep a new link for seven days. A comfortable middle length for most uses.
Nuke time|p:1209600	Keep a new link for fourteen days. A long time gives the receiver plenty of time, but the item stays online longer than necessary.
Nuke time|p:2592000	Keep a new link for thirty days. A long time gives the receiver plenty of time, but the item stays online longer than necessary.
Nuke time|p:60	Keep a new link for one minute. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Nuke time|p:300	Keep a new link for five minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Nuke time|p:900	Keep a new link for fifteen minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Nuke time|p:1800	Keep a new link for thirty minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Nuke time (ux-)|*	Choose how long a new Cloud Surf share stays online before it is deleted automatically. This is often called the nuke time. Pick a ready choice, or Custom to type your own time such as 90m or 3 days. The maximum is thirty days.
Nuke time (ux-)|custom	Type your own time with a unit: s for seconds, m for minutes, h for hours, d for days or w for weeks, for example 90m, 2d12h or 1 week. The time must be between one minute and thirty days. If it cannot be read, the old value stays.
Nuke time (ux-)|p:3600	Keep a new Cloud Surf share for one hour. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Nuke time (ux-)|p:21600	Keep a new Cloud Surf share for six hours. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Nuke time (ux-)|p:86400	Keep a new Cloud Surf share for one day. A comfortable middle length for most uses.
Nuke time (ux-)|p:604800	Keep a new Cloud Surf share for seven days. A comfortable middle length for most uses.
Nuke time (ux-)|p:1209600	Keep a new Cloud Surf share for fourteen days. A long time gives the receiver plenty of time, but the item stays online longer than necessary.
Nuke time (ux-)|p:2592000	Keep a new Cloud Surf share for thirty days. A long time gives the receiver plenty of time, but the item stays online longer than necessary.
Nuke time (ux-)|p:60	Keep a new Cloud Surf share for one minute. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Nuke time (ux-)|p:300	Keep a new Cloud Surf share for five minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Nuke time (ux-)|p:900	Keep a new Cloud Surf share for fifteen minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Nuke time (ux-)|p:1800	Keep a new Cloud Surf share for thirty minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Backup keep time|*	Choose how long a backup stays online before it is deleted automatically. This is often called the nuke time. Pick a ready choice, or Custom to type your own time such as 90m or 3 days. The maximum is thirty days; you can extend or shorten a backup later in Backup.
Backup keep time|custom	Type your own time with a unit: s for seconds, m for minutes, h for hours, d for days or w for weeks, for example 90m, 2d12h or 1 week. The time must be between one minute and thirty days. If it cannot be read, the old value stays.
Backup keep time|p:3600	Keep a backup for one hour. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Backup keep time|p:21600	Keep a backup for six hours. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Backup keep time|p:86400	Keep a backup for one day. A comfortable middle length for most uses.
Backup keep time|p:604800	Keep a backup for seven days. A comfortable middle length for most uses.
Backup keep time|p:1209600	Keep a backup for fourteen days. A long time gives the receiver plenty of time, but the item stays online longer than necessary.
Backup keep time|p:2592000	Keep a backup for thirty days. A long time gives the receiver plenty of time, but the item stays online longer than necessary.
Backup keep time|p:60	Keep a backup for one minute. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Backup keep time|p:300	Keep a backup for five minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Backup keep time|p:900	Keep a backup for fifteen minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Backup keep time|p:1800	Keep a backup for thirty minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Saved Surf keep time|*	Choose how long an item saved with save- stays online before it is deleted automatically. This is often called the nuke time. Pick a ready choice, or Custom to type your own time such as 90m or 3 days. The maximum is thirty days; you can extend or shorten it later in Saved Surf.
Saved Surf keep time|custom	Type your own time with a unit such as 90m or 3 days, between one minute and thirty days. If it cannot be read, the old value stays.
Saved Surf keep time|p:3600	Keep an item saved with save- for one hour. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Saved Surf keep time|p:21600	Keep an item saved with save- for six hours. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Saved Surf keep time|p:86400	Keep an item saved with save- for one day. A comfortable middle length for most uses.
Saved Surf keep time|p:604800	Keep an item saved with save- for seven days. A comfortable middle length for most uses.
Saved Surf keep time|p:1209600	Keep an item saved with save- for fourteen days. A long time gives the receiver plenty of time, but the item stays online longer than necessary.
Saved Surf keep time|p:2592000	Keep an item saved with save- for thirty days. A long time gives the receiver plenty of time, but the item stays online longer than necessary.
Saved Surf keep time|p:60	Keep an item saved with save- for one minute. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Saved Surf keep time|p:300	Keep an item saved with save- for five minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Saved Surf keep time|p:900	Keep an item saved with save- for fifteen minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Saved Surf keep time|p:1800	Keep an item saved with save- for thirty minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Snapshot keep time|*	Choose how long each snapshot stays online before it is deleted automatically. This is often called the nuke time. Pick a ready choice, or Custom to type your own time such as 90m or 3 days. The time is paid up front for every snapshot, so a longer time costs more credits.
Snapshot keep time|custom	Type your own time with a unit: s for seconds, m for minutes, h for hours, d for days or w for weeks, for example 90m, 2d12h or 1 week. The time must be between one minute and thirty days. If it cannot be read, the old value stays.
Snapshot keep time|p:3600	Keep each snapshot for one hour. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Snapshot keep time|p:21600	Keep each snapshot for six hours. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Snapshot keep time|p:86400	Keep each snapshot for one day. A comfortable middle length for most uses.
Snapshot keep time|p:604800	Keep each snapshot for seven days. A comfortable middle length for most uses.
Snapshot keep time|p:1209600	Keep each snapshot for fourteen days. A long time gives the receiver plenty of time, but the item stays online longer than necessary.
Snapshot keep time|p:2592000	Keep each snapshot for thirty days. A long time gives the receiver plenty of time, but the item stays online longer than necessary.
Snapshot keep time|p:60	Keep each snapshot for one minute. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Snapshot keep time|p:300	Keep each snapshot for five minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Snapshot keep time|p:900	Keep each snapshot for fifteen minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Snapshot keep time|p:1800	Keep each snapshot for thirty minutes. A short time is safer for private material, because it vanishes soon, and it usually costs less.
Snapshot interval|*	Choose how often a changed file or folder is snapshotted while the program is open. Every snapshot costs credits, so a short interval on a folder that changes often adds up quickly. The minimum is one minute. Pick a ready choice or Custom.
Snapshot interval|custom	Type your own time with a unit, such as 45m, 2h or 1d. It must be between one minute and thirty days. If it cannot be read, the old value stays.
Snapshot interval|p:60	Take a snapshot at most every one minute. Very frequent, nearly continuous protection. Costs the most credits. Only for work you cannot afford to lose even a minute of.
Snapshot interval|p:300	Take a snapshot at most every five minutes. Frequent protection. Good while you are actively writing or editing something important.
Snapshot interval|p:900	Take a snapshot at most every fifteen minutes. A reasonable compromise between protection and cost for active work.
Snapshot interval|p:1800	Take a snapshot at most every thirty minutes. Occasional protection that keeps costs low while you work.
Snapshot interval|p:3600	Take a snapshot at most every one hour. The standard: one copy per hour of changes while the program is open. A good balance for most people.
Snapshot interval|p:86400	Take a snapshot at most every one day. At most one copy a day. Cheap, but you can lose up to a day of changes.
Snapshot interval|p:604800	Take a snapshot at most every one week. One copy a week. Very cheap, only suitable for files that rarely change.
Backup|*	Settings for the safety copy made in the cloud before something is deleted. Choose whether a backup is made, and how long it is kept.
Backup|mode	Decide whether the program first copies items to the cloud before you delete them, so you can restore them later. Choose yes for safety, no for speed, or let it ask every time.
Backup|keep	Choose how long a new backup stays in the cloud before it deletes itself. The maximum is thirty days.
Backup before delete|*	Choose whether a safety copy goes to the cloud before something is deleted with d, delete or one of the delete functions. A backup costs a few credits and some time but lets you undo a deletion by mistake.
Backup before delete|v:yes	Always make a backup first and let you name it. The safest choice and the standard: a deleted file can be restored from Backup within the keep time.
Backup before delete|v:no	Delete straight away without any copy. Faster and free, but there is no way back, so only use it for things you can easily recreate.
Backup before delete|v:ask	Ask each time whether to make a backup. Flexible, but one more question at every deletion.
Snapshots›Snapshots|*	Switch the automatic background snapshots on or off. Snapshots are only taken while the program is open.
File API›Snapshots|*	Snapshots are automatic copies of files or folders on your list. Choose whether they run, how often and how long they are kept.
File API›Snapshots|on	Switch automatic snapshots on or off. When on, the files and folders you added to the list are copied to the cloud every interval, if they changed, while the program runs.
File API›Snapshots|interval	Choose how often a changed file or folder is copied. A shorter time protects better but costs more credits.
File API›Snapshots|keep	Choose how long each snapshot is kept before it is deleted automatically. A longer time gives more history but costs more credits.
Snapshots›Snapshots|v:on	Snapshots run in the background every interval while the program is open. Recommended if you want automatic protection. This is the standard.
Snapshots›Snapshots|v:off	Snapshots are paused. Your list is kept and nothing is lost; they continue when you switch on again. Choose this to stop spending credits.
Menu specific|*	Each row here belongs to one screen only. Settings made here change that screen and nothing else.
Menu specific|links	Settings for your list of online links. Open it to choose the order of this list. The change affects only this screen.
Links (api)|*	Settings for your list of online links. Open Display to choose the order. Nothing else changes.
Links (api)›Display|*	Display options for your list of online links only. Open Sort order to choose how this list is ordered. Other screens are not affected.
Links (api)›Display|sort	Choose how the items of your list of online links are ordered. The choice is remembered for this screen only, so your normal folders keep their own order.
Menu specific|backup	Settings for your list of backups. Open it to choose the order of this list. The change affects only this screen.
Backup (bk)|*	Settings for your list of backups. Open Display to choose the order. Nothing else changes.
Backup (bk)›Display|*	Display options for your list of backups only. Open Sort order to choose how this list is ordered. Other screens are not affected.
Backup (bk)›Display|sort	Choose how the items of your list of backups are ordered. The choice is remembered for this screen only, so your normal folders keep their own order.
Menu specific|saved	Settings for your list of saved items. Open it to choose the order of this list. The change affects only this screen.
Saved Surf (sv)|*	Settings for your list of saved items. Open Display to choose the order. Nothing else changes.
Saved Surf (sv)›Display|*	Display options for your list of saved items only. Open Sort order to choose how this list is ordered. Other screens are not affected.
Saved Surf (sv)›Display|sort	Choose how the items of your list of saved items are ordered. The choice is remembered for this screen only, so your normal folders keep their own order.
Menu specific|shares_given	Settings for the Cloud Surf shares you gave to others. Open it to choose the order of this list. The change affects only this screen.
Cloud Surf › Given|*	Settings for the Cloud Surf shares you gave to others. Open Display to choose the order. Nothing else changes.
Cloud Surf › Given›Display|*	Display options for the Cloud Surf shares you gave to others only. Open Sort order to choose how this list is ordered. Other screens are not affected.
Cloud Surf › Given›Display|sort	Choose how the items of the Cloud Surf shares you gave to others are ordered. The choice is remembered for this screen only, so your normal folders keep their own order.
Menu specific|shares_recv	Settings for the Cloud Surf shares you received. Open it to choose the order of this list. The change affects only this screen.
Cloud Surf › Received|*	Settings for the Cloud Surf shares you received. Open Display to choose the order. Nothing else changes.
Cloud Surf › Received›Display|*	Display options for the Cloud Surf shares you received only. Open Sort order to choose how this list is ordered. Other screens are not affected.
Cloud Surf › Received›Display|sort	Choose how the items of the Cloud Surf shares you received are ordered. The choice is remembered for this screen only, so your normal folders keep their own order.
Menu specific|snap_devices	Settings for the list of devices that have snapshots. Open it to choose the order of this list. The change affects only this screen.
Snapshots › Devices|*	Settings for the list of devices that have snapshots. Open Display to choose the order. Nothing else changes.
Snapshots › Devices›Display|*	Display options for the list of devices that have snapshots only. Open Sort order to choose how this list is ordered. Other screens are not affected.
Snapshots › Devices›Display|sort	Choose how the items of the list of devices that have snapshots are ordered. The choice is remembered for this screen only, so your normal folders keep their own order.
Menu specific|snap_targets	Settings for the folders protected on one device. Open it to choose the order of this list. The change affects only this screen.
Snapshots › Paths of a device|*	Settings for the folders protected on one device. Open Display to choose the order. Nothing else changes.
Snapshots › Paths of a device›Display|*	Display options for the folders protected on one device only. Open Sort order to choose how this list is ordered. Other screens are not affected.
Snapshots › Paths of a device›Display|sort	Choose how the items of the folders protected on one device are ordered. The choice is remembered for this screen only, so your normal folders keep their own order.
Menu specific|snapshots	Settings for the snapshots taken of one folder. Open it to choose the order of this list. The change affects only this screen.
Snapshots › Snapshots of a path|*	Settings for the snapshots taken of one folder. Open Display to choose the order. Nothing else changes.
Snapshots › Snapshots of a path›Display|*	Display options for the snapshots taken of one folder only. Open Sort order to choose how this list is ordered. Other screens are not affected.
Snapshots › Snapshots of a path›Display|sort	Choose how the items of the snapshots taken of one folder are ordered. The choice is remembered for this screen only, so your normal folders keep their own order.
Menu specific|pending	Settings for your list of unfinished uploads. Open it to choose the order of this list. The change affects only this screen.
Pending uploads (pn)|*	Settings for your list of unfinished uploads. Open Display to choose the order. Nothing else changes.
Pending uploads (pn)›Display|*	Display options for your list of unfinished uploads only. Open Sort order to choose how this list is ordered. Other screens are not affected.
Pending uploads (pn)›Display|sort	Choose how the items of your list of unfinished uploads are ordered. The choice is remembered for this screen only, so your normal folders keep their own order.
Links (api)|display	Open the display options for your list of online links, where you choose how it is sorted.
Backup (bk)|display	Open the display options for your list of backups, where you choose how it is sorted.
Saved Surf (sv)|display	Open the display options for your list of saved items, where you choose how it is sorted.
Cloud Surf › Given|display	Open the display options for the Cloud Surf shares you gave to others, where you choose how it is sorted.
Cloud Surf › Received|display	Open the display options for the Cloud Surf shares you received, where you choose how it is sorted.
Snapshots › Devices|display	Open the display options for the list of devices that have snapshots, where you choose how it is sorted.
Snapshots › Paths of a device|display	Open the display options for the folders protected on one device, where you choose how it is sorted.
Snapshots › Snapshots of a path|display	Open the display options for the snapshots taken of one folder, where you choose how it is sorted.
Pending uploads (pn)|display	Open the display options for your list of unfinished uploads, where you choose how it is sorted.
System|*	Settings that belong to your device. Open a row to adjust it.
System|timezone	Choose which timezone the program uses to show times. By default it follows your device's clock. Pick a region if times look wrong, for example when you travel or your device is set to another zone.
System|nano	Adds a handful of friendly settings to the nano text editor, such as mouse support, line numbers and a position indicator, to a file called .nanorc in your home folder. It is done only once and never twice. Choosing it again does nothing harmful.
Timezone|*	Pick the timezone the program uses for dates and times. Type an equals sign and then part of a city, region, abbreviation or offset to search quickly, for example =kolkata, =new york or =+05:30. The first choice follows your device automatically.
Timezone › Manual|*	No timezone database was found, so a short list of fixed offsets from universal time is shown. These do not change automatically for daylight saving. Type an equals sign and a region to search.
Home|*	This is the front door of the program. Each row opens one part of it: your own files, your online space, your saved links and backups, and the tools around them. Type the number of a row, or move to it with the arrow keys and press Enter. Press u to come back here from any of them. Nothing on this screen changes anything by itself.
Home|local	Your own files on this device. This is the normal file list you see when the program starts: open folders, select files, copy, move, delete or compress them. Choose it when you simply want to work with files on this computer.
Home|cloud	Browse the online space that belongs to your account, much like a folder list. You can look inside shared online folders and bring files down to this device. Choose it when the file you want is online rather than on this computer.
Home|shared	What other people have shared with you. It lists the files and folders that someone sent to you through a share link so you can open or download them. Choose it when a friend or a coworker says they sent you something.
Home|notify	Messages from the online service, for example that a share was used or that something needs your attention. Choose it to see what is new without having to look anywhere else.
Home|switch	Quick jumps between folders you use often. It keeps your bookmarks and recently used places, and a list of rules to hide folders you never want to see. Choose it to get back to a place in one step instead of typing a long path.
Home|functions	Ready-made helper actions and your own small scripts, grouped in folders. Choose it to run a task that someone already prepared, such as a batch rename or an upload, without remembering the exact command.
Home|rules	The rules that decide what the program may do with your files, for example which names to skip when copying. Choose it to look at or change those rules. A wrong rule can hide files from an action, so change one at a time.
Home|help	The built-in guide. It explains the commands and shows examples. Choose it whenever you are unsure what a key does. It only shows text and never changes anything.
Home|auth	Sign in, sign out or switch the account the online parts of the program use. Choose it first if online features say that you are not signed in, or when you want to use a different account.
Home|links	Your temporary share links. Each link lets someone download a file without an account, and it stops working after a set time. Choose it to copy a link again, change when it expires, give it a name, or switch it off early.
Home|rbam	Share a file with one particular person in a controlled way: you decide who may open it and for how long. Choose it when a public link feels too open.
Home|backup	Copies of your files stored safely online, so a mistake on this device does not lose them. Choose it to see your backups, bring one back to this device, or remove one you no longer need.
Home|saved	Files you chose to keep online on purpose. Unlike a share link they do not run out on their own. Choose it to find a saved file again or to bring it back to this device.
Home|snapshots	Automatic pictures of a folder taken in the background, so you can go back to how it looked earlier. Choose it to see the snapshots, restore one, or delete the ones you no longer need.
Home|pending	Online jobs that were started but not finished, for example an upload that stopped when the connection dropped. Choose it to continue them, or to see what is still waiting.
Pending FileAPI actions|*	Online jobs that did not finish yet, grouped by kind. A number next to a group tells you how many are waiting. Open a group to look at its jobs, or use the last two rows to restart everything that was interrupted on this computer or to ask the server again. Nothing here deletes a file.
Pending FileAPI actions|upload	Uploads that were started and not completed, for example because the connection dropped. Open it to continue one of them or to remove one you no longer want.
Pending FileAPI actions|ux	Shares to one particular person that were started and not completed. Open it to continue one or to look at what is still waiting.
Pending FileAPI actions|backup	Backups that were started and not finished. Open it to continue one so your copy becomes complete, or to remove one you no longer need.
Pending FileAPI actions|saved	Files you were saving online that did not finish. Open it to continue one, so the file is really kept, or to remove it.
Pending FileAPI actions|snapshot	Snapshots that were being taken in the background and were interrupted. Open it to continue one or to see what is still waiting.
Pending FileAPI actions|all	Restarts every job on this computer that was interrupted, one after the other, so you do not have to open each group. It only resumes work you already started; it never starts new work and never deletes anything.
Pending FileAPI actions|refresh	Asks the online server again which jobs are waiting and updates the numbers on this screen. Use it when the list looks out of date, for example after you finished something on another device.
BVK_DESC_EOF
}

# ── which text belongs to what is on the screen ──────────────────────────────────────────────
# Runs inside _st_draw and uses its caller's locals:  title  parent_title  cur.
# Most specific key first, the screen's own text last; a row without a line of its own shows the screen's text.
_ST_DESC_TXT=""; _ST_DESC_KEY=""; _ST_DESC_N=0; _ST_DESC_TRUNC=0
declare -ga _ST_DESC_ALL=() _ST_DESC_LN=()
_st_desc_for() {
  _ST_DESC_TXT=""
  _st_desc_load
  local pk="${parent_title#Settings › }" tg="" ctx="" k
  [ "$pk" = "$parent_title" ] && pk=""
  (( cur >= 0 )) && [ "${_st_kind[$cur]:-}" != h ] && tg="${_st_tag[$cur]}"
  if [ -n "$tg" ]; then
    [ "$title" = "Sort order" ] && [ -n "${_MS_SEL:-}" ] && ctx="${_MS_NAME[$_MS_SEL]:-}"      # the same tag means different things on different menus' sort screens
    for k in ${ctx:+"$ctx›$title|$tg"} ${pk:+"$pk›$title|$tg"} "$title|$tg"; do
      [ -n "${_ST_DESC[$k]+x}" ] && { _ST_DESC_TXT="${_ST_DESC[$k]}"; return 0; }
    done
  fi
  for k in ${pk:+"$pk›$title|*"} "$title|*"; do
    [ -n "${_ST_DESC[$k]+x}" ] && { _ST_DESC_TXT="${_ST_DESC[$k]}"; return 0; }
  done
  return 0
}

# word-wrap $1 to $2 columns into _ST_DESC_ALL (no forks, no globbing)
_st_desc_wrap() {
  local -a w; local x line=""
  _ST_DESC_ALL=()
  builtin read -ra w <<< "$1"
  for x in "${w[@]}"; do
    if [ -z "$line" ]; then line="$x"
    elif (( ${#line} + 1 + ${#x} <= $2 )); then line+=" $x"
    else _ST_DESC_ALL+=("$line"); line="$x"; fi
  done
  [ -n "$line" ] && _ST_DESC_ALL+=("$line")
  return 0
}

# How many lines the explanation of THIS screen takes: the tallest text among its rows and the screen's own, cut at a third of the screen.
# The block must keep ONE height while the highlight moves: the Settings block is erased and redrawn by row count, so a block that grows and
# shrinks with the highlighted row would move the prompt up and down and leave a blank row under it (and the touch / wheel maths would be off).
# Uses _st_draw's  rows cols title parent_title cur  and the screen's  _st_tag _st_kind ; cached per screen and size.
_ST_DESC_H_KEY=""; _ST_DESC_H=0
_st_desc_height() {
  local max=$1 key="$title|$parent_title|$cols|$max|${_st_tag[*]}" keep_cur=$cur h=0 n
  if [ "$key" = "$_ST_DESC_H_KEY" ]; then return 0; fi
  for (( cur = -1; cur < ${#_st_tag[@]}; cur++ )); do
    _st_desc_for
    [ -n "$_ST_DESC_TXT" ] || continue
    _st_desc_wrap "$_ST_DESC_TXT" $(( cols - 4 ))
    n=${#_ST_DESC_ALL[@]}; (( n > h )) && h=$n
  done
  cur=$keep_cur
  (( h > max )) && h=$max
  _ST_DESC_H=$h; _ST_DESC_H_KEY="$key"; _ST_DESC_KEY=""        # the wrap cache was used for the scan: rebuild it for the highlighted row
  return 0
}

# fills _ST_DESC_LN (the lines drawn above the suggestion row) and _ST_DESC_N (how many); uses _st_draw's  rows cols.
# At most a third of the screen: a long text is cut with … and  ?  + Enter shows all of it.  The block has the same height on every row of a screen
# (shorter texts are padded with empty lines), see _st_desc_height.
_st_desc_prepare() {
  _ST_DESC_N=0; _ST_DESC_TRUNC=0; _ST_DESC_LN=()
  (( rows >= 18 )) || return 0
  local max=$(( rows / 3 )) last
  (( max < 3 )) && max=3
  (( max > rows - 15 )) && max=$(( rows - 15 ))
  (( max >= 2 )) || return 0
  _st_desc_height "$max"
  (( _ST_DESC_H > 0 )) || return 0
  _st_desc_for
  if [ -n "$_ST_DESC_TXT" ]; then
    if [ "$cols|$_ST_DESC_TXT" != "$_ST_DESC_KEY" ]; then _ST_DESC_KEY="$cols|$_ST_DESC_TXT"; _st_desc_wrap "$_ST_DESC_TXT" $(( cols - 4 )); fi
    if (( ${#_ST_DESC_ALL[@]} > max )); then
      _ST_DESC_LN=("${_ST_DESC_ALL[@]:0:max}"); _ST_DESC_TRUNC=1
      last="${_ST_DESC_LN[max-1]}"; (( ${#last} > cols - 17 )) && last="${last:0:cols-17}"
      _ST_DESC_LN[max-1]="${last}… (? = all)"
    else
      _ST_DESC_LN=("${_ST_DESC_ALL[@]}")
    fi
  fi
  while (( ${#_ST_DESC_LN[@]} < _ST_DESC_H )); do _ST_DESC_LN+=(""); done
  _ST_DESC_N=${#_ST_DESC_LN[@]}
  return 0
}

# "?" + Enter: the whole text (the screen is wiped first; the caller draws it again afterwards)
_st_desc_show() {
  local x cols; cols=$(_term_cols 2>/dev/null); [ "${_vp_cols_now:-0}" -gt 0 ] 2>/dev/null && cols=$_vp_cols_now
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=60
  _st_desc_for
  if [ -z "$_ST_DESC_TXT" ]; then builtin printf '\n  There is no explanation for this one yet.\n'
  else
    _st_desc_wrap "$_ST_DESC_TXT" $(( cols - 4 ))
    builtin printf '\n\033[1m  %s\033[0m\n\n' "$title"
    for x in "${_ST_DESC_ALL[@]}"; do builtin printf '  %s\n' "$x"; done
  fi
  builtin printf '\n'
  builtin printf '  Press Enter to go back '
  builtin read -r x || true
}
