![BalatroGoesBzzz banner with pixel-art playing cards](assets/balatrogoesbzzz-banner.png)

# BalatroGoesBzzz

**Version 1.0.0**

BalatroGoesBzzz integrates the Buttplug SDK with Balatro through Intiface Central. It turns game events such as playing or discarding cards, scoring, shop purchases, opening boosters, and blind results into vibration feedback.

- Use multiple compatible toys simultaneously, each with its own intensity setting and test button.
- Configure events, intensity, and devices from a built-in, touch-friendly menu.
- The mod follows Balatro’s language setting and supports all 15 game languages, with English as a fallback.

## Installation

1. Use Lovely 0.8.0 or newer (including in your Android build). Install [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector#manual-installation) on desktop or use [Lovely Mobile Maker](https://lmm.shorty.systems/) to prepare a modded Android build from your Steam copy. Steamodded is optional.
2. Download or clone this repository. Name the folder **`BalatroGoesBzzz`** and put it in your `Mods` directory. Keep the Lua files and the `translations/` folder together so that `lovely.toml` is directly inside `Mods/BalatroGoesBzzz/`.

   | Platform | Mod folder |
   | --- | --- |
   | Windows | `%AppData%\Balatro\Mods\BalatroGoesBzzz` |
   | macOS | `~/Library/Application Support/Balatro/Mods/BalatroGoesBzzz` |
   | Android | `ASET/Mods/BalatroGoesBzzz` ([how to access the Mods folder](https://lmm.shorty.systems/faq)) |

3. Install [Intiface Central](https://intiface.com/central/) and [start its engine](https://intiface.com/docs/intiface-central/quickstart/). BalatroGoesBzzz uses Buttplug protocol v2 and connects to `127.0.0.1:12345` by default. If Intiface runs on another device, set `intiface_host` in `lovely.toml` to that device’s IP address. Change `intiface_port` there if your setup uses a different port.
4. Launch Balatro with Lovely. On macOS, use `run_lovely_macos.sh` from the game directory.

When updating from an earlier release, move the old `BalatroBuzz` folder outside `Mods` and install the complete new `BalatroGoesBzzz` folder. Keep your existing `settings.json` and replace the other mod files together. Keep only one copy of the mod in `Mods`.

## Using the mod in game

1. Open **Options → BalatroGoesBzzz**, or press **F6** on a keyboard.
2. Open **Devices** and select **Scan / connect** if your toys are missing. Turn on **Use** for each toy you want to activate. Use the arrows to browse additional devices.
3. Set each device’s strength and use **Test** beside the device to check it individually.
4. Open **Cards & score** or **Shop & round** to enable events and adjust their intensity. An event test runs on all selected devices. The event intensity is multiplied by each device’s strength, so a 60% event on a device set to 50% runs at 30%.
5. Select **Done** to return to the game. Settings are saved automatically. Select your devices again after reconnecting or restarting.

## License

BalatroGoesBzzz is licensed under the [MIT License](LICENSE). The bundled JSON library retains its copyright notice in [`json.lua`](json.lua). The bundled WebSocket client is based on [flaribbit’s MIT-licensed LÖVE WebSocket client](https://github.com/flaribbit/love2d-lua-websocket).
