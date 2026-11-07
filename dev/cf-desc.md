# BiS Guild — CurseForge page text

Paste everything below the line into the project description, in the Markdown editor.

**NO FINGERPRINT SINCE 18 OCT 2026** (Arn: "can we get rid of the fingerprint thing and just do a
secret powershell feature just for us"). Raiders read their logs in the notebook; the PowerShell
script is the officers' own and is not on this page. **The notebook link below is the check** (Arn:
"the link should also go into the curseforge description so people can double check"): it must be
exactly `U.NOTEBOOK` in `Core/Window.lua`, the link the game shows - the suite holds the two equal.

In the house voice (`_bisdev/docs/voice.md`): the opener and the script section talk; lists stay flat.

**Name:** BiS Guild
**Summary (the one-liner):** Your guild's raid record, read from the combat log: who showed, who came prepared, who's late, who's geared. For WoW Forever.

---

# BiS Guild

**Your guild's raid record, read from the combat log. For WoW Forever.**

Loot night. Two raiders want the same trinket. One has been to every raid this month, flasked, on time. The other hasn't. Everyone in the room thinks they remember which is which. BiS Guild doesn't remember. It read the log.

## What you get

`/bisg` opens the raider terminal. Six tabs.

- **RAIDERS** — your whole guild, and everyone who has raided with you: attendance, last raid, flask or elixirs, deaths, and gear issues in red, like a slot that should be enchanted and isn't. Sorted by class the way a raid sheet reads, pugs at the bottom. Click a name for their whole card. **RUN REPORT** shows the raid team by class: who has raided in the last four raids, beside every guildmate of that class who hasn't.
- **BOSSES** — every boss you've killed: kills, wipes, your best time, the night it first died, and who was there.
- **WHERE** — your guildmates on a map, right now, each a tiny 3D figure of their race. Someone inside a dungeon or raid shows docked at its door. Click one and the map opens on their zone. With OpenMap installed, one button opens it there.
- **ROSTER** — paste the Raid-Helper sign-up and see who's online, who's absent, who isn't in the guild. One button invites everyone online.
- **RECRUITS** — with BiS> Nebbinator: what the guild needs and which officer set it. Officers also see every recruit the guild is talking to, who is talking to them, and which channel brings the most whispers.
- **LOG** — read a raid: the notebook's link and the box to paste its text into (below).

Hover any item for its tooltip, enchant included. Right-click any name for the game's own player menu. Esc steps back a page; keep pressing and it closes.

## Raid night, handled

- **The raid at a glance.** Title, start time, a countdown, and how many sign-ups are online.
- **A pop-up when a sign-up logs in**, with an invite button on it. From two hours before the raid until four hours after. Off until you switch it on (options, or `/bisg logins on`).
- **Punctuality.** With the pop-up on: on time, late and by how long, or a no-show, kept raid after raid. "Late twice in eight" says more than one bad night. An invite that went out late is never held against the raider.
- **Loot.** Every award goes into a tamper-evident ledger, kept per guild. `/bisl` shows it.

## Shared with your officers

Any officer who reads a log hands the night to everyone else in the guild. Miss a raid and your copy still fills in. Nights, gear and punctuality are only taken from officers, so nobody can write themselves into the record. Officers are the guild master and the rank under.

Your alts keep their own books. A character in another guild sees that guild's record, never your main's.

## The numbers come from your combat log

An addon isn't allowed to read files off your disk, and that's a good rule. So a notebook reads it for you:

1. [Open the BiS Guild notebook](https://colab.research.google.com/github/blankfer/BiSGuild/blob/main/dev/BiSGuild.ipynb), press **Run all**, drop your combat log in (zipped is faster), and copy the text it prints.
2. In game: the terminal's **LOG** tab (or `/bisg paste`), Ctrl+V, **Import**.

It runs on Google's computer under your own Google account, so nothing runs on yours. Google will say it "was not authored by Google" - that's every notebook Google didn't write; press Run anyway.

**Pasted the wrong log?** BiS Guild warns you when most of a raid isn't in your guild, before it takes it in. And **Raids on record** lists every raid with an Archive button: an archived raid stops counting, nothing is ever deleted, and Restore brings it back. When an officer archives one, it's archived for the whole guild.

**Double-check the link.** The LOG tab shows the same link. This is the one that counts: it should start `colab.research.google.com/github/blankfer/BiSGuild`. If a link you were given goes anywhere else, it isn't ours. We publish BiS Guild in two places only: **this CurseForge page** and **its GitHub page** (github.com/blankfer/BiSGuild).

Two officers who read the same raid end up with the same night: BiS Guild lines their logs up to the second and keeps every boss either of them saw.

- **Attendance**: a raid night counts if you were there for at least half its boss kills. Leaving at nine for a sick kid doesn't cost you the night.
- **Consumables**: at each pull, a flask (or a battle and a guardian elixir) and food.
- **Gear**: what each raider wore at the pull, straight from the log. No inspecting.

A 110 MB log takes seconds. `/biscomm ver` shows which BiS versions your guild runs; switch on the newer-version note and your copy says so in chat when a guildmate has a newer BiS Guild.

## Starts quiet

A new install starts with only its main job on: the terminal and the record. The login pop-up, guildmates' dots on the world map and the newer-version note wait for you to switch them on - in **Esc > Options > AddOns > BiS> > BiS> Guild**, or `/bisg options`. Already using BiS Guild? Everything stays as you had it.

## Works with

- **BiS Tools** — when it's installed, invites go through its party list. Without it, BiS Guild invites on its own.
- **OpenMap** — when it's installed, the WHERE tab can open a guildmate's spot in it.
- **BiS> Nebbinator** — fills the RECRUITS tab, and its ads can say your next raid from the sign-up you pasted.
- **Other addons** can read the record through `BiSGuildAPI`.

None of them is needed. BiS Guild works alone.

## Commands

| | |
|---|---|
| `/bisg` | open the terminal |
| `/bisg paste` | read a raid: the notebook's link, and its text in |
| `/bisg options` | every switch, in one window |
| `/bisg logins on` / `off` | the pop-up when a sign-up logs in |
| `/bisg dots on` / `off` | guildmates on the world map |
| `/bisg note on` / `off` | a chat line when a guildmate runs a newer version |
| `/bisl` | the loot ledger |

Part of the BiS family. Talks to the other BiS addons over one shared channel; `/biscomm off` silences it.
