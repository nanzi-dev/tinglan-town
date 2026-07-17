class_name ResidentPortraitAtlas
extends RefCounted

const PORTRAIT_SHEET := preload(
	"res://assets/characters/resident_portraits.png",
)
const CELL_SIZE := Vector2(400, 400)
const COLUMNS := 5
const RESIDENT_INDEX := {
	"shen-yan": 0,
	"lin-xi": 1,
	"zhou-he": 2,
	"lu-qiao": 3,
	"su-wan": 4,
	"gu-yun": 5,
	"tang-yu": 6,
	"qiao-zhen": 7,
	"he-miao": 8,
	"xu-deng": 9,
}


func portrait_for(character_id: String) -> AtlasTexture:
	if not RESIDENT_INDEX.has(character_id):
		return null
	var index := int(RESIDENT_INDEX[character_id])
	var portrait := AtlasTexture.new()
	portrait.atlas = PORTRAIT_SHEET
	@warning_ignore("integer_division")
	var row := index / COLUMNS
	var column := index % COLUMNS
	portrait.region = Rect2(
		column * CELL_SIZE.x,
		row * CELL_SIZE.y,
		CELL_SIZE.x,
		CELL_SIZE.y,
	)
	return portrait
