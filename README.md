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
4. The window lists every recipe with:
   - **Mat cost**: the cheapest way to get each reagent, whether from a vendor, the AH market price, or crafting it yourself (for example, making Bolts of Linen instead of buying them).
   - **Sells for**: the lowest AH buyout minus the AH cut. If the vendor pays more, it uses the vendor price, marked `(v)`.
   - **Profit**, **Margin** and **Listed**. Listed is how many are on the AH, which shows how much competition there is.

Hover a row to see the reagent breakdown. Shift-click a row to link the item in chat. Click a column header to sort by it.

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
