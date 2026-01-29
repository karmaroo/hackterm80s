# Dynamic Asset Library System - Design Plan

## Executive Summary

Transform HackTerm80s from a static scene-based game to a dynamic, customizable environment where:
- All assets (system + cosmetic) are loaded from a library manifest
- Scenes are defined as JSON state, not .tscn files
- Users can add AI-generated assets via text descriptions
- Full scene persistence and sharing capability

---

## Current Architecture Analysis

### How It Works Today

```
main.tscn (static)
├── RoomElements/
│   ├── Desk (TextureRect)
│   ├── Monitor (TextureRect + shader)
│   ├── Phone (TextureRect + phone_bulb_light.gd)
│   ├── FloppyDrive (TextureRect + floppy_organizer.gd)
│   ├── Books1, Books2... (TextureRect - cosmetic)
│   └── Poster (TextureRect - cosmetic)
├── Terminal (Control + terminal.gd)
├── BootScreen (Control + boot_screen.gd)
└── UI overlays...
```

**Problems:**
1. Adding/removing assets requires editing .tscn
2. Can't truly delete scene elements at runtime
3. No way to add new assets without code changes
4. System assets have hardcoded node paths and signals

### System Assets (Interactive)

| Asset | Script | Signals/Behaviors |
|-------|--------|-------------------|
| Terminal | `terminal.gd` | Text I/O, command processing, CRT shader |
| Phone | `phone_bulb_light.gd` | Ring animation, DTMF input, call states |
| Floppy Drive | `floppy_organizer.gd` | Disk insert/eject, save/load |
| LED Clock | `led_clock.gd` | Real-time display |
| Lava Lamp | `lava_lamp.gd` | Ambient animation shader |
| Monitor | (shader only) | CRT effects, power state |
| Modem | `hayes_modem.gd` | AT commands, connection state |

### Cosmetic Assets (Visual Only)

Books, posters, desk accessories, background elements - purely decorative TextureRect nodes.

---

## Proposed Architecture

### 1. Asset Manifest System

A JSON manifest defines all available assets:

```json
{
  "version": "1.0",
  "assets": {
    "terminal": {
      "id": "terminal",
      "name": "CRT Terminal",
      "category": "system",
      "type": "scene",
      "scene_path": "res://scenes/assets/terminal.tscn",
      "icon": "res://assets/icons/terminal.png",
      "description": "Main computer terminal with CRT effects",
      "default_size": [800, 600],
      "anchor": "center",
      "singleton": true,
      "required": true,
      "connections": {
        "provides": ["text_output", "command_input"],
        "requires": ["modem"]
      }
    },
    "phone": {
      "id": "phone",
      "name": "Desk Phone",
      "category": "system",
      "type": "scene",
      "scene_path": "res://scenes/assets/phone.tscn",
      "icon": "res://assets/icons/phone.png",
      "description": "Rotary phone for dialing BBSes",
      "default_size": [200, 150],
      "singleton": true,
      "connections": {
        "provides": ["dtmf_output"],
        "requires": ["modem"]
      }
    },
    "books_hacking": {
      "id": "books_hacking",
      "name": "Hacking Books",
      "category": "cosmetic",
      "type": "texture",
      "texture_path": "res://assets/hack-books-787772.png",
      "icon": "res://assets/hack-books-787772.png",
      "description": "Stack of computer security books",
      "default_size": [120, 80],
      "tags": ["books", "decoration", "shelf"]
    },
    "custom_ai_001": {
      "id": "custom_ai_001",
      "name": "User Generated",
      "category": "cosmetic",
      "type": "texture",
      "texture_path": "user://generated/custom_ai_001.png",
      "source": "ai_generated",
      "prompt": "A worn 1980s programming manual with coffee stains",
      "created_at": "2024-01-15T10:30:00Z"
    }
  }
}
```

### 2. Scene State Format

Instead of .tscn, scenes are defined as JSON state:

