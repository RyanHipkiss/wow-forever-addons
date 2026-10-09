# CraftProfit

A World of Warcraft: Forever addon (interface 16001) that scans the auction house and lists which of your recipes make a profit if you buy the materials and sell the crafted item on the AH.

## Install

Copy the `CraftProfit` folder into:

```
E:\BattleNet\World of Warcraft\_classic_beta_\Interface\AddOns\
```

(`_classic_beta_` is the Forever client folder.)

## Use

1. **Open each profession window once** on every character. CraftProfit saves the recipes that character knows, and the recipes stay saved across all your alts.
2. **Visit a trade goods vendor** (optional, but it helps). CraftProfit records what merchants charge, so threads, vials, flux and other vendor mats get priced.
3. **Go to the auction house and click "CraftProfit", then "Scan AH".** This takes a full snapshot of the AH. Blizzard allows one full scan every 15 minutes.
4. **When the scan finishes, the window opens on the profitable recipes, most profitable first.** Each row shows:
   - the item you craft, who can craft it, and the **Mat cost**, **Sells for**, **Profit**, **Margin** and **Listed** count (how many are on the AH, which shows the competition);
   - underneath, **the mats to buy for one craft** and where each comes from: the AH price, the vendor price, or "craft it" when making it yourself is cheaper (for example, Bolts of Linen).

   Mat cost uses the cheapest of the vendor price, the AH market price, or your own craft cost. Sells for is the lowest AH buyout minus the AH cut; if a vendor pays more, it uses that and shows `(v)`. Untick **Profitable only** to see every recipe.

Hover a row to see the reagent breakdown. Shift-click a row to link the item in chat. Click a column header to sort by it.

## Browser dashboard

Each AH scan saves a daily history of every recipe's profit. The dashboard shows it in your browser:

- **Today's alerts** at the top: profitable recipes whose profit went up compared with the previous day you scanned. Recipes that have just become profitable are flagged.
- **Profitable recipes**, each with how long it has been profitable (for example, "Profitable for 48 days · since 22 Aug"), today's change, margin, AH competition, the mats to buy, and a chart of profit per craft over time (hover it, or focus it and use the arrow keys). "Daily values" shows the numbers as a table.

### Sales at price

WoW doesn't tell addons what other players' auctions sold for, so CraftProfit tracks **your own sales**. It reads your "Auction successful" mails whenever you open a mailbox, so open the mailbox before taking the gold. Each recipe card shows how many you sold **at or above the price its profit is based on** (the lowest AH buyout from the latest scan). Sales below that price aren't counted. You can pick a period (7, 30 or 90 days, or all time), set **Min sold at price** to hide recipes that haven't sold enough, or sort by **Sold at price**.

### Run it

You need [Node.js](https://nodejs.org) 18 or newer. There is nothing to install.

```
cd C:\Users\ryan\Desktop\wow-craft-profit\dashboard
node server.js
```

Or double-click `dashboard\start-dashboard.cmd`. Then open http://localhost:4747.

WoW only writes addon data to disk on **/reload, logout or exit**. So after a scan, type `/reload`, and the dashboard picks up the new data within 15 seconds. The server looks for `CraftProfit.lua` under `E:\BattleNet\World of Warcraft\_classic_beta_\WTF\Account\*\SavedVariables\`. To use another install, set `CRAFTPROFIT_WOW` to its `_classic_beta_` folder, or pass the file path: `node server.js "<path>\CraftProfit.lua"`. Add `?theme=light` or `?theme=dark` to the URL to override your system theme.

How long a recipe has been profitable is counted from the days you scanned. If you skip a few days, the run carries on as long as every day you did scan was profitable. The history keeps 400 days.

## Pricing rules

- **AH market price** is the average unit price of the cheapest 15% of the listed quantity. That is roughly what you would actually pay when buying a stack of mats, and one cheap listing can't skew it.
- **Sell price** is the lowest buyout per item, because that is the price you have to undercut.
- **Bid-only auctions** are ignored.
- **AH cut** defaults to 5%. Use `/cp cut 15` on a neutral (goblin) AH.

## Commands

| Command | What it does |
| --- | --- |
| `/cp` | Toggle the window |
| `/cp scan` | Scan the AH (you must be at the AH) |
| `/cp cut <percent>` | Set the AH cut |
| `/cp vendor <item link> <copper>` | Set a vendor price by hand |
| `/cp forget` | Forget this character's saved recipes |

## Limits

- Enchants and other recipes that don't create an item are skipped.
- Only basic (required) reagents are counted. Optional reagents are ignored.
- AH prices are stored per realm and faction.
