package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
// import "core:time/datetime"
import rl "vendor:raylib"

DEFAULT_WINDOW_POSITION :: WindowPosition.TopRight
DEFAULT_MONITOR: i32 : 0
DEFAULT_TIMER_HOUR :: 10
DEFAULT_TIMER_MINUTE :: 25
DEFAULT_WARNING_MINUTES :: 5
DEFAULT_END_TIMER_RINGS :: 2
DEFAULT_END_TIMER_SECONDS :: 2
DEFAULT_TIMER_AUDIO_FILE: string : "Bell1.wav"
DEFAULT_FONT_TTF_FILE: string : "RobotoMedium.ttf"
DEFAULT_FONT_SIZE: i32 : 72
DEFAULT_WARNING_FONT_SIZE: i32 : 80
DEFAULT_FONT_SPACING: f32 : 2
DEFAULT_EDGE_BUFFER_PIXELS: i32 : 10
DEFAULT_SHADOW_THICKNESS: f32 : 5

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
	end_timer_rings:             int,
	end_timer_seconds:           int,
	font_size:                   i32,
	warning_font_size:           i32,
	font_spacing:                f32,
	edge_margin_pixels:          i32,
	shadow_thickness:            f32,
	path_to_timer_audio_file:    string,
	path_to_timer_font_ttf_file: string,
}

timer_options: Options
ini_file_time: os.File_Time
warning_time: time.Duration
render_target: rl.RenderTexture2D
shadow_target: rl.RenderTexture2D
timer_font: rl.Font
timer_warning_font: rl.Font
timer_sound: rl.Sound
blur_shader: rl.Shader

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
		// case "monitor":
		// 	{
		// 		options.monitor = i32(strconv.atoi(v))
		// 	}
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
				options.path_to_timer_audio_file = strings.clone(v)
			}
		case "path_to_timer_font_ttf_file":
			{
				options.path_to_timer_font_ttf_file = strings.clone(v)
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
		case "shadow_thickness":
			{
				options.shadow_thickness = f32(strconv.atof(v))
			}
		case "end_timer_rings":
			{
				options.end_timer_rings = strconv.atoi(v)
			}
		case "end_timer_seconds":
			{
				options.end_timer_seconds = strconv.atoi(v)
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
	// update_monitor := false

	// fmt.printfln("Current monitor: %v", rl.GetCurrentMonitor())

	if options.position != timer_options.position {
		timer_options.position = options.position
	}
	// if options.monitor != timer_options.monitor {
	// 	timer_options.monitor = options.monitor
	// 	update_monitor = true
	// }
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
	if options.shadow_thickness != timer_options.shadow_thickness {
		timer_options.shadow_thickness = options.shadow_thickness
	}

	if time.diff(timer_options.timer_end, options.timer_end) != 0 {
		now := time.now()
		ok: bool
		hr, mn, sc := time.clock(options.timer_end)
		new_end := options.timer_end
		if time.diff(now, options.timer_end) < 0 {
			new_end, ok = time.components_to_time(
				time.year(now),
				time.month(now),
				time.day(now) + 1, // (24 * time.Hour),
				hr,
				mn,
				sc,
			)}
		timer_options.timer_end = new_end
	}
	if options.warning_minutes != timer_options.warning_minutes {
		timer_options.warning_minutes = options.warning_minutes
	}
	if options.end_timer_rings != timer_options.end_timer_rings {
		timer_options.end_timer_rings = options.end_timer_rings
	}
	if options.end_timer_seconds != timer_options.end_timer_seconds {
		timer_options.end_timer_seconds = options.end_timer_seconds
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
			timer_sound = rl.LoadSound(
				strings.unsafe_string_to_cstring(timer_options.path_to_timer_audio_file),
			)
		}
		// if update_monitor {			
		// rl.SetWindowMonitor(timer_options.monitor)
		// }
	}
}