```json
{
  "scene_id": "default_desk",
  "name": "Hacker's Desk",
  "author": "system",
  "created_at": "2024-01-01T00:00:00Z",
  "modified_at": "2024-01-15T10:30:00Z",
  "background": {
    "type": "shader",
    "shader": "res://shaders/background.gdshader",
    "params": { "color": "#1a1a2e" }
  },
  "elements": [
    {
      "asset_id": "terminal",
      "instance_id": "terminal_main",
      "position": [640, 360],
      "z_index": 10,
      "visible": true,
      "config": {
        "crt_intensity": 0.8,
        "font_size": 14
      }
    },
    {
      "asset_id": "phone",
      "instance_id": "phone_1",
      "position": [100, 400],
      "z_index": 5,
      "visible": true
    },
    {
      "asset_id": "books_hacking",
      "instance_id": "books_shelf_1",
      "position": [50, 200],
      "z_index": 2,
      "scale": [1.0, 1.0],
      "rotation": 0,
      "visible": true
    },
    {
      "asset_id": "custom_ai_001",
      "instance_id": "ai_manual_1",
      "position": [200, 250],
      "z_index": 3,
      "visible": true
    }
  ],
  "connections": [
    { "from": "terminal_main.modem_out", "to": "modem_1.command_in" },
    { "from": "phone_1.dtmf_out", "to": "modem_1.dial_in" }
  ]
}
```

### 3. Asset Categories

```
Asset Library
├── System Assets (interactive, scripted)
│   ├── Core (terminal, boot screen - required)
│   ├── Peripherals (phone, floppy, modem)
│   └── Ambient (clock, lava lamp)
├── Cosmetic Assets (visual only)
│   ├── Furniture (desk, shelves)
│   ├── Decorations (posters, plants)
│   ├── Books & Media (book stacks, tapes)
│   └── Tech Props (old computers, cables)
├── AI Generated
│   └── (user-created assets)
└── User Imported
    └── (uploaded images)
```

---

## Implementation Plan

### Phase 1: Asset Manifest & Loader

**Goal:** Load assets from manifest instead of hardcoded .tscn

**Files to create:**
- `game/scripts/asset_library.gd` - Asset manifest loader and manager
- `game/scripts/asset_loader.gd` - Dynamic asset instantiation
- `game/data/asset_manifest.json` - Asset definitions

**Changes:**
```gdscript
# asset_library.gd
class_name AssetLibrary
extends Node

var manifest: Dictionary = {}
var loaded_assets: Dictionary = {}  # id -> PackedScene or Texture

func _ready():
    _load_manifest("res://data/asset_manifest.json")
    _preload_assets()

func get_asset(id: String) -> Resource:
    if not loaded_assets.has(id):
        _load_asset(id)
    return loaded_assets.get(id)

func instantiate_asset(id: String) -> Node:
    var asset_def = manifest.assets.get(id)
    if not asset_def:
        return null

    match asset_def.type:
        "scene":
            var scene = load(asset_def.scene_path)
            return scene.instantiate()
        "texture":
            var tex_rect = TextureRect.new()
            tex_rect.texture = load(asset_def.texture_path)
            return tex_rect
    return null

func get_assets_by_category(category: String) -> Array:
    var results = []
    for id in manifest.assets:
        if manifest.assets[id].category == category:
            results.append(manifest.assets[id])
    return results
```

### Phase 2: Scene State Manager

**Goal:** Save/load scenes as JSON state

**Files to create:**
- `game/scripts/scene_state_manager.gd` - Scene serialization/deserialization
- `game/data/scenes/default_desk.json` - Default scene state

**Key functions:**
```gdscript
# scene_state_manager.gd
class_name SceneStateManager
extends Node

var current_scene_state: Dictionary = {}
var asset_library: AssetLibrary

func load_scene(scene_path: String) -> void:
    var file = FileAccess.open(scene_path, FileAccess.READ)
    current_scene_state = JSON.parse_string(file.get_as_text())
    _instantiate_scene()

func save_scene(scene_path: String) -> void:
    _serialize_current_state()
    var file = FileAccess.open(scene_path, FileAccess.WRITE)
    file.store_string(JSON.stringify(current_scene_state, "\t"))

func _instantiate_scene() -> void:
    # Clear existing elements
    for child in scene_root.get_children():
        child.queue_free()

    # Instantiate from state
    for element in current_scene_state.elements:
        var node = asset_library.instantiate_asset(element.asset_id)
        if node:
            node.name = element.instance_id
            node.position = Vector2(element.position[0], element.position[1])
            node.z_index = element.z_index
            node.visible = element.visible
            scene_root.add_child(node)
            _apply_config(node, element.get("config", {}))
```

