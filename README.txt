CURSOR QUEST CHOICES v2.4.2
By Darksolis
WoW 3.3.5a / Conquest of Azeroth

============================================================
OVERVIEW
============================================================

Cursor Quest Choices brings NPC interactions, quest rewards, and merchant access closer to your mouse cursor while also providing optional quest automation.

It is built for WoW 3.3.5a and has been specifically tuned around the custom quest/gossip behavior used on Conquest of Azeroth.

============================================================
CORE FEATURES
============================================================

CURSOR NPC INTERACTIONS
- Quest and gossip choices appear beside your cursor.
- Supports available quests, active quests, completed quests, and normal NPC gossip options.
- Handles merchants, trainers, bankers, taxi NPCs, and other gossip interactions.
- Long text is kept inside the panel and full text remains available through tooltips.
- Mouse-wheel scrolling for long interaction lists.
- Automatically positions around screen edges.
- First-click gossip data is refreshed automatically when the server initially returns incomplete names/icons.

AUTO QUEST
- Automatically accepts eligible quests.
- Automatically turns in completed quests.
- Supports NPCs with multiple quests.
- Uses short retry logic for private-server event timing so quests are not skipped when the next gossip event arrives too quickly.
- Skips trivial/grey quests when enabled.
- Blocks quest titles containing configured blocked words.
- Default blocked word: Commission.
- Hold SHIFT while interacting with an NPC to temporarily pause quest automation.

QUEST REWARDS
- Manual reward selection beside the cursor.
- Highest Vendor Value mode.
- Stats-based reward mode.
- Stats mode can either auto-select or show scores and let you choose.
- Full item tooltips remain available when choosing rewards.

MERCHANTS
- The real Blizzard merchant frame can open beside the cursor.
- Merchant position is captured when the merchant opens and remains fixed while shopping.
- Opens to the LEFT of the cursor when there is room, helping avoid bags commonly placed on the right side of the screen.
- Automatically falls back to another side when needed to stay on-screen.
- Native merchant functionality remains intact, including repair, buyback, special currencies, extended costs, stack sizes, and limited stock.
- Optional compact cursor-side merchant inventory is available in settings.

HERO'S CALL BOARD
- Hero's Call Board support is independently toggleable.
- By default, Cursor Quest Choices remains inactive on Hero's Call Board.
- This setting is intended to affect ONLY Hero's Call Board and not merchants, trainers, or normal NPC quest interactions.

/cqc callboard off
  Keeps Cursor Quest Choices inactive on Hero's Call Board.

/cqc callboard on
  Allows Cursor Quest Choices to operate on Hero's Call Board.

============================================================
REWARD MODES
============================================================

MANUAL
Choose your reward yourself from the cursor-side reward panel.

VALUE
Automatically selects the quest reward with the highest vendor value.

STATS
Uses item stats and class/stat weighting to score rewards.

Stats behavior can be set to:
- AUTO: automatically choose the highest-scoring reward.
- PICK: show scores and let you make the final choice.

============================================================
SLASH COMMANDS
============================================================

/cqc options
  Open addon settings.

/cqc on
/cqc off
  Enable or disable Cursor Quest Choices panels.

/cqc auto on
/cqc auto off
  Enable or disable automatic quest handling.

/cqc callboard on
/cqc callboard off
  Enable or disable addon functionality specifically on Hero's Call Board.

/cqc mode manual
/cqc mode value
/cqc mode stats
  Change quest reward mode.

/cqc stats auto
/cqc stats pick
  Choose whether Stats mode automatically selects or lets you pick.

/cqc focus AUTO
/cqc focus STR
/cqc focus AGI
/cqc focus INT
/cqc focus STA
/cqc focus SPI
/cqc focus AP
/cqc focus SP
/cqc focus HIT
/cqc focus CRIT
/cqc focus HASTE
/cqc focus EXP
  Set the stat focus used by Stats reward mode.

/cqc scale 0.8-1.5
  Change cursor panel scale.

/cqc rows 5-15
  Change the maximum number of visible rows before scrolling.

/cqc width 320-520
  Change cursor panel width.

/cqc hideblizzard
  Toggle the normal Blizzard gossip window while using the cursor panel.

/cqc block add <word>
/cqc block remove <word>
  Add or remove words used to prevent specific quests from being auto-accepted.

/cqc reset
  Reset Cursor Quest Choices settings to defaults.

Legacy /aq and /aqm slash commands are also supported.

============================================================
INSTALLATION
============================================================

1. Exit World of Warcraft.
2. Delete the existing folder completely:

   World of Warcraft\Interface\AddOns\CursorQuestChoices

3. If the old standalone AutoQuestMaster335 addon is still installed, remove it as well.
4. Copy the new CursorQuestChoices folder into:

   World of Warcraft\Interface\AddOns\

5. Start WoW.
6. Enable "Load out of date AddOns" if your client requires it.

Do not merge a new version over an old addon folder. Removing the old folder first prevents leftover versioned Lua files from being loaded.

============================================================
CURRENT VERSION - 2.4.2
============================================================

v2.4.2
- Fixed intermittent auto-accept failures caused by new gossip/quest events arriving while the previous action lock was still active.
- Added bounded retries when quest data arrives slightly late on the private server.
- Reduced the chance that stale Hero's Call Board UI state can interfere with normal NPC quest selection.

Recent improvements also include:
- Hero's Call Board-specific controls.
- Restored normal NPC quest automation after Call Board isolation work.
- First-click gossip refresh for incomplete NPC interaction data.
- AdiBags-safe UI scanning to prevent GetRegions() stack overflows.
- Merchant frame cursor anchoring with stable positioning while shopping.
- Multi-quest NPC continuation and safer quest event timing.

============================================================
NOTES
============================================================

Cursor Quest Choices is designed around the older WoW 3.3.5a API plus private-server behavior. Some custom server interfaces do not follow Blizzard's normal event order, so the addon contains compatibility handling specifically for those cases.

If testing a new version, always replace the full addon folder rather than copying individual Lua files over older builds.

Cursor Quest Choices
By Darksolis
