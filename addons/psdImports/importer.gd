@tool
extends EditorImportPlugin

# Set to false for faster imports (no console output)
const DEBUG_PRINTS = false

func _get_importer_name() -> String:
	return "psd_importer"

func _get_visible_name() -> String:
	return "PSD Image"

func _get_recognized_extensions() -> PackedStringArray:
	return ["psd"]

func _get_save_extension() -> String:
	return "res"

func _get_resource_type() -> String:
	return "Image"

func _get_preset_count() -> int:
	return 1

func _get_preset_name(preset_index: int) -> String:
	return "Default"

func _get_import_options(path: String, preset_index: int) -> Array:
	return []

func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true

func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array, gen_files: Array) -> int:
	if DEBUG_PRINTS:
		print("========================================")
		print("PSD Import: ", source_file)
	
	# Read the PSD file
	var file = FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		push_error("Cannot open PSD file: " + source_file)
		return FAILED
	
	var psd_data = file.get_buffer(file.get_length())
	file.close()
	
	if DEBUG_PRINTS:
		print("Read %d bytes from PSD file" % psd_data.size())
	
	# Parse PSD file
	var img = _parse_psd(psd_data)
	if img == null:
		push_error("Failed to parse PSD file: " + source_file)
		return FAILED
	
	# Set metadata on the image to help track changes
	img.set_meta("psd_source", source_file)
	var content_hash = hash(psd_data)
	img.set_meta("psd_hash", content_hash)
	img.set_meta("import_time", Time.get_unix_time_from_system())
	
	# Save the Image resource
	var full_save_path = "%s.%s" % [save_path, _get_save_extension()]
	var err = ResourceSaver.save(img, full_save_path)
	
	if err != OK:
		push_error("Failed to save image resource: " + str(err))
		return FAILED
	
	if DEBUG_PRINTS:
		print("✓ Successfully imported to: ", full_save_path)
		print("========================================")
	
	return OK

func _parse_psd(data: PackedByteArray) -> Image:
	if data.size() < 26:
		push_error("PSD file too small")
		return null
	
	# Check signature "8BPS"
	if data[0] != 0x38 or data[1] != 0x42 or data[2] != 0x50 or data[3] != 0x53:
		push_error("Invalid PSD signature")
		return null
	
	# Read version
	var version = _read_short(data, 4)
	if version != 1:
		push_error("Unsupported PSD version: " + str(version))
		return null
	
	# Read header info
	var channels = _read_short(data, 12)
	var height = _read_long(data, 14)
	var width = _read_long(data, 18)
	var depth = _read_short(data, 22)
	var color_mode = _read_short(data, 24)
	
	if DEBUG_PRINTS:
		print("=== PSD: %dx%d, %d channels, %d-bit, mode %d ===" % [width, height, channels, depth, color_mode])
	
	var offset = 26
	
	# Skip Color Mode Data section (we don't need this)
	var color_mode_data_length = _read_long(data, offset)
	offset += 4 + color_mode_data_length
	
	# Skip Image Resources section (we don't need this)
	var image_resources_length = _read_long(data, offset)
	offset += 4 + image_resources_length
	
	# Skip Layer and Mask Information section (we only want merged image)
	var layer_mask_length = _read_long(data, offset)
	offset += 4 + layer_mask_length
	
	# Compression method (2 bytes)
	var compression = _read_short(data, offset)
	offset += 2
	
	if DEBUG_PRINTS:
		print("Decompressing %s..." % ("RLE" if compression == 1 else "RAW"))
	
	# Create the image
	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)
	
	var decompress_start = Time.get_ticks_msec() if DEBUG_PRINTS else 0
	
	if compression == 0:
		_read_raw_image_data(data, offset, img, width, height, channels, depth, color_mode)
	elif compression == 1:
		_read_rle_image_data(data, offset, img, width, height, channels, depth, color_mode)
	else:
		push_error("Unsupported compression method: " + str(compression))
		return null
	
	if DEBUG_PRINTS:
		var decompress_time = Time.get_ticks_msec() - decompress_start
		print("✓ Decompression complete (%d ms)" % decompress_time)
	
	return img