### Phase 3: System Asset Abstraction

**Goal:** Make system assets self-contained and pluggable

**Changes:**
- Each system asset becomes its own .tscn scene
- Scripts use signals for communication (no hardcoded paths)
- Connection manager handles signal routing

```
game/scenes/assets/
├── terminal.tscn (Control + terminal.gd)
├── phone.tscn (TextureRect + phone.gd)
├── floppy_drive.tscn (TextureRect + floppy.gd)
├── led_clock.tscn (Control + led_clock.gd)
├── lava_lamp.tscn (TextureRect + lava_lamp.gd)
└── modem.tscn (Node + modem.gd - invisible)
```

**Base class for system assets:**
```gdscript
# system_asset.gd
class_name SystemAsset
extends Node

signal asset_ready
signal asset_error(message: String)

@export var asset_id: String = ""
@export var config: Dictionary = {}

func _ready():
    _initialize()
    asset_ready.emit()

func _initialize() -> void:
    # Override in subclasses
    pass

func apply_config(new_config: Dictionary) -> void:
    config.merge(new_config, true)
    _on_config_changed()

func _on_config_changed() -> void:
    # Override in subclasses
    pass

func serialize() -> Dictionary:
    return {
        "asset_id": asset_id,
        "config": config
    }
```

### Phase 4: Asset Library UI

**Goal:** Browse and place assets from library

**UI Design:**
```
┌─────────────────────────────────────────────────────────┐
│ ASSET LIBRARY                                      [X]  │
├─────────────────────────────────────────────────────────┤
│ [System] [Cosmetic] [AI Generated] [Search...]          │
├─────────────────────────────────────────────────────────┤
│ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐       │
│ │ 📺  │ │ 📞  │ │ 💾  │ │ 🕐  │ │ 🪔  │ │ 📚  │       │
│ │Term │ │Phone│ │Flop │ │Clock│ │Lamp │ │Books│       │
│ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘       │
│ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐                        │
│ │ 🖼️  │ │ 📼  │ │ 🌿  │ │ ➕  │                        │
│ │Postr│ │Tapes│ │Plant│ │ NEW │                        │
│ └─────┘ └─────┘ └─────┘ └─────┘                        │
├─────────────────────────────────────────────────────────┤
│ Selected: Hacking Books                                 │
│ Category: Cosmetic > Books                              │
│ Size: 120x80                                            │
│                                              [+ Place]  │
└─────────────────────────────────────────────────────────┘
```

### Phase 5: AI Asset Generation

**Goal:** Generate custom assets via text description

**Integration with Google Imagen/Gemini:**

```gdscript
# ai_asset_generator.gd
class_name AIAssetGenerator
extends Node

signal generation_started(prompt: String)
signal generation_complete(asset_id: String, texture: Texture2D)
signal generation_failed(error: String)

const API_ENDPOINT = "https://generativelanguage.googleapis.com/v1/models/imagen-3.0-generate-002:predict"

var http_request: HTTPRequest

func generate_asset(prompt: String, style_hints: Dictionary = {}) -> void:
    var structured_prompt = _build_structured_prompt(prompt, style_hints)

    var request_body = {
        "instances": [{"prompt": structured_prompt}],
        "parameters": {
            "sampleCount": 1,
            "aspectRatio": style_hints.get("aspect_ratio", "1:1"),
            "safetyFilterLevel": "block_medium_and_above",
            "personGeneration": "dont_allow"
        }
    }

    generation_started.emit(prompt)

    var headers = [
        "Content-Type: application/json",
        "Authorization: Bearer " + _get_api_key()
    ]

    http_request.request(
        API_ENDPOINT,
        headers,
        HTTPClient.METHOD_POST,
        JSON.stringify(request_body)
    )

func _build_structured_prompt(user_prompt: String, hints: Dictionary) -> String:
    var base_style = """
    1980s retro computing aesthetic, pixel art style compatible,
    vintage computer equipment, muted CRT colors,
    subtle scanlines texture, nostalgic tech vibes,
    isolated object on transparent or solid dark background,
    suitable for a retro hacker game scene
    """

    var object_type = hints.get("type", "desk accessory")

    return """
    Create a {object_type}: {user_prompt}

    Style requirements:
    {base_style}

    Output: Single object, game asset ready, no text overlays
    """.format({
        "object_type": object_type,
        "user_prompt": user_prompt,
        "base_style": base_style
    })

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
    if response_code != 200:
        generation_failed.emit("API error: " + str(response_code))
        return

    var response = JSON.parse_string(body.get_string_from_utf8())
    var image_data = Marshalls.base64_to_raw(response.predictions[0].bytesBase64Encoded)

    var image = Image.new()
    image.load_png_from_buffer(image_data)

    var texture = ImageTexture.create_from_image(image)
    var asset_id = _save_generated_asset(texture)

    generation_complete.emit(asset_id, texture)

func _save_generated_asset(texture: Texture2D) -> String:
    var asset_id = "ai_" + str(Time.get_unix_time_from_system())
    var path = "user://generated/" + asset_id + ".png"

    DirAccess.make_dir_recursive_absolute("user://generated")
    texture.get_image().save_png(path)

    # Add to manifest
    AssetLibrary.add_custom_asset({
        "id": asset_id,
        "name": "AI Generated",
        "category": "cosmetic",
        "type": "texture",
        "texture_path": path,
        "source": "ai_generated"
    })

    return asset_id
```

