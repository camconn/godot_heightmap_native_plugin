tool
extends Control


signal property_changed(key, value)

# Used for most simple types
class Editor:
	var control = null
	var getter = null
	var setter = null


# Used when the control cannot hold the actual value
class ResourceEditor extends Editor:
	var value = null
	var label = null
	
	func get_value():
		return value
	
	func set_value(v):
		value = v
		label.text = "null" if v == null else v.resource_path


var _prototype = null
var _edit_signal = true
var _editors = {}

# Had to separate the container because otherwise I can't open dialogs properly...
onready var _grid_container = get_node("GridContainer")
onready var _open_file_dialog = get_node("OpenFileDialog")


# Test
#func _ready():
#	set_prototype({
#		"seed": { "type": TYPE_INT, "randomizable": true },
#		"base_height": { "type": TYPE_REAL, "range": {"min": -1000.0, "max": 1000.0, "step": 0.1}},
#		"height_range": { "type": TYPE_REAL, "range": {"min": -1000.0, "max": 1000.0, "step": 0.1 }, "default_value": 500.0},
#		"streamed": { "type": TYPE_BOOL },
#		"texture": { "type": TYPE_OBJECT, "object_type": Resource }
#	})


func clear_prototype():
	_editors.clear()
	var i = _grid_container.get_child_count() - 1
	while i >= 0:
		var child = _grid_container.get_child(i)
		_grid_container.remove_child(child)
		child.call_deferred("free")
		i -= 1
	_prototype = null


func get_value(key):
	var editor = _editors[key]
	return editor.getter.call_func()


func get_values():
	var values = {}
	for key in _editors:
		var editor = _editors[key]
		values[key] = editor.getter.call_func()
	return values


func set_value(key, value):
	var editor = _editors[key]
	editor.setter.call_func(value)


func set_values(values):
	for key in values:
		if _editors.has(key):
			var editor = _editors[key]
			var v = values[key]
			editor.setter.call_func(v)


func set_prototype(proto):
	clear_prototype()
	
	for key in proto:
		var prop = proto[key]
		
		var label = Label.new()
		label.text = str(key).capitalize()
		_grid_container.add_child(label)
		
		var editor = _make_editor(key, prop)
		
		if prop.has("default_value"):
			editor.setter.call_func(prop.default_value)
		
		_editors[key] = editor
		_grid_container.add_child(editor.control)
	
	_prototype = proto


func trigger_all_modified():
	for key in _prototype:
		var value = _editors[key].getter.call_func()
		emit_signal("property_changed", key, value)


