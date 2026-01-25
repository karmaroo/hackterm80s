# HackTerm80s

A retro-styled 1980s computer hacking simulator game built with Godot Engine 4.3. Experience the golden age of hacking with war dialers, BBS systems, and authentic vintage computer interfaces.

## Overview

HackTerm80s puts you behind the keyboard of an 80s-era computer terminal. Scan phone numbers with your war dialer to discover hidden systems, connect to BBSes, and explore the digital underground of 1987.

## Features

### War Dialer
- Scan phone number ranges to discover computer modems
- DTMF tone generation for authentic dialing sounds
- Results logging and modem discovery tracking
- Connect to discovered systems

### BBS System
- Browse discovered BBS systems
- Registration and login system
- Message boards and file sections
- AI-powered dynamic content (optional)

### Authentic 80s Experience
- DOS-style command interface
- CRT monitor shader effects (scanlines, curvature, phosphor glow)
- Modem sounds (dial tone, ringing, handshake)
- Floppy disk system with disk swapping

### AI Integration (Optional)
- Dynamic AI-powered host systems using OpenAI API
- AI-generated BBS forum posts
- Configure via `APIKEY` command in terminal

## Tech Stack

- **Engine**: Godot 4.3
- **Language**: GDScript
- **Build System**: Docker
- **Platforms**: Linux, Windows, Web (HTML5)

## Quick Start

### Prerequisites
- Docker and Docker Compose
- X11 display server (for editor/running locally)

### Running

```bash
# Clone and enter directory
cd hackterm80s

# Launch the Godot editor
./run.sh editor

# Or run the game directly
./run.sh play

# Build for all platforms
./run.sh build
```

### Docker Commands

```bash
# Start Godot editor
docker-compose up --build godot-editor

# Build releases
docker-compose --profile build up --build godot-build

# Run game without editor
docker-compose --profile run up --build godot-run
```

## Project Structure

```
hackterm80s/
├── Dockerfile              # Godot 4.3 build container
├── docker-compose.yml      # Multi-service Docker config
├── run.sh                  # Helper script
├── game/
│   ├── project.godot       # Godot project file
│   ├── export_presets.cfg  # Export configurations
│   ├── scripts/
│   │   ├── main.gd         # Scene controller
│   │   ├── terminal.gd     # DOS terminal emulator
│   │   ├── game_state.gd   # Global state singleton
│   │   ├── session_manager.gd  # Save/load persistence
│   │   ├── settings_manager.gd # User settings
│   │   ├── ai_host.gd      # AI-powered hosts
│   │   ├── ai_forum.gd     # AI forum generation
│   │   ├── system_templates.gd # System definitions
│   │   ├── dtmf_generator.gd   # Phone tone generation
│   │   ├── hayes_modem.gd  # Modem simulation
│   │   ├── war_dialer.gd   # War dialer core
│   │   ├── floppy_organizer.gd # Disk management
│   │   └── programs/
│   │       ├── wardialer_program.gd  # War dialer UI
│   │       └── bbs_dialer.gd         # BBS client
│   ├── scenes/
│   │   ├── main.tscn       # Main game scene
│   │   └── programs/       # Program scenes
│   ├── shaders/
│   │   ├── crt.gdshader    # CRT monitor effect
│   │   └── screen_glow.gdshader # Phosphor bloom
│   └── assets/             # Audio, images, fonts (see below)
└── builds/
    └── web/
        └── Dockerfile      # Nginx for web deployment
```

## Terminal Commands

| Command | Description |
|---------|-------------|
| `DIR` | List directory contents |
| `CLS` | Clear screen |
| `TYPE <file>` | Display file contents |
| `A:` / `C:` | Switch drives |
| `DATE` | Show current date |
| `TIME` | Show current time |
| `VER` | Show DOS version |
| `MEM` | Show memory info |
| `HISTORY` | Command history |
| `SESSION` | Manage saved sessions |
| `APIKEY <key>` | Set OpenAI API key |

## Programs

Run programs by typing the executable name:

| Program | Description |
|---------|-------------|
| `WD.EXE` | War Dialer (requires floppy disk) |
| `BBS.EXE` | BBS Dialer (requires floppy disk) |

## Required Assets

Binary assets (audio, images, fonts) are not included in this repo and must be downloaded separately. See `ASSETS_NEEDED.md` for the complete list.

### Audio
- Modem sounds (dial tone, ring, handshake)
- Floppy disk sounds (insert, read, eject)
- Keyboard click sounds

### Fonts
- DOS terminal font (e.g., Perfect DOS VGA 437)
- Digital clock font (DSEG7)

### Images
- Background artwork
- Floppy disk sprites

## Configuration

### AI Features
To enable AI-powered hosts and forum content:

1. Get an OpenAI API key from https://platform.openai.com/
2. In the terminal, type: `APIKEY sk-your-key-here`
3. The key is stored locally and persists between sessions

### Sessions
Game progress is automatically saved. Use `SESSION` command to:
- `SESSION SAVE` - Manual save
- `SESSION LIST` - View all sessions
- `SESSION LOAD <id>` - Load a session
- `SESSION NEW` - Start fresh

## Development

### Running the Editor
```bash
./run.sh editor
```

### Building Releases
```bash
./run.sh build
```

Outputs:
- `builds/hackterm80s-linux` - Linux executable
- `builds/hackterm80s.exe` - Windows executable
- `builds/web/` - Web export

### Web Deployment
```bash
cd builds/web
docker build -t hackterm80s-web .
docker run -p 8080:80 hackterm80s-web
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| F5 | Toggle CRT shader |
| F11 | Toggle fullscreen |
| Ctrl+C | Interrupt program |
| Up/Down | Command history |

## Credits

- Inspired by WarGames (1983) and 80s hacker culture
- Built with Godot Engine
- Audio assets from various royalty-free sources

## License

This project is for educational and entertainment purposes. The code is provided as-is.

---

*"Would you like to play a game?"*