**AI Generation UI:**
```
┌─────────────────────────────────────────────────────────┐
│ 🤖 AI ASSET GENERATOR                              [X]  │
├─────────────────────────────────────────────────────────┤
│ Describe what you want to create:                       │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ A worn 1980s programming manual with coffee stains  │ │
│ │ and dog-eared pages, titled "BASIC for Beginners"   │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Asset Type: [Book/Manual ▼]                             │
│ Style:      [Photorealistic ▼]  [Pixel Art]  [Painted] │
│ Size:       [Small ▼]  Medium  Large                    │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │                                                     │ │
│ │              [Preview appears here]                 │ │
│ │                                                     │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Estimated cost: ~$0.02                                  │
│                                                         │
│              [Cancel]  [🎨 Generate]  [✓ Use Asset]    │
└─────────────────────────────────────────────────────────┘
```

---

## Data Flow

```
                    ┌──────────────────┐
                    │  Asset Manifest  │
                    │  (JSON config)   │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌────────────┐ ┌────────────┐ ┌────────────┐
       │  Built-in  │ │ AI-Gen'd   │ │   User     │
       │  Assets    │ │  Assets    │ │  Uploaded  │
       │ (res://)   │ │ (user://)  │ │ (user://)  │
       └─────┬──────┘ └─────┬──────┘ └─────┬──────┘
             │              │              │
             └──────────────┼──────────────┘
                            ▼
                    ┌──────────────────┐
                    │  Asset Library   │
                    │    (runtime)     │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌────────────┐ ┌────────────┐ ┌────────────┐
       │   Scene    │ │   Edit     │ │   Asset    │
       │   State    │ │   Mode     │ │  Library   │
       │  Manager   │ │  Manager   │ │    UI      │
       └─────┬──────┘ └─────┬──────┘ └─────┬──────┘
             │              │              │
             └──────────────┼──────────────┘
                            ▼
                    ┌──────────────────┐
                    │   Scene Root     │
                    │  (instantiated)  │
                    └──────────────────┘
```

---

## Server-Side Considerations

### Asset Storage API

```javascript
// server/routes/assets.js

// Upload custom asset
POST /api/assets/upload
  - Accepts PNG/JPG
  - Returns asset_id
  - Stores in /uploads/assets/{user_id}/{asset_id}.png

// Get user's custom assets
GET /api/assets/custom
  - Returns manifest of user's uploaded/generated assets

// Share asset (make public)
POST /api/assets/{asset_id}/share
  - Adds to public asset gallery

// Browse public assets
GET /api/assets/gallery?category=&tags=&page=

// AI Generation proxy (hides API key)
POST /api/assets/generate
  - Takes prompt, forwards to Google API
  - Stores result, returns asset_id
```

### Scene Storage API

```javascript
// Save user's scene
POST /api/scenes
  - Accepts scene JSON state
  - Returns scene_id

// Load scene
GET /api/scenes/{scene_id}

// List user's scenes
GET /api/scenes

// Share scene
POST /api/scenes/{scene_id}/share

// Browse shared scenes
GET /api/scenes/gallery
```

