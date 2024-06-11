package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
// import "core:time/datetime"
import rl "vendor:raylib"

DEFAULT_WINDOW_POSITION :: WindowPosition.TopRight
DEFAULT_MONITOR: i32 : 1
DEFAULT_TIMER_HOUR :: 10
DEFAULT_TIMER_MINUTE :: 25
DEFAULT_WARNING_MINUTES :: 5
DEFAULT_TIMER_AUDIO_FILE: string : "Bell1.wav"
DEFAULT_FONT_TTF_FILE: string : "RobotoMedium.ttf"
DEFAULT_FONT_SIZE: i32 : 72
DEFAULT_WARNING_FONT_SIZE: i32 : 80
DEFAULT_FONT_SPACING: f32 : 2
DEFAULT_EDGE_BUFFER_PIXELS: i32 : 10

UTC_OFFSET :: -4

INI_FILE_NAME: string : "timer_options.ini"

WindowPosition :: enum {
	TopRight,
	TopLeft,
	BottomRight,
	BottomLeft,
}

Options :: struct {
	position:                    WindowPosition,
	monitor:                     i32,
	timer_end:                   time.Time,
	warning_minutes:             int,
	font_size:                   i32,
	warning_font_size:           i32,
	font_spacing:                f32,
	edge_margin_pixels:          i32,
	path_to_timer_audio_file:    string,
	path_to_timer_font_ttf_file: string,
}

timer_options: Options
ini_file_time: os.File_Time
warning_time: time.Duration
render_target: rl.RenderTexture2D
timer_font: rl.Font
timer_warning_font: rl.Font

load_ini_file :: proc() -> (Options, bool) {
	fileerr: os.Errno
	ini_file_time, fileerr = os.last_write_time_by_name(INI_FILE_NAME)
	if fileerr != os.ERROR_NONE {
		fmt.eprintfln("Failed to get file time for INI file '%s': %v", INI_FILE_NAME, fileerr)
		return {}, false
	}
	data, success := os.read_entire_file(INI_FILE_NAME)
	defer delete(data)
	if !success {
		fmt.eprintfln("ERROR: Failed to read INI file '%s'", INI_FILE_NAME)
		return {}, false
	}

	lines, err := strings.split_lines(string(data))
	defer delete(lines)
	if err != nil {
		fmt.eprintln("Memory allocation error")
		return {}, false
	}
	values := make([]string, len(lines))
	defer delete(values)

	idx := 0
	// First, check for comments
	for line in lines {
		res, _ := strings.split(line, ";")
		defer delete(res)
		if res[0] != "" {
			values[idx] = strings.trim(res[0], " ")
			// values[idx] = res[0]
			idx += 1
		}
	}
	values = values[:idx]

	options: Options = {}

	for value in values {
		res, _ := strings.split(value, "=")
		defer delete(res)
		if len(res) != 2 {
			fmt.eprintfln("Invalid key/value pair in INI file: %v", res)
			return {}, false
		}
		k := strings.trim(res[0], " ")
		v := strings.trim(res[1], " ")
		switch k {
		case "position":
			{
				switch v {
				case "topleft":
					{
						options.position = .TopLeft
					}
				case "topright":
					{
						options.position = .TopRight
					}
				case "bottomleft":
					{
						options.position = .BottomLeft
					}
				case "bottomright":
					{
						options.position = .BottomRight
					}
				case:
					{
						fmt.eprintfln(
							"Invalid window position choice: '%s', defaulting to %v",
							v,
							DEFAULT_WINDOW_POSITION,
						)
					}
				}
			}
		case "monitor":
			{
				options.monitor = i32(strconv.atoi(v))
			}
		case "timer_end_in_military_time":
			{
				val := i32(strconv.atoi(v))
				if val < 0 || val > 2359 {
					fmt.eprintfln("ERROR: Invalid timer_end_in_military_time in INI file: %v", val)
					return {}, false
				}
				now := time.now()
				options.timer_end, _ = time.components_to_time(
					time.year(now),
					time.month(now),
					time.day(now),
					(val / 100) - UTC_OFFSET,
					(val % 100),
					0,
				)
			}
		case "warning_minutes":
			{
				options.warning_minutes = strconv.atoi(v)
			}
		case "path_to_timer_audio_file":
			{
				options.path_to_timer_audio_file = v
			}
		case "path_to_timer_font_ttf_file":
			{
				options.path_to_timer_font_ttf_file = v
			}
		case "font_size":
			{
				options.font_size = i32(strconv.atoi(v))
			}
		case "warning_font_size":
			{
				options.warning_font_size = i32(strconv.atoi(v))
			}
		case "font_spacing":
			{
				options.font_spacing = f32(strconv.atof(v))
			}
		case "edge_margin_pixels":
			{
				options.edge_margin_pixels = i32(strconv.atoi(v))
			}
		case:
			{
				fmt.eprintfln("Unrecognized key: '%s'", k)
			}
		}
	}
	// fmt.println(options)
	return options, true
}

