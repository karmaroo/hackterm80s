extends Node
class_name FloppyOrganizer
## Manages floppy disk inventory and selection

signal disk_selected(disk_id: String)
signal disk_ejected()

# Currently inserted disk
var inserted_disk: String = ""

# Disk definitions
const DISKS = {
	"wardialer": {
		"label": "WARDIALER V1.0",
		"color": "blue",
		"files": {
			"WD.EXE": {"type": "exe", "program": "wardialer"}
		}
	},
	"wardialer_v2": {
		"label": "WARDIALER V2.0",
		"color": "red",
		"files": {
			"WD.EXE": {"type": "exe", "program": "wardialer"},
			"README.TXT": {"type": "file", "content": "War Dialer v2.0\nNew features: AI host support\n"}
		}
	},
	"bbsdialer": {
		"label": "BBS DIALER",
		"color": "green",
		"files": {
			"BBS.EXE": {"type": "exe", "program": "bbsdialer"}
		}
	}
}


func _ready() -> void:
	# Give player starting disk
	if not GameState.has_disk("wardialer"):
		GameState.add_disk_to_inventory("wardialer")


## Insert a disk into the drive
func insert_disk(disk_id: String) -> bool:
	if not DISKS.has(disk_id):
		return false
	
	if not GameState.has_disk(disk_id):
		return false
	
	inserted_disk = disk_id
	var disk_data = DISKS[disk_id]
	
	# Mount in terminal's virtual filesystem
	var terminal = get_tree().get_first_node_in_group("terminal")
	if terminal and terminal.has_method("mount_floppy"):
		terminal.mount_floppy(disk_data.files, disk_data.label)
	
	# Play sound
	GameState.floppy_reading.emit()
	
	disk_selected.emit(disk_id)
	return true


## Eject current disk
func eject_disk() -> void:
	if inserted_disk.is_empty():
		return
	
	inserted_disk = ""
	
	var terminal = get_tree().get_first_node_in_group("terminal")
	if terminal and terminal.has_method("eject_floppy"):
		terminal.eject_floppy()
	
	disk_ejected.emit()


## Get disk info
func get_disk_info(disk_id: String) -> Dictionary:
	return DISKS.get(disk_id, {})


## List available disks in player inventory
func get_available_disks() -> Array:
	var available: Array = []
	for disk_id in GameState.owned_disks:
		if DISKS.has(disk_id):
			available.append({
				"id": disk_id,
				"label": DISKS[disk_id].label,
				"color": DISKS[disk_id].color
			})
	return available
