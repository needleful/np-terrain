@tool
class_name NPHeightmapRenderer
extends Node3D

# For my heightmap, I'm using up to 5 mipmaps, plus the original texture
@export var materials: Array[Material]
