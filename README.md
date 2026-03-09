# crash_dslrcamera

A FiveM resource that adds a DSLR-style camera for police/roleplay use. Take in-game screenshots, tag evidence in frame, and save photos to an SD card with metadata (location, time, street name).

## Requirements

- **ox_lib**
- **ox_inventory**
- **screenshot-basic**

## Installation

1. Drop the `crash_dslrcamera` folder into your server's `resources` directory.
2. Add `ensure crash_dslrcamera` to your `server.cfg` (after ox_lib, ox_inventory, and screenshot-basic).
3. Add the camera item to ox_inventory (e.g. `dslr_camera`) if you haven’t already.
4. Configure `config.lua` and `server/sv_config.lua` (see below).

## Configuration

### `config.lua`

| Option | Description |
|--------|-------------|
| `Config.CameraItem` | Item name in ox_inventory (default: `dslr_camera`) |
| `Config.MaxPhotosPerFolder` | Max photos per folder (default: 50) |
| `Config.CameraPropModel` | Prop model for the camera (default: `prop_cs_camera_01`) |
| `Config.UseDiscordLogs` | Use Discord webhook for photo logs |

### `server/sv_config.lua`

| Option | Description |
|--------|-------------|
| `ServerConfig.FiveManageApiKey` | **Required** for screenshot-basic / FiveManage |
| `ServerConfig.DiscordWebhook` | Discord webhook URL (optional, if `UseDiscordLogs` is true) |

## Features

- Use the camera item to enter viewfinder mode.
- Adjust FOV/zoom; take photos that are saved server-side.
- Photos can include metadata (timestamp, street name, coordinates, evidence in frame).
- Optional Discord logging when photos are taken.

## License

This project is licensed under the **PolyForm Noncommercial License 1.0.0**. You may use, modify, and distribute it for non-commercial purposes (e.g. personal servers, community use, hobby projects). Commercial use and redistribution for sale are not permitted.

Full terms: [LICENSE](LICENSE) | [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)