check_reload_ini_file :: proc() -> bool {
	curr_file_time, err := os.last_write_time_by_name(INI_FILE_NAME)
	if err != os.ERROR_NONE {
		fmt.eprintfln("Failed to get file time for INI file '%s': %v", INI_FILE_NAME, err)
		return false
	}
	if curr_file_time > ini_file_time {
		options, success := load_ini_file()
		if !success {
			return false
		}
		update_timer_options(options)
		return true
	}
	return true
}

update_timer_options :: proc(options: Options, first_time: bool = false) {
	reload_font := false
	reload_warning_font := false
	reload_audio := false

	if options.position != timer_options.position {
		timer_options.position = options.position
	}
	if options.monitor != timer_options.monitor {
		timer_options.monitor = options.monitor
		rl.SetWindowMonitor(timer_options.monitor)
	}
	if options.path_to_timer_audio_file != timer_options.path_to_timer_audio_file {
		timer_options.path_to_timer_audio_file = options.path_to_timer_audio_file
		reload_audio = true
	}
	if options.path_to_timer_font_ttf_file != timer_options.path_to_timer_font_ttf_file {
		timer_options.path_to_timer_font_ttf_file = options.path_to_timer_font_ttf_file
		reload_font = true
	}
	if options.font_size != timer_options.font_size {
		timer_options.font_size = options.font_size
		reload_font = true
	}
	if options.warning_font_size != timer_options.warning_font_size {
		timer_options.warning_font_size = options.warning_font_size
		reload_warning_font = true
	}
	if options.font_spacing != timer_options.font_spacing {
		timer_options.font_spacing = options.font_spacing
	}
	if options.edge_margin_pixels != timer_options.edge_margin_pixels {
		timer_options.edge_margin_pixels = options.edge_margin_pixels
	}
	if time.diff(timer_options.timer_end, options.timer_end) != 0 {
		timer_options.timer_end = options.timer_end
	}
	if options.warning_minutes != timer_options.warning_minutes {
		timer_options.warning_minutes = options.warning_minutes
	}
	warning_time = time.Duration(i64(timer_options.warning_minutes) * i64(time.Minute))

	// Skip Raylib reconfiguration on first time, since Raylib hasn't been initialized yet
	if !first_time {
		if reload_font {
			rl.UnloadFont(timer_font)
			timer_font = rl.LoadFontEx(
				strings.unsafe_string_to_cstring(timer_options.path_to_timer_font_ttf_file),
				timer_options.font_size,
				nil,
				0,
			)
		}
		if reload_warning_font {
			rl.UnloadFont(timer_warning_font)
			timer_warning_font = rl.LoadFontEx(
				strings.unsafe_string_to_cstring(timer_options.path_to_timer_font_ttf_file),
				timer_options.warning_font_size,
				nil,
				0,
			)
		}
		if reload_audio {

		}
	}
}

