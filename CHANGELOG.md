# BiSGuild

## Unreleased

- **Guildmates on the world map are radar tracks now.** The little squares are gone. Each guildmate is drawn like a fighter jet's radar screen shows a friendly:
  - a half-circle in their class colour;
  - a line showing which way they're heading, longer the faster they go (none when standing still);
  - their callsign beside it, like "FRANK 26", on their own zone's map only, so the continent map stays clean.
  - **Hover to lock on:** green brackets close in, and a card shows their whole name, class, level, heading and speed, where they are, and how many seconds old that is. Click opens their card in the terminal, as before.
  - **Old spots fade:** someone you haven't heard from in a while goes grey and hollow, with the age on the tag.
  - **Groups merge:** several guildmates in one spot become one box with a count. Hover it for the names.
- **Next to OpenMap.** OpenMap now draws your guild too. BiS Guild's tracks stay on, and the first login with OpenMap says once which switch is whose. Our switch is now in OpenMap's own menu as well ("BiS Guild radar tracks").
- **A track says where it really is.** It used to show the guild roster's zone, which can lag behind (a dot in Tirisfal said "Durotar").
- For other addons: `BiSGuildAPI.MapDots()` (version 3) says whether our tracks are on the map.

## 1.0.0 - Forever 1.0

- **A new install starts quiet.** Only the main job is on: the raider terminal (`/bisg`) and the raid record. The "X just logged in - invite?" pop-up, guildmates' dots on the world map and the "a guildmate runs a newer version" line in chat start off, until you switch them on. **Already using BiS Guild? Nothing changes for you** - every switch stays as you had it.
- **Options, in one place.** BiS Guild has an options window now: **Esc > Options > AddOns > BiS> > BiS> Guild**, or `/bisg options`. Switches for the login pop-up, the map dots, the newer-version note, the shared BiS channel and sharing your spot, and a button to the terminal. The slash commands still work and do exactly the same.
- BiS> Guild in Esc > Options > AddOns is a full-page dashboard now: every section down the left, its settings big and readable on the right.
- **New: `/bisg note on | off`** for the newer-version line in chat. `/biscomm ver` lists every BiS version in your guild either way.
- **Fixed: right-clicking a name inside a dungeon or raid broke the game's own menus.** Inside an instance the right-click now says so in one line instead; out in the world it opens the player menu as before.

## 0.5.4