func _read_raw_image_data(data: PackedByteArray, offset: int, img: Image, width: int, height: int, channels: int, depth: int, color_mode: int) -> void:
	var bytes_per_channel = depth / 8
	var pixels_per_channel = width * height
	
	# Create raw RGBA byte array for fast bulk operation
	var rgba_data = PackedByteArray()
	rgba_data.resize(width * height * 4)
	
	for y in range(height):
		for x in range(width):
			var pixel_index = y * width + x
			var byte_index = pixel_index * 4
			var r = 0
			var g = 0
			var b = 0
			var a = 255
			
			if color_mode == 3:  # RGB
				if channels >= 3:
					r = data[offset + pixel_index]
					g = data[offset + pixels_per_channel + pixel_index]
					b = data[offset + pixels_per_channel * 2 + pixel_index]
				if channels >= 4:
					a = data[offset + pixels_per_channel * 3 + pixel_index]
			elif color_mode == 1:  # Grayscale
				var gray = data[offset + pixel_index]
				r = gray
				g = gray
				b = gray
				if channels >= 2:
					a = data[offset + pixels_per_channel + pixel_index]
			
			rgba_data[byte_index] = r
			rgba_data[byte_index + 1] = g
			rgba_data[byte_index + 2] = b
			rgba_data[byte_index + 3] = a
	
	# Set data in one bulk operation - MUCH faster than set_pixel()
	img.set_data(width, height, false, Image.FORMAT_RGBA8, rgba_data)

func _read_rle_image_data(data: PackedByteArray, offset: int, img: Image, width: int, height: int, channels: int, depth: int, color_mode: int) -> void:
	# RLE has byte counts first
	var scanline_count = height * channels
	var byte_counts_size = scanline_count * 2
	
	var data_offset = offset + byte_counts_size
	
	# Decompress each channel
	var channel_data = []
	for c in range(channels):
		var channel_pixels = PackedByteArray()
		channel_pixels.resize(width * height)
		var write_index = 0
		
		for row in range(height):
			while write_index < (row + 1) * width:
				if data_offset >= data.size():
					push_error("RLE: Ran out of data at row %d" % row)
					break
				
				var len = data[data_offset]
				data_offset += 1
				
				if len < 128:
					# Copy literal bytes
					var count = len + 1
					for i in range(count):
						if data_offset >= data.size() or write_index >= channel_pixels.size():
							break
						channel_pixels[write_index] = data[data_offset]
						data_offset += 1
						write_index += 1
				elif len > 128:
					# Repeat byte
					var count = 257 - len
					if data_offset >= data.size():
						break
					var value = data[data_offset]
					data_offset += 1
					for i in range(count):
						if write_index >= channel_pixels.size():
							break
						channel_pixels[write_index] = value
						write_index += 1
		
		channel_data.append(channel_pixels)
	
	# Convert planar to RGBA in one pass - MUCH faster
	var rgba_data = PackedByteArray()
	rgba_data.resize(width * height * 4)
	
	var total_pixels = width * height
	for pixel_index in range(total_pixels):
		var byte_index = pixel_index * 4
		var r = 0
		var g = 0
		var b = 0
		var a = 255
		
		if color_mode == 3:  # RGB
			if channels >= 3 and pixel_index < channel_data[0].size():
				r = channel_data[0][pixel_index]
				g = channel_data[1][pixel_index]
				b = channel_data[2][pixel_index]
			if channels >= 4 and pixel_index < channel_data[3].size():
				a = channel_data[3][pixel_index]
		elif color_mode == 1:  # Grayscale
			if pixel_index < channel_data[0].size():
				var gray = channel_data[0][pixel_index]
				r = gray
				g = gray
				b = gray
			if channels >= 2 and pixel_index < channel_data[1].size():
				a = channel_data[1][pixel_index]
		
		rgba_data[byte_index] = r
		rgba_data[byte_index + 1] = g
		rgba_data[byte_index + 2] = b
		rgba_data[byte_index + 3] = a
	
	# Set all data at once - MUCH faster than set_pixel()
	img.set_data(width, height, false, Image.FORMAT_RGBA8, rgba_data)

func _read_short(data: PackedByteArray, offset: int) -> int:
	return (int(data[offset]) << 8) | int(data[offset + 1])

func _read_long(data: PackedByteArray, offset: int) -> int:
	return (int(data[offset]) << 24) | (int(data[offset + 1]) << 16) | (int(data[offset + 2]) << 8) | int(data[offset + 3])