draw_timer :: proc() -> bool {
	now := time.now()
	diff := time.diff(now, timer_options.timer_end)
	is_warning := diff <= warning_time
	// fmt.printfln("Diff: %v, Warning: %v, IsWarning: %v", diff, warning_time, is_warning)
	hours, minutes, seconds := time.clock(diff)
	timer_text: string
	if hours > 0 {
		timer_text = fmt.tprintf("%d:%02d:%02d", hours, minutes, seconds)
	} else {
		timer_text = fmt.tprintf("%d:%02d", minutes, seconds)
	}
	font_size := rl.MeasureTextEx(
		is_warning ? timer_warning_font : timer_font,
		strings.unsafe_string_to_cstring(timer_text),
		is_warning ? f32(timer_options.warning_font_size) : f32(timer_options.font_size),
		timer_options.font_spacing,
	)

	window_x: i32 = 0
	window_y: i32 = 0
	switch timer_options.position {
	case .TopLeft:
		{
			window_x = 0
			window_y = 0
		}
	case .TopRight:
		{
			window_x =
				rl.GetMonitorWidth(timer_options.monitor) -
				i32(font_size[0]) -
				timer_options.edge_margin_pixels
			window_y = 0
		}
	case .BottomLeft:
		{
			window_x = 0
			window_y =
				rl.GetMonitorHeight(timer_options.monitor) -
				i32(font_size[1]) -
				timer_options.edge_margin_pixels
		}
	case .BottomRight:
		{
			window_x =
				rl.GetMonitorWidth(timer_options.monitor) -
				i32(font_size[0]) -
				timer_options.edge_margin_pixels
			window_y =
				rl.GetMonitorHeight(timer_options.monitor) -
				i32(font_size[1]) -
				timer_options.edge_margin_pixels
		}
	}
	rl.SetWindowPosition(window_x, window_y)

	texture_width := i32(font_size[0]) + timer_options.edge_margin_pixels
	texture_height := i32(font_size[1]) + timer_options.edge_margin_pixels
	if texture_width != render_target.texture.width ||
	   texture_height != render_target.texture.height {
		rl.SetWindowSize(texture_width, texture_height)
		rl.UnloadRenderTexture(render_target)
		render_target = rl.LoadRenderTexture(texture_width, texture_height)
		rl.SetTextureFilter(render_target.texture, .BILINEAR)
	}

	rl.BeginTextureMode(render_target)
	rl.ClearBackground(rl.BLANK)
	texture_position: rl.Vector2
	switch timer_options.position {
	case .TopLeft:
		{
			texture_position = {
				f32(timer_options.edge_margin_pixels),
				f32(timer_options.edge_margin_pixels),
			}
		}
	case .TopRight:
		{
			texture_position = {0, f32(timer_options.edge_margin_pixels)}
		}
	case .BottomLeft:
		{
			texture_position = {f32(timer_options.edge_margin_pixels), 0}
		}
	case .BottomRight:
		{
			texture_position = {0, 0}
		}
	}
	// fmt.printfln(
	// 	"Window: %v, Texture: %v",
	// 	rl.Vector2{f32(window_x), f32(window_y)},
	// 	rl.Vector2{f32(texture_width), f32(texture_height)},
	// )
	rl.DrawTextEx(
		is_warning ? timer_warning_font : timer_font,
		strings.unsafe_string_to_cstring(timer_text),
		texture_position,
		is_warning ? f32(timer_options.warning_font_size) : f32(timer_options.font_size),
		timer_options.font_spacing,
		// rl.WHITE,
		is_warning ? rl.RED : rl.WHITE,
	)
	rl.EndTextureMode()

	rl.BeginDrawing()
	rl.ClearBackground(rl.BLANK)
	rl.DrawTexturePro(
		render_target.texture,
		{0, 0, f32(render_target.texture.width), f32(-render_target.texture.height)},
		{0, 0, f32(texture_width), f32(texture_height)},
		{0, 0},
		0,
		rl.WHITE,
	)
	rl.EndDrawing()

	return true
}

// TODO: INI loading
main :: proc() {
	now := time.now()
	default_timer_end, _ := time.components_to_time(
		time.year(now),
		time.month(now),
		time.day(now),
		DEFAULT_TIMER_HOUR - UTC_OFFSET,
		DEFAULT_TIMER_MINUTE,
		0,
	)
	timer_options = {
		position                    = DEFAULT_WINDOW_POSITION,
		timer_end                   = default_timer_end,
		warning_minutes             = DEFAULT_WARNING_MINUTES,
		path_to_timer_audio_file    = DEFAULT_TIMER_AUDIO_FILE,
		path_to_timer_font_ttf_file = DEFAULT_FONT_TTF_FILE,
		font_size                   = DEFAULT_FONT_SIZE,
		warning_font_size           = DEFAULT_WARNING_FONT_SIZE,
		font_spacing                = DEFAULT_FONT_SPACING,
		edge_margin_pixels          = DEFAULT_EDGE_BUFFER_PIXELS,
	}

	loaded_options, success := load_ini_file()
	if !success {
		fmt.eprintln("Unable to load options INI file!")
		return
	}
	update_timer_options(loaded_options, true)

	// fmt.printfln("End Time: %v:%v %v", time.clock(end_time))
	// fmt.printfln("Warning Time: %v:%v %v", time.clock(warning_time))
	current_time := time.diff(now, timer_options.timer_end)
	if current_time < 0 {
		fmt.eprintln("End time has already passed!")
		return
	}

	rl.SetConfigFlags({.WINDOW_TRANSPARENT, .MSAA_4X_HINT, .WINDOW_HIDDEN})
	rl.SetTraceLogLevel(.ERROR)
	rl.InitWindow(640, 480, "Timer")
	rl.SetWindowState({.WINDOW_UNDECORATED})

	render_target = rl.LoadRenderTexture(640, 480)
	rl.SetTextureFilter(render_target.texture, .BILINEAR)
	rl.SetTargetFPS(10)

	timer_font = rl.LoadFontEx(
		strings.unsafe_string_to_cstring(timer_options.path_to_timer_font_ttf_file),
		timer_options.font_size,
		nil,
		0,
	)
	timer_warning_font = rl.LoadFontEx(
		strings.unsafe_string_to_cstring(timer_options.path_to_timer_font_ttf_file),
		timer_options.warning_font_size,
		nil,
		0,
	)
	draw_timer()
	rl.ClearWindowState({.WINDOW_HIDDEN})

	for draw_timer() && !rl.WindowShouldClose() {
		success := check_reload_ini_file()
		if !success {
			fmt.eprintln("Error reloading INI file. Shutting down...")
			return
		}

		free_all(context.temp_allocator)
	}
	rl.UnloadRenderTexture(render_target)
	rl.CloseWindow()
}
