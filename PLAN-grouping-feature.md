# Grouping Feature Implementation Plan

## Overview

Add the ability to select multiple items, right-click to group them into a new parent node, and ungroup them later. Groups persist across sessions via server sync.

## Current State

- **Multi-select**: Partially implemented via Shift+Click (stored in `multi_selected` array)
  - **BUG**: Outlines show but dragging only moves the primary `selected_element`
  - **BUG**: Tree/list items don't show multi-select highlighting
- **Context menu**: Exists at lines 1870-1912 with items like Duplicate, Hide, Delete, z-order controls
- **Path hierarchy**: Items have paths like "RoomElements/Binder1/ColorRect"
- **Server persistence**: Config has `elements`, `copies`, `hidden`, `locked`, `custom_names`

---

## Phase 0: Fix Multi-Select (PREREQUISITE)

### Problem 1: Dragging only moves single element

**Location:** `_handle_drag()` (~line 4376)

The current code only moves `selected_element`. Need to move all `multi_selected` elements together.

**Fix:**

```gdscript
func _handle_drag(mouse_pos: Vector2) -> void:
    if not selected_element:
        return

    var screen_delta = mouse_pos - drag_start_mouse
    var zoom_scale = zoom_container.scale if zoom_container else Vector2.ONE
    var scene_delta = screen_delta / zoom_scale

    if is_resizing:
        _handle_resize(scene_delta)
    elif is_dragging:
        # Move all multi-selected elements (or just the single selected)
        var elements_to_move = _get_elements_to_move()

        for i in range(elements_to_move.size()):
            var element = elements_to_move[i]
            var start_offsets = multi_drag_start_offsets[i] if multi_drag_start_offsets.size() > i else drag_start_offsets

            var start_pos: Vector2
            if start_offsets.get("is_control", true):
                start_pos = Vector2(start_offsets.get("left", 0), start_offsets.get("top", 0))
            else:
                start_pos = start_offsets.get("position", Vector2.ZERO)

            var new_pos = start_pos + scene_delta

            # Apply snapping only for primary element
            if element == selected_element and snap_enabled and element is Control:
                var snap_result = _calculate_snap(new_pos.x, new_pos.y)
                new_pos.x = snap_result["x"]
                new_pos.y = snap_result["y"]
                _draw_smart_guides(snap_result["guides"])
                scene_delta = new_pos - start_pos  # Update delta for other elements

            _apply_drag_delta(element, start_offsets, new_pos - start_pos)

        if not snap_enabled:
            _clear_smart_guides()
```

**Additional changes needed:**

1. Add `var multi_drag_start_offsets: Array[Dictionary] = []` to track starting positions
2. In `_handle_mouse_down()`, populate `multi_drag_start_offsets` for all multi-selected elements
3. Add helper `_get_elements_to_move()` that returns `multi_selected` if populated, else `[selected_element]`

### Problem 2: Tree items don't highlight multi-selected

**Location:** `_render_tree_node()` (~line 1795)

Current code:
```gdscript
var is_selected = item and selected_element == item["element"]
```

**Fix:**
```gdscript
var is_selected = item and (selected_element == item["element"] or item["element"] in multi_selected)
```

Also update the background color logic to use a slightly different color for multi-selected (not primary):
```gdscript
var is_multi_selected = item and item["element"] in multi_selected and item["element"] != selected_element

var bg_color = Color(0.05, 0.05, 0.08)
if is_selected:
    bg_color = Color(0.0, 0.3, 0.15)  # Primary selection - bright green
elif is_multi_selected:
    bg_color = Color(0.0, 0.2, 0.25)  # Multi-select - cyan tint
elif not item:
    bg_color = Color(0.04, 0.04, 0.06)
elif is_hidden:
    bg_color = Color(0.03, 0.03, 0.05)
```

### Problem 3: Need to refresh tree when multi-selection changes

In `_add_to_multi_selection()` and `_remove_from_multi_selection()`, add tree refresh:
```gdscript
_populate_scene_tree()  # Refresh to show multi-select highlighting
```

---

## Requirements

### Group Feature
1. Select 2+ items via Shift+Click
2. Right-click shows "Group" option
3. Creates a new Control node as parent
4. Moves selected items to be children of new group
5. Updates all paths to reflect new hierarchy
6. Scrolls tree to new group, auto-expands it
7. Group is immediately renameable (shows in Properties panel)

### Ungroup Feature
1. Select a group node (parent with children)
2. Right-click shows "Ungroup" option
3. Moves children back to group's parent
4. Deletes the group node
5. Updates all paths to reflect flattened hierarchy

