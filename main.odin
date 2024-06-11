package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:time/datetime"
// import win32 "core:sys/windows"
import rl "vendor:raylib"

/*
  TODO:
  1. Multi-monitor support
  2. Audio!
  3. Allow timer positioning by monitor corner instead of x,y
  4. Resize window/render target to timer text size
  5. Text color/flash for warning time
  6. More INI documentation
  TODO:
*/

MAX_WINDOW_WIDTH: i32 = 1920
MAX_WINDOW_HEIGHT: i32 = 1080
DEFAULT_WINDOW_WIDTH: i32 : 640
DEFAULT_WINDOW_HEIGHT: i32 : 480
MAX_WINDOW_X: i32 = 1900
MAX_WINDOW_Y: i32 = 1060
DEFAULT_WINDOW_X: i32 : 10
DEFAULT_WINDOW_Y: i32 : 30
DEFAULT_TIMER_HOUR :: 10
DEFAULT_TIMER_MINUTE :: 25
DEFAULT_WARNING_MINUTES :: 5
DEFAULT_TIMER_AUDIO_FILE: string : "Bell1.wav"
DEFAULT_FONT_TTF_FILE: string : "RobotoMedium.ttf"
DEFAULT_FONT_SIZE: i32 : 72

UTC_OFFSET :: -4

INI_FILE_NAME: string : "timer_options.ini"

Options :: struct {
	window_width:                i32,
	window_height:               i32,
	window_x_position:           i32,
	window_y_position:           i32,
	timer_end:                   time.Time,
	warning_minutes:             int,
	timer_font_size:             i32,
	path_to_timer_audio_file:    string,
	path_to_timer_font_ttf_file: string,
}