draw_timer :: proc() -> bool {
	zero_time := (1 * time.Second) - (1 * time.Nanosecond)
	now := time.now()
	diff := time.diff(now, timer_options.timer_end)
	is_warning := diff <= (warning_time + zero_time)
	is_done := diff <= zero_time

	hours, minutes, seconds := time.clock(diff)
	if is_done {
		hours = 0
		minutes = 0
		seconds = 0
	}
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

	@(static)
	final_draw := false

	texture_width := i32(font_size[0]) + timer_options.edge_margin_pixels
	texture_height := i32(font_size[1]) + timer_options.edge_margin_pixels

	if !final_draw {
		if texture_width != render_target.texture.width ||
		   texture_height != render_target.texture.height {
			rl.SetWindowSize(texture_width, texture_height)
			rl.UnloadRenderTexture(render_target)
			rl.UnloadRenderTexture(shadow_target)
			render_target = rl.LoadRenderTexture(texture_width, texture_height)
			shadow_target = rl.LoadRenderTexture(texture_width, texture_height)
			rl.SetTextureFilter(render_target.texture, .ANISOTROPIC_4X)
			rl.SetTextureFilter(shadow_target.texture, .POINT)
		}

		texture_position: rl.Vector2
		switch timer_options.position {
		case .TopLeft:
			{
				texture_position = {f32(timer_options.edge_margin_pixels), 0}
			}
		case .TopRight:
			{
				texture_position = {0, 0}
			}
		case .BottomLeft:
			{
				texture_position = {
					f32(timer_options.edge_margin_pixels),
					f32(timer_options.edge_margin_pixels),
				}
			}
		case .BottomRight:
			{
				texture_position = {0, f32(timer_options.edge_margin_pixels)}
			}
		}

		rl.BeginTextureMode(shadow_target)
		rl.ClearBackground(rl.BLANK)
		rl.BeginBlendMode(.ADDITIVE)
		offset: rl.Vector2
		for x in -1 ..= 1 {
			for y in -1 ..= 1 {
				if y == 0 && x == 0 {continue}
				offset = {f32(x), f32(y)}
				offset = rl.Vector2Normalize(offset)
				offset = {
					offset.x * timer_options.shadow_thickness,
					offset.y * timer_options.shadow_thickness,
				}

				rl.DrawTextEx(
					is_warning ? timer_warning_font : timer_font,
					strings.unsafe_string_to_cstring(timer_text),
					texture_position + offset,
					is_warning \
					? f32(timer_options.warning_font_size) \
					: f32(timer_options.font_size),
					timer_options.font_spacing,
					rl.BLACK,
				)
			}
		}
		rl.EndBlendMode()
		rl.EndTextureMode()

		rl.BeginTextureMode(render_target)
		rl.ClearBackground(rl.BLANK)
		renderWidth := f32(shadow_target.texture.width)
		renderHeight := f32(shadow_target.texture.height)
		// rl.BeginShaderMode(blur_shader)
		// rl.SetShaderValue(
		// 	blur_shader,
		// 	rl.GetShaderLocation(blur_shader, "renderWidth"),
		// 	&renderWidth,
		// 	.FLOAT,
		// )
		// rl.SetShaderValue(
		// 	blur_shader,
		// 	rl.GetShaderLocation(blur_shader, "renderHeight"),
		// 	&renderHeight,
		// 	.FLOAT,
		// )
		rl.DrawTexturePro(
			shadow_target.texture,
			{0, 0, renderWidth, -renderHeight},
			{0, 0, f32(texture_width), f32(texture_height)},
			{0, 0},
			0,
			rl.BLACK,
		)
		rl.DrawTextEx(
			is_warning ? timer_warning_font : timer_font,
			strings.unsafe_string_to_cstring(timer_text),
			texture_position,
			is_warning ? f32(timer_options.warning_font_size) : f32(timer_options.font_size),
			timer_options.font_spacing,
			is_warning ? rl.RED : rl.WHITE,
		)
		// rl.EndShaderMode()
		rl.EndTextureMode()
	}

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

	@(static)
	warning_sound_was_played := false
	if is_warning && !warning_sound_was_played {
		warning_sound_was_played = true
		rl.PlaySound(timer_sound)
	}

	@(static)
	done_stopwatch: time.Stopwatch
	@(static)
	num_rings := 0
	end_timer_delay :=
		(time.Duration(timer_options.end_timer_seconds + 1) * time.Second) -
		(1 * time.Second - 1 * time.Nanosecond)
	if final_draw {
		if time.stopwatch_duration(done_stopwatch) >= end_timer_delay {
			rl.PlaySound(timer_sound)
			num_rings += 1
			if num_rings == timer_options.end_timer_rings {
				return false
			}
			time.stopwatch_reset(&done_stopwatch)
			time.stopwatch_start(&done_stopwatch)
		}
	}

	if is_done && !final_draw {
		final_draw = true
		rl.PlaySound(timer_sound)
		num_rings += 1
		time.stopwatch_start(&done_stopwatch)
	}


	return true
}

