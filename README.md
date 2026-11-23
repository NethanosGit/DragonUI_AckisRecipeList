# DragonUI_AckisRecipeList

Shows the recipes you have **not learned yet** inside [DragonUI](https://github.com/NeticSoul/DragonUI)'s
Professions window, using the recipe database of **AckisRecipeList**, so you no longer need Ackis's own window.

For WoW 3.3.5a (WotLK). It is an add-on for DragonUI and does not modify it.

## What it does

- Adds the recipes you have not learned to the profession list, greyed out, under the category they belong to
  (Elixirs, Potions, Bracer, ...), highest required skill first. Only recipes up to your **current skill** are shown.
- Learned recipes are mixed into the same order, so the whole category reads by skill.
- Clicking one shows, in the right-hand pane: what it makes, its reagents (icon, how many you carry, vendor
  price when known) and **where to get the recipe** (trainer, vendor, quest, drop, reputation, with zone and
  coordinates).
- The skill needed is shown next to the recipe name in the details pane (the list rows stay clean).
- Learned recipes are **cached**, so nothing is scanned each time the window opens. The Ackis **Scan** button on the
  profession window becomes a **Re-Scan** button that re-reads the open profession.
- Settings window: `/duiarl` (show or hide the feature, hide grey recipes, re-scan everything).

## Requirements

- [DragonUI](https://github.com/NeticSoul/DragonUI) (with its Professions window enabled)
- AckisRecipeList (v2.01 for 3.3.5a)

Both are listed as dependencies in the `.toc`, so the game will not load this add-on without them.

## Installation

1. Copy the `DragonUI_AckisRecipeList` folder into `Interface\AddOns\`.
2. **Edit one line in AckisRecipeList** (below). This step is required.
3. Start the game (or `/reload` after editing).

## The one edit you must make in AckisRecipeList

AckisRecipeList keeps its recipe tables in a private variable that other add-ons cannot see. This add-on needs
one line that makes it visible. You do not need to understand it, just add it:

1. Open `Interface\AddOns\AckisRecipeList\core.lua` in a text editor (Notepad is fine).
2. Find the block of lines that starts around **line 84** and ends around **line 93**:

   ```lua
   private.custom_list	= {}
   private.mob_list	= {}
   private.quest_list	= {}
   private.recipe_list	= {}
   private.reputation_list	= {}
   private.trainer_list	= {}
   private.seasonal_list	= {}
   private.vendor_list	= {}
   private.location_list	= {}
   private.acquire_list	= {}
   ```

3. Right **after the last line of that block** (`private.acquire_list	= {}`, around **line 93**), add an empty line
   and then this new line:

   ```lua
   addon.private = private
   ```

   The result should look like this:

   ```lua
   private.acquire_list	= {}

   addon.private = private

   -- Filter flags and acquire types - defined in Constants.lua
   ```

4. Save the file and restart the game or type `/reload`.

If you do not find those lines (a different version of Ackis), search the file for `private.acquire_list` and add
`addon.private = private` on the next line after it is first created.

If the line is missing, the add-on tells you in chat at login, and `/duiarl` shows
"line missing in core.lua". **If you update or replace AckisRecipeList, repeat this edit.**

## Settings and commands

| Command | |
| --- | --- |
| `/duiarl` | Open the settings window |
| `/duiarl debug` | With an unlearned recipe selected: prints what is stored for each of its reagents (to find out why an icon is missing) |

## Notes

- **Reagents:** AckisRecipeList has no reagent data. They are read from the recipe's tooltip. Item details (icon,
  quality, price) are stored in the saved variable `DragonUI_AckisRecipeListDB`, filled from the recipes you know,
  your bags and bank, and any vendor you open.
- **Vendor prices** appear only for items whose vendor you have seen: the game cannot report a vendor's price
  without opening that vendor's window.
- **Categories** are learned from the recipes you already know (an unlearned recipe goes under the header that
  recipes of the same kind sit under). A recipe of a kind you have never learned is not shown.
- **Specialty** recipes (for example Goblin Engineering) and recipes of the other faction are not shown.
- The add-on wraps some of DragonUI's profession functions at runtime. A DragonUI update that changes
  `addon.Professions` (`Model`, `List`, `Details`, `Art`) may break it.
- **Safety net:** if the profession list is ever rebuilt in a runaway loop (more than 150 times in a second),
  the Ackis part switches itself off until `/reload` and prints a red message with a call trace in chat. If you
  see it, please report it with the trace.
- Saved data is per character (settings, learned recipes) and per account (item details), all in
  `DragonUI_AckisRecipeListDB`.

## Credits

Recipe data and acquisition sources: AckisRecipeList by Torhal, Pompachomp, Ackis, Zhinjio, Jim-Bim and
contributors. Window and frame art: DragonUI, read from DragonUI at runtime; nothing is copied.