timer_options: Options
ini_file_time: os.File_Time
warning_time: time.Time
render_target: rl.RenderTexture2D
timer_font: rl.Font

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
		case "window_width":
			{
				options.window_width = i32(strconv.atoi(v))
			}
		case "window_height":
			{
				options.window_height = i32(strconv.atoi(v))
			}
		case "window_x_position":
			{
				options.window_x_position = i32(strconv.atoi(v))
			}
		case "window_y_position":
			{
				options.window_y_position = i32(strconv.atoi(v))
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
		case "timer_font_size":
			{
				options.timer_font_size = i32(strconv.atoi(v))
			}
		case:
			{
				fmt.eprintfln("Unrecognized key: '%s'", k)
			}
		}
	}
	fmt.println(options)
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
	update_window_dimensions := false
	update_window_position := false
	reload_font := false
	reload_audio := false
	update_warning_time := false

	if options.window_width > 0 &&
	   options.window_width <= MAX_WINDOW_WIDTH &&
	   options.window_width != timer_options.window_width {
		timer_options.window_width = options.window_width
		update_window_dimensions = true
	}
	if options.window_height > 0 &&
	   options.window_height <= MAX_WINDOW_HEIGHT &&
	   options.window_height != timer_options.window_height {
		timer_options.window_height = options.window_height
		update_window_dimensions = true
	}
	if options.window_x_position >= 0 &&
	   options.window_x_position <= MAX_WINDOW_X &&
	   options.window_x_position != timer_options.window_x_position {
		timer_options.window_x_position = options.window_x_position
		update_window_position = true
	}
	if options.window_y_position >= 0 &&
	   options.window_y_position <= MAX_WINDOW_Y &&
	   options.window_y_position != timer_options.window_y_position {
		timer_options.window_y_position = options.window_y_position
		update_window_position = true
	}
	if options.path_to_timer_audio_file != timer_options.path_to_timer_audio_file {
		timer_options.path_to_timer_audio_file = options.path_to_timer_audio_file
		reload_audio = true
	}
	if options.path_to_timer_font_ttf_file != timer_options.path_to_timer_font_ttf_file {
		timer_options.path_to_timer_font_ttf_file = options.path_to_timer_font_ttf_file
		reload_font = true
	}
	if options.timer_font_size != timer_options.timer_font_size {
		timer_options.timer_font_size = options.timer_font_size
		reload_font = true
	}
	if time.diff(timer_options.timer_end, options.timer_end) != 0 {
		timer_options.timer_end = options.timer_end
		update_warning_time = true
	}
	if options.warning_minutes != timer_options.warning_minutes {
		timer_options.warning_minutes = options.warning_minutes
		update_warning_time = true
	}
	if update_warning_time {
		warning_time = time.time_add(
			timer_options.timer_end,
			time.Duration(i64(-timer_options.warning_minutes) * i64(time.Minute)),
		)
	}

	// Skip Raylib reconfiguration on first time, since Raylib hasn't been initialized yet
	if !first_time {
		if update_window_dimensions {
			rl.SetWindowSize(timer_options.window_width, timer_options.window_height)
			rl.UnloadRenderTexture(render_target)
			render_target = rl.LoadRenderTexture(
				timer_options.window_width,
				timer_options.window_height,
			)
			rl.SetTextureFilter(render_target.texture, .BILINEAR)
		}
		if update_window_position {
			rl.SetWindowPosition(timer_options.window_x_position, timer_options.window_y_position)
		}
		if reload_font {
			rl.UnloadFont(timer_font)
			timer_font = rl.LoadFontEx(
				strings.unsafe_string_to_cstring(timer_options.path_to_timer_font_ttf_file),
				timer_options.timer_font_size,
				nil,
				255,
			)
		}
		if reload_audio {

		}
	}
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
		window_width                = DEFAULT_WINDOW_WIDTH,
		window_height               = DEFAULT_WINDOW_HEIGHT,
		window_x_position           = DEFAULT_WINDOW_X,
		window_y_position           = DEFAULT_WINDOW_Y,
		timer_end                   = default_timer_end,
		warning_minutes             = DEFAULT_WARNING_MINUTES,
		path_to_timer_audio_file    = DEFAULT_TIMER_AUDIO_FILE,
		path_to_timer_font_ttf_file = DEFAULT_FONT_TTF_FILE,
		timer_font_size             = DEFAULT_FONT_SIZE,
	}

	loaded_options, success := load_ini_file()
	if !success {
		fmt.eprintln("Unable to load options INI file!")
		return
	}
	update_timer_options(loaded_options, true)

	warning_time = time.time_add(
		timer_options.timer_end,
		time.Duration(i64(-timer_options.warning_minutes) * i64(time.Minute)),
	)
	// fmt.printfln("End Time: %v:%v %v", time.clock(end_time))
	// fmt.printfln("Warning Time: %v:%v %v", time.clock(warning_time))
	if time.diff(now, timer_options.timer_end) < 0 {
		fmt.eprintln("End time has already passed!")
		return
	}

	rl.SetConfigFlags({.WINDOW_TRANSPARENT})
	rl.SetTraceLogLevel(.ERROR)
	rl.InitWindow(timer_options.window_width, timer_options.window_height, "Timer")
	rl.SetWindowPosition(timer_options.window_y_position, timer_options.window_x_position)
	rl.SetWindowState({.WINDOW_UNDECORATED})

	render_target = rl.LoadRenderTexture(timer_options.window_width, timer_options.window_height)
	rl.SetTextureFilter(render_target.texture, .BILINEAR)
	rl.SetTargetFPS(10)

	timer_font = rl.LoadFontEx(
		strings.unsafe_string_to_cstring(timer_options.path_to_timer_font_ttf_file),
		timer_options.timer_font_size,
		nil,
		255,
	)

	for time.diff(now, timer_options.timer_end) > 0 && !rl.WindowShouldClose() {
		success := check_reload_ini_file()
		if !success {
			fmt.eprintln("Error reloading INI file. Shutting down...")
			return
		}

		now = time.now()
		hours, minutes, seconds := time.clock(time.diff(now, timer_options.timer_end))
		timer_text: string
		if hours > 0 {
			timer_text = fmt.tprintf("%d:%02d:%02d", hours, minutes, seconds)
		} else {
			timer_text = fmt.tprintf("%d:%02d", minutes, seconds)
		}
		rl.BeginTextureMode(render_target)

		rl.ClearBackground(rl.BLANK)
		rl.DrawTextEx(
			timer_font,
			strings.unsafe_string_to_cstring(timer_text),
			{0, 0},
			f32(timer_options.timer_font_size),
			2,
			rl.WHITE,
		)
		rl.EndTextureMode()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLANK)
		rl.DrawTexturePro(
			render_target.texture,
			{0, 0, f32(render_target.texture.width), f32(-render_target.texture.height)},
			{0, 0, f32(timer_options.window_width), f32(timer_options.window_height)},
			{0, 0},
			0,
			rl.WHITE,
		)
		rl.EndDrawing()
	}
	rl.UnloadRenderTexture(render_target)
	rl.CloseWindow()
}
