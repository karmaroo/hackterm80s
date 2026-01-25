extends Node
## Boot screen controller - handles startup sequence

signal boot_complete()

var terminal: Node


func run_boot_sequence() -> void:
	if not terminal:
		boot_complete.emit()
		return
	
	# BIOS-style boot
	terminal.print_line("SHADOW BIOS v1.0")
	terminal.print_line("(C) 1987 Shadow Systems Inc.")
	terminal.print_line("")
	
	await get_tree().create_timer(0.3).timeout
	
	terminal.print_line("Memory Test: 640K OK")
	await get_tree().create_timer(0.2).timeout
	
	terminal.print_line("Extended Memory: 384K")
	await get_tree().create_timer(0.2).timeout
	
	terminal.print_line("")
	terminal.print_line("Detecting drives...")
	terminal.print_line("  C: - 20MB Hard Disk")
	terminal.print_line("  A: - 3.5\" Floppy")
	
	await get_tree().create_timer(0.5).timeout
	
	terminal.print_line("")
	terminal.print_line("Loading SHADOW-DOS...")
	
	await get_tree().create_timer(0.3).timeout
	
	boot_complete.emit()
