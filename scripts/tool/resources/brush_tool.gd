class_name BrushTool
extends Resource

enum BrushBufferName {
	ROLLBACK,
	COMMIT,
	CURSOR_INFO,
	CANVAS_INFO,
	BRUSH_INFO,
	INTERNAL,
	CUSTOM1,
	CUSTOM2,
	CUSTOM3,
	CUSTOM4,
	CUSTOM5,
	CUSTOM6,
	CUSTOM7,
	CUSTOM8,
	CUSTOM9,
	CUSTOM10,
	CUSTOM11,
	CUSTOM12
}

const BUFFER_NAMES : Dictionary[BrushBufferName, String] = {
	BrushBufferName.ROLLBACK : "ROLLBACK",
	BrushBufferName.COMMIT : "COMMIT",
	BrushBufferName.CURSOR_INFO : "CURSOR_INFO",
	BrushBufferName.CANVAS_INFO : "CANVAS_INFO",
	BrushBufferName.BRUSH_INFO : "BRUSH_INFO",
	BrushBufferName.INTERNAL : "INTERNAL",
	BrushBufferName.CUSTOM1 : "CUSTOM1",
	BrushBufferName.CUSTOM2 : "CUSTOM2",
	BrushBufferName.CUSTOM3 : "CUSTOM3",
	BrushBufferName.CUSTOM4 : "CUSTOM4",
	BrushBufferName.CUSTOM5 : "CUSTOM5",
	BrushBufferName.CUSTOM6 : "CUSTOM6",
	BrushBufferName.CUSTOM7 : "CUSTOM7",
	BrushBufferName.CUSTOM8 : "CUSTOM8",
	BrushBufferName.CUSTOM9 : "CUSTOM9",
	BrushBufferName.CUSTOM10 : "CUSTOM10",
	BrushBufferName.CUSTOM11 : "CUSTOM11",
	BrushBufferName.CUSTOM12 : "CUSTOM12"
}

@export var name : String

@export var icon : Texture

@export var parameters : Array[BrushParameter]

@export var buffers : Dictionary[BrushBufferName, int]

@export var stages : Array[BrushStage]