// TODO: INI loading
main :: proc() {
	// Configure timer and load options file
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
		end_timer_seconds           = DEFAULT_END_TIMER_SECONDS,
		path_to_timer_audio_file    = DEFAULT_TIMER_AUDIO_FILE,
		path_to_timer_font_ttf_file = DEFAULT_FONT_TTF_FILE,
		font_size                   = DEFAULT_FONT_SIZE,
		warning_font_size           = DEFAULT_WARNING_FONT_SIZE,
		font_spacing                = DEFAULT_FONT_SPACING,
		edge_margin_pixels          = DEFAULT_EDGE_BUFFER_PIXELS,
		shadow_thickness            = DEFAULT_SHADOW_THICKNESS,
	}

	loaded_options, success := load_ini_file()
	if !success {
		fmt.eprintln("Unable to load options INI file!")
		return
	}
	update_timer_options(loaded_options, true)

	current_time := time.diff(now, timer_options.timer_end)
	ok: bool
	if current_time < 0 {
		hr, mn, sc := time.clock(timer_options.timer_end)
		timer_options.timer_end, ok = time.components_to_time(
			time.year(now),
			time.month(now),
			time.day(now) + 1, // (24 * time.Hour),
			hr,
			mn,
			sc,
		)
	}

	// Open window
	rl.SetConfigFlags({.WINDOW_TRANSPARENT, .MSAA_4X_HINT, .WINDOW_HIDDEN})
	rl.SetTraceLogLevel(.ERROR)
	rl.InitWindow(640, 480, "Timer")
	defer rl.CloseWindow()
	rl.SetWindowState({.WINDOW_UNDECORATED})
	// rl.SetWindowMonitor(timer_options.monitor)

	// Configure render texture
	render_target = rl.LoadRenderTexture(640, 480)
	shadow_target = rl.LoadRenderTexture(640, 480)
	defer rl.UnloadRenderTexture(render_target)
	defer rl.UnloadRenderTexture(shadow_target)
	rl.SetTextureFilter(render_target.texture, .ANISOTROPIC_4X)
	rl.SetTextureFilter(shadow_target.texture, .POINT)
	rl.SetTargetFPS(60)

	// Load fonts
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
	blur_shader = rl.LoadShader(nil, "blur.fs")

	// Init audio device and load audio
	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	assert(rl.IsAudioDeviceReady())
	timer_sound = rl.LoadSound(
		strings.unsafe_string_to_cstring(timer_options.path_to_timer_audio_file),
	)

	// First draw
	draw_timer()
	rl.ClearWindowState({.WINDOW_HIDDEN})

	// Application loop
	for draw_timer() && !rl.WindowShouldClose() {
		success := check_reload_ini_file()
		if !success {
			fmt.eprintln("Error reloading INI file. Shutting down...")
			return
		}

		free_all(context.temp_allocator)
	}
	for rl.IsSoundPlaying(timer_sound) {
	}
}
