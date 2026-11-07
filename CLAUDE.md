Read ../_bisdev/CLAUDE.md first.

## Layout (BiSGuild only)

- `BiSGuild.toc`: the load order and the only place the version lives (`## Version`). It also carries
  `## X-Curse-Project-ID` (0 until the CurseForge project exists) and `## X-CurseForge-GameVersionType`,
  which `dev/release.ps1` reads.
- `Core/Init.lua`: the house skeleton from `_bisdev/new-addon.sh` — palette per call (`ns.T`), `ns.VERSION`
  from the TOC, `ns.Print`, `BiSGuildDB` defaults, the shared BiS channel booted with its off switch saved,
  and `/bisg`, which hands straight to `ns.Say`.
- `Core/Report.lua`: what the combat log said. `BiSGuildReport` is written into `Data/Report.lua` by
  the script and loaded like any other file, so `/reload` IS the import - nothing is typed or pasted.
  Also remembers where the player's Logs folder is (asked once) and builds the PowerShell line from
  it: `Logs` and `Interface` are SIBLINGS inside the client folder, so dropping `\Logs` is the whole
  derivation and it works at any depth.
- **No fingerprint since 18 Oct 2026** (Arn: "can we get rid of the fingerprint thing and just do a
  secret powershell feature just for us"). 16-18 Oct a SHA-256 of every file was stamped, checked and
  published (stamp.ps1, manifest, Core/Build.lua, `ns.parts`); all gone - no stamp step, nothing to
  rerun. **Raiders read logs in the notebook** (`dev/BiSGuild.ipynb`, Google's computer, the reader
  fetched from our GitHub); **the PowerShell road is the officers' own** - `/bisg window|logs|script`
  still work, unlisted in `/bisg help` and on the page. `Core/Copies.lua` is only the "a guildmate runs
  a newer version" nudge now (GLOG `BUILD`, middle field always `-` so 0.1.x copies still accept it).
- **The notebook link is the check** (Arn: "the link should also go into the curseforge description
  so people can double check"): `U.NOTEBOOK` in `Core/Window.lua` is shown in the LOG tab's window and
  must equal the link on the page (`dev/cf-desc.md`) - the suite holds them equal.
- **Published only on CurseForge and GitHub** (Arn, 17 Oct) - the page says any other copy isn't ours.
- **Archived raids (18 Oct 2026)**: never deleted - `record.archived[key] = {night, t, by}`, out of
  every count and share; a copy of an archived raid is refused (`S.ArchivedAs`) and counts as held
  (`X.HaveRaid`). Later decision wins (`t`; `record.restored[key]`). An officer's archive/restore goes
  out as GLOG `ARCH` (key + check number, so a copy keyed a day off finds it); an officer who hears a
  HAVE2 offering a raid it archived re-sends ARCH once a session. The list: `U.ShowRaids`.
- `Core/Window.lua`: three windows. The RAIDS list (`U.ShowRaids`, from the paste window). The PASTE window (`U.ShowPaste`, the LOG tab, `/bisg paste`): the
  notebook's link, the box, Import and its progress bar. The officers' SCRIPT window (`U.Show`,
  `/bisg window`): a terminal on purpose (Arn: "the more we make it look like a powershell window the
  better") - PowerShell's own `#012456`, Arial Narrow, a `PS>` prompt, a cursor blinking at 2 Hz.
- **Nothing is collected in game.** The addon used to count boss kills and who was standing there;
  that was a second source of truth against the combat log, and when two disagree the one people
  believe is the one on the website (Arn, 5 Oct: "we can get rid of the attendence and consume check
  lets do logs for that"). `dev/logreport.py` and `Tools/logreport.ps1` read the log instead - one
  line at a time, so 110 MB costs seconds and not memory, and with `FileShare.ReadWrite` so it works
  while WoW still has the file open. Which auras count is DATA (`dev/consumables.txt`), never a rule
  in the code: the buff does not carry its item's name.
- `Core/Say.lua`: the slash commands. Bare `/bisg` opens the window; `report`, `logs <path>` and
  `script` are the rest, and anything unrecognised is the report, because there is nothing else it
  could mean now.
- **Forever 1.0 (7 Nov 2026), quiet start**: `ns.Settle()` (Core/Init.lua, at ADDON_LOADED, before the defaults)
  says new or existing - no table, or only the one our own `db()` made (`ns.madeHere`), is NEW. `ns.Forever10`
  writes `ns.QUIET` (logins, mapDots, versionNote = false) into a new install, or FREEZES an existing save
  (logins/mapDots were read `~= false`: written as what they showed; versionNote = true), then stamps `forever10`.
  Never twice. No per-character mirror here, so a lost save reads as new (quiet).
- `Core/Options.lua` (`ns.Opt`): the options window (BiSTheme's kit, `BiSGuildOptions`) and the BiS> Guild page
  (`O.Register` at PLAYER_LOGIN, `status()` = "logins - dots - note"). Every switch and its slash command share one
  setter (`O.SetLogins/SetDots/SetNote/SetComm/SetShare`). `/bisg options` opens the options WINDOW (8 Nov, like the family's right-click); the page is Esc > Options > AddOns.
  Since Settings minor 2 (8 Nov) the page never takes the options window in (Arn: "dont just shrink remake them
  all"): it shows the status line and a button "the options window", which closes the game's options and shows the
  window as it always was. A dashboard (`build`) comes later. **No minimap button** - never had one, so no
  right-click to fix; `/bisg` and the BiS> page are the doors.
- The terminal's right-click player menu (`K.PlayerMenu`) opens only where `IsInInstance()` reads a plain false
  (`K.OutInTheWorld`): inside an instance the game's menu breaks on secret frame rects.
- `Libs/`: embedded `BiSTheme/Console.lua`, `Options.lua` (since 1.0.0), `Settings.lua` and `LibBiSComm-1.0` —
  copies, see `../_bisdev/CLAUDE.md`.
  Since 16 Oct also three THIRD-PARTY libs, BiS Tools' copies byte for byte (the suite checks):
  `LibStub`, `CallbackHandler-1.0`, `HereBeDragons` (BSD) - sources and commits in
  `Libs/THIRD-PARTY.txt`. Never edit them. The suites compile HereBeDragons but never run it (it drives
  the client's map engine); `dev/tests.lua` swaps in a strict pins stand-in.
- `Core/Store.lua`, `Core/Share.lua`: the guild's record (`BiSGuildDB.record`) and its sharing over
  LibBiSComm GUILD ("GLOG", officers believed). **Since 17 Oct a night is ONE RAID** (`dev/NIGHTS.md`):
  key `"YYYY-MM-DD <instance>"` (`-2` for a second raid of it that date), holding every pull (UTC time,
  encounter, who with which consumables as flags, deaths, potions); the totals are DERIVED
  (`S.Derive`, the same rule as `logreport.py` `derive` and the .ps1). Two officers' copies MERGE pull
  by pull (`S.SameRaid`, `S.Merge`); sharing is HAVE2/WANT2/NIGHT2. Whole-date nights from before stay
  (old HAVE/WANT/NIGHT) and never sit beside raids of their date. Show a key with `S.Label` /
  `S.DateOf`, never raw. **`dev/test_logreport.py` is NOT in check.sh** - run it by hand after any
  reader or Store change (it was broken 16-17 Oct and nobody saw): `python dev/test_logreport.py`. `Core/Terminal.lua`, `Core/Where.lua`: the raider
  terminal and its WHERE page. `Core/Pins.lua`: guildmates' dots on the world map. Plan: `dev/TERMINAL.md`.
- `dev/tests.lua`: headless suite on `dev/kit.lua` (Nebbinator's strict harness, verbatim). Loads the TOC's
  files in order, fails on any global not in `ALLOWED`. `dev/theme.lua`: the palette law.
- `dev/release.ps1`: zip + CurseForge upload (normally GitHub runs it on a tag — see
  `../_bisdev/docs/playbook.md`).
- `.github/workflows/check.yml` (every push/PR) and `release.yml` (tag = release, PR = dry run).
