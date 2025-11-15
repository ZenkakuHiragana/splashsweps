# Project Overview

This project is a Garry's Mod addon named **Splash SWEPs**. It provides a framework for creating Splatoon-like weapons that can paint ink onto world surfaces and affect other players. The system is designed to work on multiplayer dedicated servers and offers various customization options.

The core of the addon is a Lua-based library that handles the complex logic of painting, collision detection, and networking, while allowing developers to easily create new weapons and ink types.

**Technologies:**
*   **Language:** Lua (Garry's Mod API)
*   **Shaders:** HLSL (for custom rendering effects)
*   **Data:** JSON (for defining content like ink types)

**Architecture:**
*   The project follows the standard Garry's Mod addon file structure.
*   A global table `SplashSWEPs` (aliased as `ss`) is used as a namespace for all shared functions and data, preventing global scope pollution.
*   Code is logically separated into `client`, `server`, and `shared` directories.
*   The shared code acts as a library/API for other parts of the addon. For example, `ss.Paint(...)` is used to draw ink, and `ss.ReadGrid(...)` is used to check for ink at a specific position.
*   Content such as different types of ink is defined in `.json` files located in `data_static/splashsweps/inktypes/`, making the system data-driven and easily extensible.
*   The Lua code is annotated with `---@class` style comments, suggesting it is written to be used with a language server like LuaLS for static analysis and better development tooling.

# Building and Running

This is a Garry's Mod addon and does not have a traditional build process.

**Installation:**
1.  Download the project files.
2.  Place the entire `splashsweps` folder into your Garry's Mod `addons` directory. The path is typically `steamapps/common/GarrysModDS/garrysmod/addons/`.
3.  Start Garry's Mod. The addon will be loaded automatically.

**Running in-game:**
*   The test weapon, "Inkling base", can be found in the weapons list under the "Other" category.
*   Configuration options for the addon can be found in the Utilities tab in the spawn menu (`Q` menu) under "Splash SWEPs".

# Development Conventions

*   **File Structure:** Adheres to the standard Garry's Mod addon structure (`lua/autorun`, `lua/weapons`, `materials`, etc.).
*   **Namespacing:** All shared code should be part of the `SplashSWEPs` global table.
*   **Data-Driven Design:** New content like ink types should be created by adding new JSON files rather than hardcoding values in Lua. An ink type requires a `.json` file in `data_static/splashsweps/inktypes/` that specifies its name and material properties.
*   **Weapon Creation:** New weapons can be created as standard SWEPs in the `lua/weapons/` directory. These weapons should use the `SplashSWEPs` API to implement their painting functionality (e.g., calling `ss.Paint` on primary fire).
*   **Code Style:** The code uses annotations for static analysis. It is recommended to use a compatible tool (like VS Code with the `sumneko.lua` extension) to maintain style and quality.
    *   **Naming Convention:** All public functions should use `CamelCase`, but if you are going to implement a very common or fundamental functions it should use names like `builtinfunctions`. local variables should use `builtinfunction` but if it has a long name or is harder to read (usuall having more than three words) it should use `lowerCamelCase`.
    *   **File Names:** Lua file names under splashsweps should be like `builtinfunctions`.
    *   **Class Definition:** Do not use metatable-based class definition. Define structures using `ss.struct` and instantiate defined classes using `ss.new`. The class name in lua annotation should begin with `ss.` and the class name as the argument of `ss.struct` and `ss.new` should have no `ss.` prefix. Class methods (fields storing a function) should not be used.
    *   **File Inclusion:** Do not `include` in the middle of files. All includes should be placed in autorun.lua with alphabetical order.
    *   **Typing:** If you define and initialize an empty table as a local variable, write a type hint with `---@type` annotation to indicate what it will store.
    *   Diagnose Lua files using `lua-language-server --configpath .vscode/config-sv.lua --check path/to/lua/to/check.lua` and resolve the warnings as possible as you can. if you are editing clientside code, use the `--configpath .vscode/config-cl.lua` instead.
*   **References:**
    *   All GMOD Lua APIs are defined under .vscode folder. Make sure you don't write undefined functions using these files.
    *   If you are still unsure, visit https://wiki.facepunch.com/gmod to search necessary information.
    *   If you want Source Engine specific information, visit https://developer.valvesoftware.com/wiki and search Valve Developer Community.
