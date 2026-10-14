class_name UpgradeDef
extends Resource
## Generic stat upgrade offered on level-up.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var stat: String = ""
@export var op: String = "add"     ## add | mul
@export var value: float = 0.0
@export var max_level: int = 5
@export var color: Color = Color.WHITE
## Card/HUD art, res:// path. Empty = silhouette_upgrade fallback.
@export var icon: String = ""