---

## Migration Strategy

### Step 1: Create asset scenes (non-breaking)
Extract each system asset into its own .tscn file while keeping main.tscn working.

### Step 2: Create manifest for existing assets
Document all current assets in JSON manifest format.

### Step 3: Build AssetLibrary loader
New code path that can load from manifest, tested alongside existing.

### Step 4: Build SceneStateManager
Can serialize current scene to JSON, load scene from JSON.

### Step 5: Convert main.tscn to scene state
Generate default_desk.json from existing layout.

### Step 6: Switch to dynamic loading
main.tscn becomes minimal bootstrap, loads scene state dynamically.

### Step 7: Add Asset Library UI
Users can now browse and place assets.

### Step 8: Add AI generation
Integrate image generation API.

---

## Technical Considerations

### Performance
- Lazy-load assets (don't preload entire library)
- Cache frequently used assets
- Limit simultaneous AI generation requests
- Compress stored images

### Security
- Validate uploaded images (size, format, no scripts)
- Rate limit AI generation
- Sanitize user prompts before sending to AI
- Don't expose API keys to client

### Persistence
- Scene state saved to server via WebSocket
- Fallback to localStorage for offline
- Auto-save with debouncing
- Version history for scenes

### Compatibility
- Keep default scene working for new users
- Import/export scene files
- Asset pack bundles for sharing

---

## File Structure After Implementation

```
game/
├── scripts/
│   ├── asset_library.gd        # Asset manifest manager
│   ├── asset_loader.gd         # Dynamic instantiation
│   ├── scene_state_manager.gd  # Scene serialization
│   ├── ai_asset_generator.gd   # AI image generation
│   ├── assets/                 # System asset scripts
│   │   ├── system_asset.gd     # Base class
│   │   ├── terminal_asset.gd
│   │   ├── phone_asset.gd
│   │   └── ...
│   └── ui/
│       ├── asset_library_ui.gd
│       └── ai_generator_ui.gd
├── scenes/
│   ├── main.tscn               # Bootstrap only
│   ├── assets/                 # Packaged system assets
│   │   ├── terminal.tscn
│   │   ├── phone.tscn
│   │   └── ...
│   └── ui/
│       ├── asset_library.tscn
│       └── ai_generator.tscn
├── data/
│   ├── asset_manifest.json     # All asset definitions
│   └── scenes/
│       ├── default_desk.json   # Default scene state
│       └── ...
└── assets/                     # Textures, audio, etc.

server/
├── routes/
│   ├── assets.js               # Asset storage API
│   ├── scenes.js               # Scene storage API
│   └── ai.js                   # AI generation proxy
└── uploads/
    ├── assets/                 # User uploaded assets
    └── scenes/                 # Saved scene states
```

---

## Questions to Resolve

1. **Singleton assets**: Should terminal/phone be single-instance only, or allow multiples?

2. **Asset dependencies**: If phone requires modem, auto-add modem when placing phone?

3. **Scene sharing**: Public gallery? Friends-only? How to handle moderation?

4. **AI generation costs**: Per-user limits? Credits system? Pay-per-generate?

5. **Offline support**: How much functionality without server connection?

6. **Asset versioning**: What happens when we update a built-in asset?

---

## Recommended Implementation Order

| Phase | Effort | Description |
|-------|--------|-------------|
| 1 | Medium | Asset manifest + loader (foundation) |
| 2 | Medium | Scene state manager (save/load) |
| 3 | High | System asset abstraction (refactor) |
| 4 | Medium | Asset library UI (browse/place) |
| 5 | Medium | AI generation integration |
| 6 | Low | Server APIs for storage |
| 7 | Low | Scene sharing/gallery |

**Total estimated effort**: Significant refactor, but enables major new capabilities.

---

## Benefits

✅ **True asset deletion** - Remove anything, it's just JSON state
✅ **Custom scenes** - Users can create unique setups
✅ **AI creativity** - Generate any decorative asset imaginable
✅ **Shareable** - Export/import scenes and assets
✅ **Extensible** - Easy to add new asset types
✅ **Testable** - Scene state is just data, easy to test
✅ **Versionable** - Git-friendly JSON configs