- **Which BiS versions your guild runs:** `/biscomm ver` lists every BiS addon around you, who has the newest, and which release is marked critical. Nothing is said unless an update is critical (or your copy is too old to talk to a guildmate's) - then one line, once, never in a fight.

## 0.5.3

- **Buttons and rows pop under the mouse** (a clearer tint and a bar on the left), and Escape closes the logins window.

## 0.5.2

- **No more text over the raider list.** Before your guild's first logged raid, the RAIDERS tab printed its "no raid nights yet" note straight through the guild's names. The note now goes on the line above the list.
- **No black squares left on the WHERE map.** After looking at a map with dots on it, switching to another map left small black squares where those dots had been. They now go with their dots.

## 0.5.1

- **The Deeprun Tram's timetable, for the whole guild.** With the shared BiS lib's new version, riding the Deeprun Tram with any BiS addon times it for your guild, the way the zeppelins and boats already are - BiS Tools' ride card and BiS Shell's TRAM-TRAK read it.
- **No double marks for your group on the map.** The game already draws your party and raid members on the world map, so a guildmate in your group no longer gets a BiS Guild dot on top of it. When they leave your group, their dot comes back.

## 0.5.0

- **ROSTER and the raid-night pop-up make the raid by themselves.** Invite more than a party holds and the party turns into a raid: on your own, the first four go out and the rest wait until someone joins; in a party, it becomes a raid before the sixth would be refused. Invites still waiting for an answer count, so asking one raider at a time as they log in works past five. (With BiS Tools' party tool on, BiS Tools does the same.) Nobody joins within two minutes: the waiting ones are dropped and named.
- **You show up in FojjiCore's windows.** A party member running FojjiCore now sees your level and experience in its Experience window and your campfire in its Campfires window, instead of "No Addon" (the shared BiS lib, version 16 - quiet if you run FojjiCore's Dungeon Journal yourself, which says the same).

## 0.4.1

- **Carries the shared ride clock** (the BiS lib, version 15): ride a zeppelin or a boat with any BiS addon on and its timetable goes to your guild and group - for BiS Tools' ride card and Power Word: Shell's ZEPPELIN.EXE and HARBOR.EXE.

## 0.4.0

- **RECRUITS, a new terminal tab** (with BiS> Nebbinator 4.0). Everyone sees what the guild needs and which officer set it. Officers also see the guild's recruits - who, how far along, who in the guild is talking to them, when, and the note - and which channel brings the most whispers. An officer's **SET THEM** opens Nebbinator's Team page. Type `recruits` to open it too.
- **RUN REPORT:** what the raid team looks like, by class - who has raided in the last four raids beside every guild member of that class who hasn't. With no raids yet, the roster is the team. A button on the RAIDERS bar, or type `report`.
- **WHERE knows who is in an instance.** A guildmate inside a dungeon, raid or battleground shows docked at its door on the map ("Darth - docked: Shadowfang Keep", "3 docked: Molten Core"), and the list says "in dungeon" instead of a missing dot.
- The tabs are a little narrower, so all six fit beside the prompt.

## 0.3.0

- **Guildmates as tiny figures on the WHERE map.** Each guildmate sharing their spot stands there as a little 3D figure of their race and sex, facing the way they're heading. BiS Guild learns what someone looks like whenever you group with them or target them, and keeps it - they need nothing installed for that part. Someone it hasn't seen yet is a dot, as before.
- **No more names printed on top of each other.** When guildmates stand together - a party, say - their names share one label, like "you +3". Every figure still shows, and the list beside the map names everyone. Names on the map are first names only.
- **Fixed: an "action blocked" error for officers.** BiS Guild read the guild's Information text to see how many ranks count as officers, and Forever doesn't allow addons to read it. It doesn't any more: officers are the guild master and the rank under.

## 0.2.1

- **BiS addons can talk to other players on Forever again.** The game wrongly says addon messages are restricted, and the shared BiS code believed it, so nothing this addon sends to other players went out. It does now - and your guild's BiS Guild map shows where you are (outside instances; `/biscomm share off` turns that off).
- **Names with surnames work.** The shared code now uses your whole "Name Surname": you no longer show up twice on your own guild map, and party members with surnames are recognised.

## 0.2.0

- **No PowerShell: the BiS Guild notebook.** The terminal's LOG tab has its link - click it, Ctrl+C, paste it in your browser. Press Run all, drop your combat log in, and copy the text it prints; back in game, paste it in the LOG tab and press Import. It runs on Google's computer, under your own Google account - nothing runs on yours. The raid goes in exactly as if an officer had shared it. Our CurseForge page carries the same link, so you can check it.
- **A wrong raid can be archived.** The paste window's "Raids on record" lists every raid with an Archive button; archived raids drop out of every count and sit at the bottom with Restore - nothing is ever deleted. An officer's archive or restore goes to the whole guild, so the raid doesn't come back from another officer's copy.
- **"18 of 25 aren't in your guild"**: Import stops on a raid that's mostly strangers - usually somebody else's log - and takes it only on a second press.
- **RAIDERS lists every guild member**, from the game's guild list. Members with no raids yet are greyed above the pugs; clicking one says they have no raids logged with us yet.
- **The fingerprint is gone**, with the PowerShell warning and `/bisg copy`: nobody runs our script on their own computer any more. Your copy still tells you when a guildmate runs a newer BiS Guild.
- **Gear from TBC logs** is read now (it never was - their lines have one group fewer than Forever's).
- **A night is one raid now, and officers' copies are merged kill by kill.** Two raids on one evening (two teams, or Molten Core then Onyxia) are two nights, so someone at one of them no longer loses the night for missing the other's kills. When two officers read the same raid, BiS Guild lines their logs up by the second - in any time zone - and keeps every boss either of them saw, instead of whichever copy was fuller. Nights already on record stay as they were.

## 0.1.1

Fingerprint (SHA-256 of the whole addon, check it with the command on the CurseForge page): `93B8570923F7CCE40F422614E08BFBD59C527287E992460939285076C5EF67AC`

- **Where BiS Guild comes from:** only its CurseForge page and its GitHub page. A copy from anywhere else is not ours, however official it looks - the CurseForge page says so above the check line.
- The terminal's frame is a thin dark-purple line all round, like BiS Tools' windows. It was a bar along the top in your accent colour, which came out white with EllesmereUI's.

## 0.1.0

Fingerprint (SHA-256 of the whole addon, check it with the command on the CurseForge page): `D0375501644F887783CC69320842BDA7696F962DE882782BFE520070D68B3F33`

The first public release. Loot night, two raiders, one trinket, and everyone thinks they remember who showed up. BiS Guild read the log instead.

- **The raider terminal** (`/bisg`): RAIDERS, BOSSES, WHERE, ROSTER and LOG. Attendance, deaths, flasks and food, gear issues in red, item tooltips with the enchant, the game's own right-click menu on every name. Esc steps back a page.
- **The record comes from your combat log.** A small PowerShell script reads it, only the logs it hasn't read yet, and the addon picks the night up at `/reload`. Nothing to paste.
- **Shared with your officers.** Any officer who reads a log hands the night to the whole guild, so a missed raid still fills in. Only officers are believed. Each guild keeps its own books, so an alt in another guild never sees your main's.
- **Raid night.** Paste the Raid-Helper sign-up: who's online, absent or not in the guild, one button to invite everyone online, a pop-up when a sign-up logs in, and punctuality kept raid after raid.
- **WHERE**: your guildmates on a map, opening in OpenMap when it's installed.
- **Loot**: awards in a tamper-evident ledger per guild, `/bisl`. BiS Loot is folded in.
- **Your copy is checked, three ways.** One fingerprint covers every file, with a one-line PowerShell check on the CurseForge page. The script refuses to run on a copy that doesn't match. In game, a missing or mismatched file switches BiS Guild off and says which, and your guildmates' copies tell you if yours differs or is out of date (`/bisg copy`).
- Works with BiS Tools (invites through its party list) and OpenMap. Needs neither.

## 0.0.1

- Created from the BiS house skeleton (`_bisdev/new-addon.sh`): shared BiS channel, palette, tests, CI and
  release from GitHub already wired.
- Window: the report's "last" line keeps the kill count; the boss names moved into its tooltip. A full
  Black Temple night ran the line out of the window.