### Persistence
1. Groups saved in config (no special handling needed - they're just nodes)
2. Group node positions, custom names persist
3. Children paths update automatically

---

## Implementation Plan

### Phase 1: Group Creation

**File:** `game/scripts/edit_mode_manager.gd`

#### 1.1 Add context menu items for Group/Ungroup

Location: `_create_context_menus()` (~line 1870)

```gdscript
# After "Redo Move" item (id 9)
context_menu.add_separator()
context_menu.add_item("Group Selection", 10)   # Only enabled when multi_selected.size() >= 2
context_menu.add_item("Ungroup", 11)           # Only enabled when selected is a group
```

#### 1.2 Update context menu visibility in `_show_context_menu()`

Location: `_show_context_menu()` (~line 1915)

```gdscript
# Show/hide Group option based on multi-selection
var can_group = multi_selected.size() >= 2
context_menu.set_item_disabled(10, not can_group)

# Show/hide Ungroup option based on whether selected item is a group
var can_ungroup = _is_group_node(selected_item)
context_menu.set_item_disabled(11, not can_ungroup)
```

#### 1.3 Add `_is_group_node()` helper function

```gdscript
func _is_group_node(item: Dictionary) -> bool:
    """Check if an item is a group (has children that are also in editable_elements)"""
    if item.is_empty():
        return false
    var path = item.get("path", "")
    if path.is_empty():
        return false

    # Check if any other item's path starts with this path + "/"
    for other in editable_elements:
        var other_path = other.get("path", "")
        if other_path.begins_with(path + "/"):
            return true
    return false
```

#### 1.4 Implement `_group_selection()` function

```gdscript
func _group_selection() -> void:
    """Group the currently multi-selected elements into a new parent node"""
    if multi_selected.size() < 2:
        return

    # 1. Find common parent path for all selected items
    var items_to_group: Array[Dictionary] = []
    for element in multi_selected:
        var item = _get_item_for_element(element)
        if not item.is_empty():
            items_to_group.append(item)

    if items_to_group.size() < 2:
        return

    # Find the common parent path
    var common_parent = _find_common_parent_path(items_to_group)

    # 2. Generate unique group name
    var group_name = _generate_unique_group_name(common_parent)
    var group_path = (common_parent + "/" + group_name) if common_parent else group_name

    # 3. Create the group Control node
    var group_node = Control.new()
    group_node.name = group_name
    group_node.mouse_filter = Control.MOUSE_FILTER_IGNORE

    # 4. Find the scene parent and add group node
    var first_element = items_to_group[0]["element"]
    var scene_parent = first_element.get_parent()
    scene_parent.add_child(group_node)

    # 5. Calculate bounding box of all selected items for group position
    var bounds = _calculate_bounds(items_to_group)
    group_node.position = bounds.position
    group_node.size = bounds.size

    # 6. Reparent all selected items to the group
    for item in items_to_group:
        var element = item["element"]
        var old_path = item["path"]

        # Calculate new local position relative to group
        var global_pos = element.global_position
        element.get_parent().remove_child(element)
        group_node.add_child(element)
        element.position = global_pos - group_node.global_position

        # Update path in editable_elements
        var new_path = group_path + "/" + element.name
        item["path"] = new_path

        # Update tracking dictionaries
        _update_path_in_tracking(old_path, new_path)

    # 7. Register the group in editable_elements
    var group_item = {
        "element": group_node,
        "type": ItemType.OBJECT,
        "path": group_path,
        "category": "Groups",
        "is_group": true,
        "is_copy": false,
    }
    editable_elements.append(group_item)

    # 8. Push undo action
    _push_undo_action({
        "type": "group",
        "group_path": group_path,
        "child_paths": items_to_group.map(func(i): return i["path"]),
        "original_paths": items_to_group.map(func(i): return i.get("original_path", i["path"])),
    })

    # 9. Clear multi-selection and select the group
    _clear_multi_selection()
    _select_element(group_node)

    # 10. Update UI
    _populate_scene_tree()
    _expand_to_path(group_path)
    _scroll_to_selected_in_tree(group_path)
    _update_selection_outline()
    _update_properties_panel()
    _mark_scene_dirty()

    print("[EditMode] Created group: %s with %d children" % [group_path, items_to_group.size()])
```

#### 1.5 Helper functions for grouping

```gdscript
func _find_common_parent_path(items: Array[Dictionary]) -> String:
    """Find the common parent path for a set of items"""
    if items.is_empty():
        return ""

    var paths: Array[String] = []
    for item in items:
        var path = item.get("path", "")
        var last_slash = path.rfind("/")
        if last_slash >= 0:
            paths.append(path.substr(0, last_slash))
        else:
            paths.append("")  # Top-level item

    # Find common prefix
    if paths.is_empty():
        return ""

    var common = paths[0]
    for p in paths:
        while not p.begins_with(common) and common.length() > 0:
            var last_slash = common.rfind("/")
            if last_slash >= 0:
                common = common.substr(0, last_slash)
            else:
                common = ""

    return common


func _generate_unique_group_name(parent_path: String) -> String:
    """Generate a unique group name like Group1, Group2, etc."""
    var base_name = "Group"
    var counter = 1
    var test_path = (parent_path + "/" + base_name + str(counter)) if parent_path else (base_name + str(counter))

    while _path_exists(test_path):
        counter += 1
        test_path = (parent_path + "/" + base_name + str(counter)) if parent_path else (base_name + str(counter))

    return base_name + str(counter)


func _calculate_bounds(items: Array[Dictionary]) -> Rect2:
    """Calculate the bounding box of all items"""
    if items.is_empty():
        return Rect2()

    var min_pos = Vector2(INF, INF)
    var max_pos = Vector2(-INF, -INF)

    for item in items:
        var element = item["element"]
        if element is Control:
            var rect = Rect2(element.global_position, element.size)
            min_pos.x = min(min_pos.x, rect.position.x)
            min_pos.y = min(min_pos.y, rect.position.y)
            max_pos.x = max(max_pos.x, rect.position.x + rect.size.x)
            max_pos.y = max(max_pos.y, rect.position.y + rect.size.y)

    return Rect2(min_pos, max_pos - min_pos)


func _update_path_in_tracking(old_path: String, new_path: String) -> void:
    """Update all tracking dictionaries when a path changes"""
    # Update original_positions
    if original_positions.has(old_path):
        original_positions[new_path] = original_positions[old_path]
        original_positions.erase(old_path)

    # Update modified_elements
    if modified_elements.has(old_path):
        modified_elements[new_path] = modified_elements[old_path]
        modified_elements.erase(old_path)

    # Update custom_names
    if custom_names.has(old_path):
        custom_names[new_path] = custom_names[old_path]
        custom_names.erase(old_path)

    # Update hidden_elements
    if hidden_elements.has(old_path):
        hidden_elements[new_path] = hidden_elements[old_path]
        hidden_elements.erase(old_path)

    # Update locked_elements
    if locked_elements.has(old_path):
        locked_elements[new_path] = locked_elements[old_path]
        locked_elements.erase(old_path)
```

---

### Phase 2: Ungroup Implementation

#### 2.1 Implement `_ungroup_selection()` function

```gdscript
func _ungroup_selection() -> void:
    """Ungroup the currently selected group node"""
    if not selected_item or selected_item.is_empty():
        return

    if not _is_group_node(selected_item):
        return

    var group_path = selected_item.get("path", "")
    var group_element = selected_item.get("element")

    if not group_element:
        return

    # 1. Find the group's parent path
    var last_slash = group_path.rfind("/")
    var parent_path = group_path.substr(0, last_slash) if last_slash >= 0 else ""

    # 2. Get scene parent
    var scene_parent = group_element.get_parent()

    # 3. Find all children of this group
    var children_to_ungroup: Array[Dictionary] = []
    for item in editable_elements:
        var item_path = item.get("path", "")
        if item_path.begins_with(group_path + "/"):
            # Check it's a direct child (not nested deeper)
            var relative_path = item_path.substr(group_path.length() + 1)
            if "/" not in relative_path:
                children_to_ungroup.append(item)

    # 4. Reparent children to group's parent
    for item in children_to_ungroup:
        var element = item["element"]
        var old_path = item["path"]

        # Calculate global position before reparenting
        var global_pos = element.global_position

        # Reparent
        group_element.remove_child(element)
        scene_parent.add_child(element)
        element.global_position = global_pos

        # Update path
        var new_path = (parent_path + "/" + element.name) if parent_path else element.name
        item["path"] = new_path

        # Update tracking
        _update_path_in_tracking(old_path, new_path)

    # 5. Remove group from editable_elements
    for i in range(editable_elements.size() - 1, -1, -1):
        if editable_elements[i].get("path", "") == group_path:
            editable_elements.remove_at(i)
            break

    # 6. Delete the group node
    group_element.queue_free()

    # 7. Clean up tracking for group
    original_positions.erase(group_path)
    modified_elements.erase(group_path)
    custom_names.erase(group_path)
    hidden_elements.erase(group_path)
    locked_elements.erase(group_path)

    # 8. Push undo action
    _push_undo_action({
        "type": "ungroup",
        "group_path": group_path,
        "child_paths": children_to_ungroup.map(func(i): return i["path"]),
    })

    # 9. Clear selection
    _clear_selection()

    # 10. Update UI
    _populate_scene_tree()
    _update_type_highlights()
    _update_item_labels()
    _mark_scene_dirty()

    print("[EditMode] Ungrouped: %s (%d children)" % [group_path, children_to_ungroup.size()])
```

---

### Phase 3: Context Menu Integration

#### 3.1 Update `_on_context_menu_item()` handler

Location: `_on_context_menu_item()` (~line 1943)

```gdscript
# Add cases for new menu items
10:  # Group Selection
    _group_selection()
11:  # Ungroup
    _ungroup_selection()
```

---

### Phase 4: Server Persistence

Groups are just Control nodes with children, so they persist naturally through the existing config system. However, we need to ensure:

#### 4.1 Groups are saved with `is_group` flag

In `get_scene_config()` and `_send_scene_update_ws()`, add the `is_group` flag to element data:

```gdscript
element_data["is_group"] = item.get("is_group", false)
```

#### 4.2 Groups are recreated on config load

In `apply_scene_config()`, when processing elements that have `is_group: true`, create them as Control nodes:

```gdscript
# In the elements processing loop
if element_data.get("is_group", false) and not element:
    # Recreate the group node
    var group_node = Control.new()
    group_node.name = path.get_file()
    # ... position, size from config
    # Add to parent
```

---

### Phase 5: Undo/Redo Support

#### 5.1 Add undo handlers for group/ungroup

In `_apply_undo_action()`:

```gdscript
"group":
    # Undo group = ungroup
    _undo_group(action)

"ungroup":
    # Undo ungroup = recreate group
    _undo_ungroup(action)
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `game/scripts/edit_mode_manager.gd` | All grouping logic |

## Implementation Order

| Priority | Task | Complexity |
|----------|------|------------|
| **Phase 0: Fix Multi-Select** | | |
| 0.1 | Add `multi_drag_start_offsets` variable | Low |
| 0.2 | Update `_handle_mouse_down()` to store multi-drag offsets | Medium |
| 0.3 | Update `_handle_drag()` to move all multi-selected | Medium |
| 0.4 | Update `_render_tree_node()` for multi-select highlighting | Low |
| 0.5 | Add tree refresh in multi-select functions | Low |
| **Phase 1-5: Grouping** | | |
| 1 | Add `_is_group_node()` helper | Low |
| 2 | Add context menu items (Group/Ungroup) | Low |
| 3 | Update `_show_context_menu()` for enable/disable | Low |
| 4 | Implement `_group_selection()` | High |
| 5 | Implement helper functions | Medium |
| 6 | Implement `_ungroup_selection()` | Medium |
| 7 | Wire up context menu handlers | Low |
| 8 | Add undo/redo support | Medium |
| 9 | Update save/load for group persistence | Medium |
| 10 | Test and debug | Medium |

## Testing Checklist

### Phase 0: Multi-Select Fixes
1. [ ] Multi-select 2+ items with Shift+Click
2. [ ] All multi-selected items show dashed outline
3. [ ] All multi-selected items highlighted in tree (cyan tint)
4. [ ] Primary selected item highlighted brighter (green)
5. [ ] Dragging moves ALL multi-selected items together
6. [ ] Items maintain relative positions during drag
7. [ ] Snapping works on primary element, others follow

### Phases 1-5: Grouping
8. [ ] Right-click with multi-select shows "Group Selection" (enabled)
9. [ ] Click "Group Selection" creates group node
10. [ ] Group appears in tree with children nested
11. [ ] Tree scrolls to and expands the new group
12. [ ] Group is selected and shows in Properties panel
13. [ ] Can rename group via Properties panel
14. [ ] Select group and right-click shows "Ungroup"
15. [ ] Click "Ungroup" moves children back, deletes group
16. [ ] Children positions preserved after ungroup
17. [ ] Undo group -> ungroups
18. [ ] Undo ungroup -> recreates group
19. [ ] Save/reload preserves groups
20. [ ] WebSocket sync preserves groups across sessions

## Edge Cases to Handle

- Grouping items from different parent paths
- Grouping items that are already in a group (nested groups)
- Ungrouping nested groups
- Grouping copies vs originals
- Group containing hidden items
- Group containing locked items