func _make_editor(key, prop):
	var ed = null
	
	var editor = null
	var getter = null
	var setter = null
	var extra = null
	
	match prop.type:
	
		TYPE_INT, \
		TYPE_REAL:
			var pre = null
			if prop.has("randomizable") and prop.randomizable:
				editor = HBoxContainer.new()
				pre = Button.new()
				pre.connect("pressed", self, "_randomize_property_pressed", [key])
				pre.text = "Randomize"
				editor.add_child(pre)
			
			var spinbox = SpinBox.new()
			# Spinboxes have shit UX when not expanded...
			spinbox.rect_min_size = Vector2(120, 16) 
			_setup_range_control(spinbox, prop)
			spinbox.connect("value_changed", self, "_property_edited", [key])
			
			getter = funcref(spinbox, "get_value")
			setter = funcref(spinbox, "set_value")
			
			var show_slider = prop.has("range") and not (prop.has("slidable") and prop.slidable == false)
			if show_slider:
				if editor == null:
					editor = HBoxContainer.new()
				var slider = HSlider.new()
				# Need to give some size because otherwise the slider is hard to click...
				slider.rect_min_size = Vector2(32, 16)
				_setup_range_control(slider, prop)
				slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				spinbox.share(slider)
				editor.add_child(slider)
				editor.add_child(spinbox)
			else:
				spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				if editor == null:
					editor = spinbox
				else:
					editor.add_child(spinbox)
			
		TYPE_STRING:
			editor = LineEdit.new()
			editor.connect("text_entered", self, "_property_edited", [key])
			getter = funcref(editor, "get_text")
			setter = funcref(editor, "set_text")
		
		TYPE_COLOR:
			editor = ColorPickerButton.new()
			editor.connect("color_changed", self, "_property_edited", [key])
			getter = funcref(editor, "get_pick_color")
			setter = funcref(editor, "set_pick_color")
			
		TYPE_BOOL:
			editor = CheckButton.new()
			editor.connect("toggled", self, "_property_edited", [key])
			getter = funcref(editor, "is_pressed")
			setter = funcref(editor, "set_pressed")
		
		TYPE_OBJECT:
			# TODO How do I even check inheritance if I work on the class themselves, not instances?
			if prop.object_type == Resource:
				editor = HBoxContainer.new()
				
				var label = Label.new()
				label.text = "null"
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				label.clip_text = true
				label.align = Label.ALIGN_RIGHT
				editor.add_child(label)
				
				var load_button = Button.new()
				load_button.text = "Load..."
				load_button.connect("pressed", self, "_on_ask_load_texture", [key])
				editor.add_child(load_button)

				var clear_button = Button.new()
				clear_button.text = "Clear"
				clear_button.connect("pressed", self, "_on_ask_clear_texture", [key])
				editor.add_child(clear_button)
				
				ed = ResourceEditor.new()
				ed.label = label
				getter = funcref(ed, "get_value")
				setter = funcref(ed, "set_value")
		
		_:
			editor = Label.new()
			editor.text = "<not editable>"
			getter = funcref(self, "_dummy_getter")
			setter = funcref(self, "_dummy_setter")
	
	if not(editor is CheckButton):
		editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	if ed == null:
		# Default
		ed = Editor.new()
	ed.control = editor
	ed.getter = getter
	ed.setter = setter
	
	return ed


static func _setup_range_control(range_control, prop):
	if prop.type == TYPE_INT:
		range_control.step = 1
		range_control.rounded = true
	else:
		range_control.step = 0.1
	if prop.has("range"):
		range_control.min_value = prop.range.min
		range_control.max_value = prop.range.max
		if prop.range.has("step"):
			range_control.step = prop.range.step
	else:
		# Where is INT_MAX??
		range_control.min_value = -0x7fffffff
		range_control.max_value = 0x7fffffff


func _property_edited(value, key):
	if _edit_signal:
		#print("Property edited ", key, "=", value)
		emit_signal("property_changed", key, value)


func _randomize_property_pressed(key):
	var prop = _prototype[key]
	var v = 0
	
	# TODO Support range step
	match prop.type:
		TYPE_INT:
			if prop.has("range"):
				v = randi() % (prop.range.max - prop.range.min) + prop.range.min
			else:
				v = randi() - 0x7fffffff
		TYPE_REAL:
			if prop.has("range"):
				v = rand_range(prop.range.min, prop.range.max)
			else:
				v = randf()			
	
	_editors[key].setter.call_func(v)


func _dummy_getter():
	pass


func _dummy_setter(v):
	# TODO Could use extra data to store the value anyways?
	pass


func _on_ask_load_texture(key):
	_open_file_dialog.add_filter("*.png ; PNG files")
	_open_file_dialog.connect("popup_hide", self, "call_deferred", ["_on_file_dialog_close"], CONNECT_ONESHOT)
	_open_file_dialog.connect("file_selected", self, "_on_texture_selected", [key])
	_open_file_dialog.popup_centered_minsize()


func _on_file_dialog_close():
	# Disconnect listeners automatically,
	# so we can re-use the same dialog with different listeners
	var cons = _open_file_dialog.get_signal_connection_list("file_selected")
	for con in cons:
		#print("DDD Disconnect ", con.method)
		_open_file_dialog.disconnect("file_selected", con.target, con.method)


func _on_texture_selected(path, key):
	var tex = load(path)
	if tex == null:
		print("Could not load texture ", path)
		return
	var ed = _editors[key]
	ed.setter.call_func(tex)
	_property_edited(tex, key)


func _on_ask_clear_texture(key):
	var ed = _editors[key]
	ed.setter.call_func(null)
	_property_edited(null, key)

