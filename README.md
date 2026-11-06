# Splash SWEPs

[![Discord Banner 2](https://discordapp.com/api/guilds/933039683259224135/widget.png?style=banner2)](https://discord.gg/yrNej7G6gH)

This addon provides a set of water guns, which can actually paint around the world and soak other players.  
If you are interested in this project, watch this the following video for a brief introduction.  
[![Youtube](https://img.youtube.com/vi/2ca3UeLlCZs/0.jpg)](https://www.youtube.com/watch?v=2ca3UeLlCZs)

> [!CAUTION]  
> Many features seen in the video are disabled.  I will add them again in the future.

The aim of this rework is the following:

* Working fine on multiplayer game (especially on dedicated servers)
* Various options!
  * Drawing crosshair
  * Left hand mode
  * DOOM-style viewmodel
  * Aim down sight toggle/hold
  * And so on...

## Important thing - read before testing

***
**I don't intend to let you enjoy the new SWEPs.  Actually I want you to test it to help me fix bugs.**  
**So, I think something like "The addon isn't working for me" isn't worth reading.**  
**If you're going to tell me you're in trouble, go to Issues page and follow the template.**  

* [ ] What happened to you? Write the detail.
* [ ] How to get the same problem? The "step to reproduce" section.
* [ ] Any errors?  If so, the message in the console.
* [ ] Your environment (OS, Graphics card, and so on).
* [ ] Addons in your game - Some of them may conflict. Please specify the one.  
      **Something like "I have 300+ addons" isn't helpful.**

## Known issues

* Loading some large maps with this SWEPs causes GMOD to crash in 32-bit build.
    You can still load them in 64-bit build so I recommend to switch to it.
* You may experience major frame drops if your VRAM amount is not enough.
    Make sure to set the ink resolution option (found in where you change playermodel for the SWEPs) correctly.
* If you see errors on map load and can't paint at all, try removing the cache file.
    * It is located in `garrysmod/data/splashsweps/<mapname>.dat`.
      The server and each player build their own one, so remove it where you see the errors.
* The ink surface doesn't support multiple light styles on a map.

***

## Implemented features

* A new ink system
* A basic water gun weapon
* Basic GUI to change ink color, and other settings.
    GUI menu is in the weapon tab and Utility -> Splash SWEPs.

## How to install this project

Though this is still work in progress, you can download and test it.
If you test it in multiplayer game, all players must have the assets.

* Click **Clone or download** on the top-right, then **Download ZIP**.
* Extract the zip into garrysmod/addons/.  
  * Go to Steam -> LIBRARY -> Garry's Mod
  * Right click the game in the list or click the gear icon -> then Properties...
  * Open **Installed Files** tab and click **Browse...** button at the top right.
  * An explorer pops up. Go to **garrysmod/addons/**.
  * Put the extracted folder named **splashsweps-main** there.

Using an external addon for third person view is also recommended.

* [Enhanced ThirdPerson [Reupload]][1]  

[1]:https://steamcommunity.com/sharedfiles/filedetails/?id=2593095865
