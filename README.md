<h1 align="center"> GatheringTracker </h1> <br>

<div align="center">
    <a href="https://www.curseforge.com/wow/addons/gathering-tracker" target="_blank">
        <img alt="CurseForge Downloads" src="https://img.shields.io/curseforge/dt/406104?style=for-the-badge&label=CurseForge"> 
    </a>
    <a href="https://www.curseforge.com/wow/addons/gathering-tracker" target="_blank">
        <img alt="CurseForge Version" src="https://img.shields.io/curseforge/v/406104?style=for-the-badge">
    </a>
    <a href="https://www.curseforge.com/wow/addons/gathering-tracker" target="_blank">
        <img alt="CurseForge Game Versions" src="https://img.shields.io/curseforge/game-versions/406104?style=for-the-badge">
    </a>
</div>

<div align="center">
  <img width="70%" src=".previews/GT2.png?" />
</div>
<p align="center" style="font-style: italic">
  Gathering Tracker provides a HUD to track any item.
</p>

## Features

- Supported on all versions of WoW, including WoW Forever
- Session window with a summary panel and one line per item gathered this session
  - Time, Looted gold, Herb value, Ore value (shown once you gather some) and Gold per hour
  - Pause / Resume and Reset buttons; the minus button collapses the item list
  - Drag the title bar to move it, right-click it for the Filter Menu
  - Uses the game's own fonts, so it matches your UI
- Display AH Price Data
  - Currently supports: TradeSkillMaster, Auctionator, and RECrystallize
- Can track any item in the game
- Can track any supported Currency
- Filter options accessible through the window title bar, minimap icon, or broker icon

## Commands:

/gt or /gatheringtracker will open the addon configurations

## Tests

`lua5.1 tests/run_tests.lua` loads the addon against a mock WoW client and checks every element of the session window.

## Issues/Support:

For any issues, support, or feature requests please submit an issue on [Github](https://github.com/Noshei/GatheringTracker).
