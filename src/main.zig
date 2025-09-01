const rl = @import("raylib");
const rg = @import("raygui");
const std = @import("std");

var grid_lines = false;
var spline_dots = false;
var grid_segments: i32 = 8;

var ear_tip_x: f32 = 25;
var ear_tip_y: f32 = -50;

var start_timer = false;
var seconds_accum: f32 = 0;

// Lap system variables
var lap_minutes: i32 = 1;
var lap_seconds: i32 = 30;
var total_laps: i32 = 3;
var current_lap: i32 = 0;
var checkpoint_sound: rl.Sound = undefined;
var finisher_sound: rl.Sound = undefined;
var sounds_loaded = false;
var sounds_muted = false;

// Config overlay state
var show_config_overlay = false;

// Config file path
var config_path_buffer: [256]u8 = undefined;

// Particle system for completion effect
const MAX_PARTICLES = 200;
var particles: [MAX_PARTICLES]Particle = undefined;
var particles_active = false;
var particle_timer: f32 = 0;

const Particle = struct {
    position: rl.Vector2,
    velocity: rl.Vector2,
    life: f32,
    size: f32,
    color: rl.Color,
};

var h: i32 = 0;
var w: i32 = 0;

var screen_size: rl.Vector2 = rl.Vector2.init(0, 0);
var screen_center: rl.Vector2 = rl.Vector2.init(0, 0);
var clock_center: rl.Vector2 = rl.Vector2.init(0, 0);

const background_color = rl.Color{ .r = 23, .g = 23, .b = 28, .a = 255 };
const edge_color = rl.Color{ .r = 255, .g = 140, .b = 180, .a = 240 };
const minute_color: rl.Color = rl.Color{ .r = 255, .g = 140, .b = 180, .a = 240 };
const second_color: rl.Color = rl.Color{ .r = 255, .g = 80, .b = 160, .a = 255 };
const text_color: rl.Color = .white;

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 512;
    const screenHeight = 650;

    rl.setConfigFlags(.{
        .window_transparent = true,
        .msaa_4x_hint = true,
    });

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    // Load configuration
    loadConfig();

    // Load sound effects - only set sounds_loaded if both files exist and load successfully
    if (rl.fileExists("checkpoint.flac") and rl.fileExists("finisher.flac")) {
        checkpoint_sound = rl.loadSound("checkpoint.flac") catch |err| blk: {
            std.log.warn("Failed to load checkpoint.flac: {}", .{err});
            break :blk undefined;
        };
        finisher_sound = rl.loadSound("finisher.flac") catch |err| blk: {
            std.log.warn("Failed to load finisher.flac: {}", .{err});
            break :blk undefined;
        };
        sounds_loaded = true;
    }
    defer {
        if (sounds_loaded) {
            rl.unloadSound(checkpoint_sound);
            rl.unloadSound(finisher_sound);
        }
    }

    // Initialize particles
    initParticles();

    //--------------------------------------------------------------------------------------

    const initial_angle: f32 = 180;

    var minutes_angle: f32 = initial_angle;
    var seconds_angle: f32 = initial_angle;

    var ear_tip_height: f32 = 200 + 30;

    setupCatTimerStyle();

    rl.setTargetFPS(60);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        const deltaTime = rl.getFrameTime();

        // if (rl.isKeyPressed(.d)) {
        //     spline_dots = !spline_dots;
        // }
        //
        // if (rl.isKeyPressed(.g)) {
        //     grid_lines = !grid_lines;
        // }
        //
        if (rl.isKeyPressed(.kp_subtract)) {
            grid_segments -= 1;
        }

        if (rl.isKeyPressed(.kp_add)) {
            grid_segments += 1;
        }

        if (rl.isKeyPressed(.page_up)) {
            ear_tip_height += 5;
        }

        if (rl.isKeyPressed(.page_down)) {
            ear_tip_height -= 5;
        }

        if (rl.isKeyPressed(.up)) {
            ear_tip_y -= 5;
        }

        if (rl.isKeyPressed(.down)) {
            ear_tip_y += 5;
        }

        if (rl.isKeyPressed(.right)) {
            ear_tip_x += 5;
        }

        if (rl.isKeyPressed(.left)) {
            ear_tip_x -= 5;
        }

        // Toggle config overlay with 'C' key
        if (rl.isKeyPressed(.c)) {
            show_config_overlay = !show_config_overlay;
        }

        h = rl.getScreenHeight();
        w = rl.getScreenWidth();

        const segment_x_step = @divTrunc(w, grid_segments);
        const segment_y_step = @divTrunc(h, grid_segments);

        const screen_center_x = @divTrunc(w, 2);
        const screen_center_y = @divTrunc(h, 2);

        const clock_center_x = screen_center_x;
        const clock_center_y = @divTrunc(512, 2);

        const inner_radius = 195;
        const outer_radius = 200;

        const minute_thickness = 2;
        const second_thickness = 2;

        const minute_hand = 150;
        const second_hand = outer_radius - 35;

        // const background_color = rl.Color.fromInt(0x181317FF);
        if (start_timer) {
            seconds_accum += deltaTime;

            // Check for lap completion using truncated division
            const lap_duration_seconds: f32 = @floatFromInt(lap_minutes * 60 + lap_seconds);
            const completed_laps = @as(i32, @intFromFloat(seconds_accum / lap_duration_seconds));
            if (completed_laps > current_lap and current_lap < total_laps) {
                current_lap = completed_laps;

                if (current_lap < total_laps) {
                    // Play checkpoint sound
                    if (sounds_loaded and !sounds_muted) {
                        rl.playSound(checkpoint_sound);
                    }
                } else {
                    // All laps completed - play finisher sound and trigger particles
                    if (sounds_loaded and !sounds_muted) {
                        rl.playSound(finisher_sound);
                    }
                    triggerParticles();
                    start_timer = false; // Stop timer
                }
            }
        }

        // Update particles
        if (particles_active) {
            updateParticles(deltaTime);
        }

        seconds_angle = (180 / 30.0) * seconds_accum + initial_angle;
        minutes_angle = (180 / 30.0) * (seconds_accum / 60) + initial_angle;

        // const second_hand = inner_radius - 10;
        //----------------------------------------------------------------------------------
        const clock_tick_angle_step = std.math.tau / 60.0;
        const clock_tick_relative_to_center = rl.Vector2.init(@floatFromInt(inner_radius - 17), 0.0);

        screen_center = rl.Vector2.init(@floatFromInt(screen_center_x), @floatFromInt(screen_center_y));
        screen_size = screen_center.scale(2.0);
        clock_center = rl.Vector2.init(@floatFromInt(clock_center_x), @floatFromInt(clock_center_y));

        {
            rl.beginDrawing();
            defer rl.endDrawing();
            rl.clearBackground(background_color);

            drawStars(.white);

            // tiny_ears(screen_center, outer_radius, ear_tip_height, cat_ears_step_dividor, .white);
            const left = rl.Vector2.init(0, -outer_radius + 5).rotate(clock_tick_angle_step * 3.2).add(clock_center);
            const top = rl.Vector2.init(0, -outer_radius).rotate(clock_tick_angle_step * 5).add(clock_center).add(rl.Vector2.init(ear_tip_x, ear_tip_y));
            const right = rl.Vector2.init(0, -outer_radius + 5).rotate(clock_tick_angle_step * 9).add(clock_center);

            drawEars(left, top, right, screen_center.x, edge_color);

            drawSmoothCircle(clock_center, outer_radius, edge_color);
            drawSmoothCircle(clock_center, inner_radius, background_color);

            drawClockTicks(60, clock_tick_relative_to_center, clock_center, clock_tick_angle_step);

            drawHand(clock_center, minute_thickness, minute_hand, minutes_angle, minute_color);
            drawHand(clock_center, second_thickness, second_hand, seconds_angle, second_color);

            var buffer: [20]u8 = undefined;
            const font_size = 56;
            const color = edge_color;

            const cologn_size = rl.measureText(":", font_size);
            rl.drawText(":", clock_center_x - @divTrunc(cologn_size, 2), clock_center_y + 50, font_size, color);

            const minutes_time = try std.fmt.bufPrintZ(&buffer, "{d:0>2.0} ", .{@divFloor(seconds_accum, 60.0)});
            const minutes_size = rl.measureText(minutes_time, font_size);
            rl.drawText(minutes_time, clock_center_x - @divFloor(cologn_size, 2) - minutes_size, clock_center_y + 50, font_size, color);

            const seconds_time = try std.fmt.bufPrintZ(&buffer, " {d:0>2.0}", .{@rem(seconds_accum, 60.0)});
            rl.drawText(seconds_time, clock_center_x + @divFloor(cologn_size, 2), clock_center_y + 50, font_size, color);

            const controls_tab_x: f32 = 50;
            const controls_tab_y: f32 = clock_center.y + outer_radius + 25;
            const edge_thickness = 5;
            const panel_thickness = 135;

            rl.drawRectangleRec(rl.Rectangle.init(controls_tab_x, controls_tab_y, screen_size.x - (controls_tab_x * 2), panel_thickness), edge_color);
            rl.drawRectangleRec(rl.Rectangle.init(controls_tab_x + edge_thickness, controls_tab_y + edge_thickness, screen_size.x - ((controls_tab_x + edge_thickness) * 2), panel_thickness - edge_thickness * 2), background_color);

            const content_x = controls_tab_x + edge_thickness + 20;
            const content_y = controls_tab_y + edge_thickness + 20;

            // Lap configuration controls
            const control_height = 25;
            const button_width = 20;
            const label_font_size = 20;

            // Total laps control
            rl.drawText("Total Laps", @intFromFloat(content_x), @intFromFloat(content_y), label_font_size, .white);
            if (rg.button(rl.Rectangle.init(content_x + 20 + 100, content_y - 3, button_width, control_height), "-")) {
                if (total_laps > 1) total_laps -= 1;
            }
            var laps_buffer: [10]u8 = undefined;
            const laps_text = try std.fmt.bufPrintZ(&laps_buffer, "{d: >2}", .{@as(u32, @intCast(total_laps))});
            rl.drawText(laps_text, @intFromFloat(content_x + 20 + 130), @intFromFloat(content_y), label_font_size, .white);
            if (rg.button(rl.Rectangle.init(content_x + 20 + 160, content_y - 3, button_width, control_height), "+")) {
                if (total_laps < 10) total_laps += 1;
            }

            // Lap duration - minutes
            rl.drawText("Minutes", @intFromFloat(content_x), @intFromFloat(content_y + 35), label_font_size, .white);
            if (rg.button(rl.Rectangle.init(content_x + 20 + 100, content_y + 32, button_width, control_height), "-")) {
                if (lap_minutes > 0) lap_minutes -= 1;
            }
            var minutes_buffer: [10]u8 = undefined;
            const minutes_text = try std.fmt.bufPrintZ(&minutes_buffer, "{d: >2}", .{@as(u32, @intCast(lap_minutes))});
            rl.drawText(minutes_text, @intFromFloat(content_x + 20 + 130), @intFromFloat(content_y + 35), label_font_size, .white);
            if (rg.button(rl.Rectangle.init(content_x + 20 + 160, content_y + 32, button_width, control_height), "+")) {
                if (lap_minutes < 59) lap_minutes += 1;
            }

            // Lap duration - seconds
            rl.drawText("Seconds", @intFromFloat(content_x), @intFromFloat(content_y + 70), label_font_size, .white);
            if (rg.button(rl.Rectangle.init(content_x + 20 + 100, content_y + 67, button_width, control_height), "-")) {
                if (lap_seconds > 0) lap_seconds -= 5;
            }
            var seconds_buffer: [10]u8 = undefined;
            const seconds_text = try std.fmt.bufPrintZ(&seconds_buffer, "{d: >2}", .{@as(u32, @intCast(lap_seconds))});
            rl.drawText(seconds_text, @intFromFloat(content_x + 20 + 130), @intFromFloat(content_y + 70), label_font_size, .white);
            if (rg.button(rl.Rectangle.init(content_x + 20 + 160, content_y + 67, button_width, control_height), "+")) {
                if (lap_seconds < 59) lap_seconds += 5;
            }

            // Current lap display
            var lap_buffer: [50]u8 = undefined;
            const lap_display = try std.fmt.bufPrintZ(&lap_buffer, "Lap: {d}/{d}", .{ current_lap, total_laps });
            rl.drawText(lap_display, @intFromFloat(content_x + 245), @intFromFloat(content_y + 10), 20, edge_color);

            const button_w = 50;
            const button_h = 30;
            const button_spacing = 15;

            // Position buttons under the lap display, centered
            const buttons_x = content_x + 235;
            const buttons_start_y = content_y + 45;

            const start_pause_button_rect = rl.Rectangle.init(buttons_x, buttons_start_y, button_w, button_h);
            const reset_button_rect = rl.Rectangle.init(buttons_x + button_w + button_spacing, buttons_start_y, button_w, button_h);

            renderStartPauseControl(start_pause_button_rect);
            renderResetControl(reset_button_rect);

            // Config button in top right corner
            const config_button_size = 30;
            const config_button_rect = rl.Rectangle.init(@floatFromInt(w - config_button_size - 10), 10, config_button_size, config_button_size);
            if (rg.button(config_button_rect, rg.iconText(@intFromEnum(rg.IconName.gear), ""))) {
                show_config_overlay = !show_config_overlay;
            }

            // Config overlay
            if (show_config_overlay) {
                renderConfigOverlay();
            }

            //----------------------------------------------------------------------------------

            // Draw particles on top of everything
            if (particles_active) {
                drawParticles();
            }

            if (grid_lines) {
                const segments: usize = @intCast(grid_segments);
                for (0..(segments + 1)) |step| {
                    const stepi: i32 = @intCast(step);
                    rl.drawLine(0, stepi * segment_y_step, w, stepi * segment_y_step, color);
                    rl.drawLine(stepi * segment_x_step, 0, stepi * segment_x_step, h, color);
                }

                rl.drawFPS(10, 10);
            }
        }
    }
}

fn drawClockTicks(
    tick_count: usize,
    clock_tick_relative_to_center: rl.Vector2,
    center: rl.Vector2,
    step_angle: f32,
) void {
    for (0..tick_count) |step| {
        const stepf: f32 = @floatFromInt(step);

        const tick_position = clock_tick_relative_to_center.rotate(stepf * step_angle).add(center);

        const radius: f32 = if (@rem(stepf, 5.0) == 0) 5 else 3;
        rl.drawCircleV(tick_position, radius, .purple);
    }
}

fn drawHand(center: rl.Vector2, half_thickness: f32, height: f32, angle: f32, color: rl.Color) void {
    const hand_rect = rl.Rectangle.init(center.x, center.y, half_thickness * 2, height);
    rl.drawRectanglePro(hand_rect, rl.Vector2.init(half_thickness, half_thickness), angle, color);

    // Heart position at the tip
    const tip = rl.Vector2.init(0, height).rotate(std.math.degreesToRadians(angle)).add(center);
    drawHeart(tip, 15.0, angle, color); // 20.0 = heart size}
}

fn drawHeart(center: rl.Vector2, size: f32, angle_deg: f32, color: rl.Color) void {
    const steps: usize = 40; // smoothness
    var points: [steps]rl.Vector2 = undefined;

    // Create points in local space
    for (0..steps) |i| {
        const t = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps))) * std.math.tau;
        var x = 16.0 * std.math.pow(f32, std.math.sin(t), 3);
        var y = 13.0 * std.math.cos(t) - 5.0 * std.math.cos(2.0 * t) - 2.0 * std.math.cos(3.0 * t) - std.math.cos(4.0 * t);

        // scale and flip Y (since screen coords increase downward)
        x *= -size * 0.05;
        y *= -size * 0.05;

        // rotate
        const angle_rad = std.math.degreesToRadians(angle_deg);
        const xr = x * std.math.cos(angle_rad) - y * std.math.sin(angle_rad);
        const yr = x * std.math.sin(angle_rad) + y * std.math.cos(angle_rad);

        points[i] = rl.Vector2.init(center.x + xr, center.y + yr);
    }

    // Draw as triangle fan
    rl.drawLineStrip(&points, color);
    rl.drawTriangleFan(&points, color);
}

fn drawSmoothCircle(center: rl.Vector2, radius: f32, color: rl.Color) void {
    const segments: usize = 128; // Higher number = smoother circle
    var points: [segments + 2]rl.Vector2 = undefined;

    // Center point for triangle fan
    points[0] = center;

    // Generate points around the circumference
    const angle_step = std.math.tau / @as(f32, @floatFromInt(segments));
    for (0..segments) |i| {
        const angle = angle_step * @as(f32, @floatFromInt(i));
        const point = rl.Vector2.init(radius, 0).rotate(-angle);
        points[i + 1] = point.add(center);
    }

    // Close the circle by connecting back to first point
    points[segments + 1] = points[1];

    // Draw filled circle
    rl.drawTriangleFan(&points, color);
}

fn drawStars(color: rl.Color) void {
    // Create a PRNG
    var rng = std.Random.DefaultPrng.init(0);
    const rand = rng.random();

    const size_x: i32 = @intFromFloat(screen_size.x);
    const size_y: i32 = @intFromFloat(screen_size.y);

    const segments = 15;
    const step_x: i32 = @divTrunc(size_x, segments);
    const step_y: i32 = @divTrunc(size_y, segments);

    for (0..segments + 1) |i| {
        for (0..segments + 1) |j| {
            const x = step_x * @as(i32, @intCast(i)) + rand.intRangeAtMost(i32, -10, 10);
            const y = step_y * @as(i32, @intCast(j)) + rand.intRangeAtMost(i32, -10, 10);
            rl.drawCircle(x, y, 1.5 * rand.float(f32), color);
        }
    }
}

var left_control_offset = rl.Vector2.init(0.156, 0.626);
var left_top_control_offset = rl.Vector2.init(0.68, 1.009);

var right_control_offset = rl.Vector2.init(-0.074, -0.528);
var right_top_control_offset = rl.Vector2.init(-0.487, -0.925);

var mouse = rl.Vector2.init(0, 0);
var selected_point: enum { left, left_top, right_top, right, none } = .none;

fn drawEars(left: rl.Vector2, top: rl.Vector2, right: rl.Vector2, center_x: f32, color: rl.Color) void {

    // Left curve: left -> top
    const left_top_scale = top.subtract(left);
    const left_control_point = left_control_offset.multiply(left_top_scale).add(left); // push upward more
    const left_top_control_point = left_top_control_offset.multiply(left_top_scale).add(left); // pull outwards

    const ear_p1: [4]rl.Vector2 = .{
        left,
        left_control_point,
        left_top_control_point,
        top,
    };

    // Right curve: top -> right
    const right_top_scale = right.subtract(top);
    const right_control_point = right_control_offset.multiply(right_top_scale).add(right); // wider outward
    const right_top_control_point = right_top_control_offset.multiply(right_top_scale).add(right); // push downward slightly

    const ear_p2: [4]rl.Vector2 = .{
        top,
        right_top_control_point,
        right_control_point,
        right,
    };

    rl.drawSplineBezierCubic(&ear_p1, 5, color);
    rl.drawSplineBezierCubic(&ear_p2, 5, color);

    const ear_p1_reflected: [4]rl.Vector2 = .{
        rl.Vector2{ .x = 2 * center_x - ear_p1[0].x, .y = ear_p1[0].y },
        rl.Vector2{ .x = 2 * center_x - ear_p1[1].x, .y = ear_p1[1].y },
        rl.Vector2{ .x = 2 * center_x - ear_p1[2].x, .y = ear_p1[2].y },
        rl.Vector2{ .x = 2 * center_x - ear_p1[3].x, .y = ear_p1[3].y },
    };

    const ear_p2_reflected: [4]rl.Vector2 = .{
        rl.Vector2{ .x = 2 * center_x - ear_p2[0].x, .y = ear_p2[0].y },
        rl.Vector2{ .x = 2 * center_x - ear_p2[1].x, .y = ear_p2[1].y },
        rl.Vector2{ .x = 2 * center_x - ear_p2[2].x, .y = ear_p2[2].y },
        rl.Vector2{ .x = 2 * center_x - ear_p2[3].x, .y = ear_p2[3].y },
    };

    rl.drawSplineBezierCubic(&ear_p1_reflected, 5, color);
    rl.drawSplineBezierCubic(&ear_p2_reflected, 5, color);

    // fixed points in red, control in blue and a line to handle them
    rl.drawCircleV(ear_p1[0], 2.5, color);
    rl.drawCircleV(ear_p1[3], 2.5, color);
    rl.drawCircleV(ear_p2[3], 2.5, color);

    rl.drawCircleV(ear_p1_reflected[0], 2.5, color);
    rl.drawCircleV(ear_p1_reflected[3], 2.5, color);
    rl.drawCircleV(ear_p2_reflected[3], 2.5, color);

    if (spline_dots) {
        rl.drawCircleV(left, 5, .red);
        rl.drawCircleV(top, 5, .red);
        rl.drawCircleV(right, 5, .red);

        rl.drawCircleV(left_control_point, 5, .blue);
        rl.drawCircleV(left_top_control_point, 5, .blue);
        rl.drawCircleV(right_top_control_point, 5, .blue);
        rl.drawCircleV(right_control_point, 5, .blue);

        //====
        mouse = rl.getMousePosition();

        if (rl.isMouseButtonUp(.left)) {
            selected_point = .none;
        }

        selected_point = if (selected_point == .none and rl.isMouseButtonDown(.left)) point: {
            if (rl.checkCollisionPointCircle(mouse, left_control_point, 5)) break :point .left;
            if (rl.checkCollisionPointCircle(mouse, left_top_control_point, 5)) break :point .left_top;
            if (rl.checkCollisionPointCircle(mouse, right_control_point, 5)) break :point .right;
            if (rl.checkCollisionPointCircle(mouse, right_top_control_point, 5)) break :point .right_top;

            break :point .none;
        } else selected_point;

        if (selected_point != .none) {
            std.log.debug("Point taken {s}", .{@tagName(selected_point)});
        }

        switch (selected_point) {
            .left => {
                left_control_offset = mouse.subtract(left).divide(left_top_scale);
                std.log.debug("{} {}", .{ left_control_offset.x, left_control_offset.y });
            },
            .left_top => {
                left_top_control_offset = mouse.subtract(left).divide(left_top_scale);
            },
            .right_top => {
                right_top_control_offset = mouse.subtract(right).divide(right_top_scale);
            },
            .right => {
                right_control_offset = mouse.subtract(right).divide(right_top_scale);
            },
            .none => {},
        }

        if (rl.isKeyPressed(.p)) {
            std.log.debug("height: {d}, {d}", .{ ear_tip_x, ear_tip_y });
            std.log.debug("left: {d}, {d}", .{ left_control_offset.x, left_control_offset.y });
            std.log.debug("left_top: {d} {d}", .{ left_top_control_offset.x, left_top_control_offset.y });
            std.log.debug("right_top: {d} {d}", .{ right_top_control_offset.x, right_top_control_offset.y });
            std.log.debug("right: {d} {d}", .{ right_control_offset.x, right_control_offset.y });
        }
        //====
    }
}

fn tiny_ears(radius: f32, ear_tip_height: f32, angle_divider: f32, color: rl.Color) void {
    rl.drawLineBezier(
        rl.Vector2.init(0.0, 10.0).add(clock_center),
        rl.Vector2.init(ear_tip_height, 0.0).rotate(-4 * (std.math.pi / angle_divider) - (std.math.pi / 2.0)).add(clock_center),
        5,
        color,
    );

    rl.drawLineBezier(
        rl.Vector2.init(ear_tip_height, 0.0).rotate(-4 * (std.math.pi / angle_divider) - (std.math.pi / 2.0)).add(clock_center),
        rl.Vector2.init(-radius, 0.0).add(clock_center),
        5,
        color,
    );

    rl.drawLineBezier(
        rl.Vector2.init(0.0, -10.0).add(clock_center),
        rl.Vector2.init(ear_tip_height, 0.0).rotate(4 * (std.math.pi / angle_divider) - (std.math.pi / 2.0)).add(clock_center),
        5,
        color,
    );

    rl.drawLineBezier(
        rl.Vector2.init(ear_tip_height, 0.0).rotate(4 * (std.math.pi / angle_divider) - (std.math.pi / 2.0)).add(clock_center),
        rl.Vector2.init(radius, 0.0).add(clock_center),
        5,
        color,
    );
}

fn renderStartPauseControl(rect: rl.Rectangle) void {
    if (start_timer) {
        if (rg.button(rect, rg.iconText(@intFromEnum(rg.IconName.player_pause), ""))) {
            start_timer = !start_timer;
        }
    } else {
        if (rg.button(rect, rg.iconText(@intFromEnum(rg.IconName.player_play), ""))) {
            start_timer = !start_timer;
        }
    }
}

fn renderResetControl(rect: rl.Rectangle) void {
    if (rg.button(rect, rg.iconText(@intFromEnum(rg.IconName.restart), ""))) {
        // Reset timer and laps
        seconds_accum = 0;
        current_lap = 0;
        start_timer = false;
        particles_active = false;
    }
}

fn getConfigPath() []const u8 {
    const home_path = std.process.getEnvVarOwned(std.heap.c_allocator, "HOME") catch return ".clockrc";
    defer std.heap.c_allocator.free(home_path);

    const config_path = std.fmt.bufPrint(&config_path_buffer, "{s}/.clockrc", .{home_path}) catch return ".clockrc";
    return config_path;
}

fn saveConfig() void {
    const config_path = getConfigPath();
    const file = std.fs.cwd().createFile(config_path, .{}) catch |err| {
        std.log.warn("Failed to create config file '{s}': {}", .{ config_path, err });
        return;
    };
    defer file.close();

    const writer = file.writer();
    writer.print("sounds_muted={}\n", .{sounds_muted}) catch |err| {
        std.log.warn("Failed to write config: {}", .{err});
    };
}

fn loadConfig() void {
    const config_path = getConfigPath();
    const file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
        std.log.info("Config file not found '{s}', using defaults: {}", .{ config_path, err });
        return;
    };
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line_buf: [256]u8 = undefined;
    while (reader.readUntilDelimiterOrEof(line_buf[0..], '\n') catch null) |line| {
        if (std.mem.startsWith(u8, line, "sounds_muted=")) {
            const value = line[13..];
            sounds_muted = std.mem.eql(u8, value, "true");
        }
    }
}

fn renderConfigOverlay() void {
    // Semi-transparent background
    const overlay_bg = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 180 };
    rl.drawRectangle(0, 0, w, h, overlay_bg);

    // Config panel
    const panel_width = 300;
    const panel_height = 150;
    const panel_x = @divFloor(w - panel_width, 2);
    const panel_y = @divFloor(h - panel_height, 2);

    const panel_rect = rl.Rectangle.init(@floatFromInt(panel_x), @floatFromInt(panel_y), panel_width, panel_height);
    rl.drawRectangleRec(panel_rect, edge_color);
    rl.drawRectangleRec(rl.Rectangle.init(@floatFromInt(panel_x + 5), @floatFromInt(panel_y + 5), panel_width - 10, panel_height - 10), background_color);

    // Config title
    const title = "Configuration";
    const title_size = rl.measureText(title, 24);
    rl.drawText(title, panel_x + @divFloor(panel_width - title_size, 2), panel_y + 20, 24, edge_color);

    // Sound mute checkbox
    const checkbox_size = 20;
    const checkbox_y = panel_y + 60;
    const checkbox_rect = rl.Rectangle.init(@floatFromInt(panel_x + 30), @floatFromInt(checkbox_y), checkbox_size, checkbox_size);

    if (rg.checkBox(checkbox_rect, "", &sounds_muted)) {
        // Checkbox was toggled, save config
        saveConfig();
    }

    rl.drawText("Mute Sounds", panel_x + 60, checkbox_y + 2, 18, .white);

    // Close button
    const close_button_width = 80;
    const close_button_height = 25;
    const close_button_rect = rl.Rectangle.init(@floatFromInt(panel_x + panel_width - close_button_width - 20), @floatFromInt(panel_y + panel_height - close_button_height - 20), close_button_width, close_button_height);

    if (rg.button(close_button_rect, "Close")) {
        show_config_overlay = false;
    }
}

pub fn setupCatTimerStyle() void {
    // Default control properties
    rg.setStyle(.default, .{ .control = .border_color_normal }, edge_color.toInt());
    rg.setStyle(.default, .{ .control = .base_color_normal }, background_color.toInt());
    rg.setStyle(.default, .{ .control = .text_color_normal }, text_color.toInt());
    rg.setStyle(.default, .{ .control = .border_width }, 2);

    // Button styling
    rg.setStyle(.button, .{ .control = .border_color_normal }, edge_color.toInt());
    rg.setStyle(.button, .{ .control = .base_color_normal }, background_color.toInt());
    rg.setStyle(.button, .{ .control = .text_color_normal }, text_color.toInt());

    // Hover states - slightly brighter pink
    const hover_edge = rl.Color{ .r = 255, .g = 130, .b = 200, .a = 255 };
    const hover_bg = rl.Color{ .r = 35, .g = 35, .b = 45, .a = 255 };

    rg.setStyle(.button, .{ .control = .border_color_focused }, hover_edge.toInt());
    rg.setStyle(.button, .{ .control = .base_color_focused }, hover_bg.toInt());

    // Pressed states
    const pressed_edge = rl.Color{ .r = 200, .g = 80, .b = 150, .a = 255 };
    const pressed_bg = rl.Color{ .r = 45, .g = 25, .b = 55, .a = 255 };

    rg.setStyle(.button, .{ .control = .border_color_pressed }, pressed_edge.toInt());
    rg.setStyle(.button, .{ .control = .base_color_pressed }, pressed_bg.toInt());

    // Label styling
    rg.setStyle(.label, .{ .control = .text_color_normal }, text_color.toInt());

    // TextBox styling (if you have input fields)
    rg.setStyle(.textbox, .{ .control = .border_color_normal }, edge_color.toInt());
    rg.setStyle(.textbox, .{ .control = .base_color_normal }, background_color.toInt());
    rg.setStyle(.textbox, .{ .control = .text_color_normal }, text_color.toInt());

    // Slider styling
    rg.setStyle(.slider, .{ .control = .border_color_normal }, edge_color.toInt());
    rg.setStyle(.slider, .{ .control = .base_color_normal }, background_color.toInt());

    // Checkbox styling
    rg.setStyle(.checkbox, .{ .control = .border_color_normal }, edge_color.toInt());
    rg.setStyle(.checkbox, .{ .control = .base_color_normal }, background_color.toInt());
    rg.setStyle(.checkbox, .{ .control = .text_color_normal }, text_color.toInt());

    // DropdownBox styling
    rg.setStyle(.dropdownbox, .{ .control = .border_color_normal }, edge_color.toInt());
    rg.setStyle(.dropdownbox, .{ .control = .base_color_normal }, background_color.toInt());
    rg.setStyle(.dropdownbox, .{ .control = .text_color_normal }, text_color.toInt());

    // ListView styling
    rg.setStyle(.listview, .{ .control = .border_color_normal }, edge_color.toInt());
    rg.setStyle(.listview, .{ .control = .base_color_normal }, background_color.toInt());
    rg.setStyle(.listview, .{ .control = .text_color_normal }, text_color.toInt());

    // Set global text size and font
    rg.setStyle(.default, .{ .default = .text_size }, 20);
}

fn initParticles() void {
    for (0..MAX_PARTICLES) |i| {
        particles[i] = Particle{
            .position = rl.Vector2.init(0, 0),
            .velocity = rl.Vector2.init(0, 0),
            .life = 0,
            .size = 0,
            .color = rl.Color.init(255, 20, 147, 0), // Deep pink
        };
    }
}

fn triggerParticles() void {
    particles_active = true;
    particle_timer = 3.0; // Particles last 3 seconds

    // Create a PRNG for particle randomization
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const rand = rng.random();

    const neon_pink = rl.Color.init(255, 20, 147, 255);
    const bright_pink = rl.Color.init(255, 105, 180, 255);
    const magenta = rl.Color.init(255, 0, 255, 255);

    for (0..MAX_PARTICLES) |i| {
        const angle = rand.float(f32) * std.math.tau;
        const speed = 100 + rand.float(f32) * 200;

        particles[i] = Particle{
            .position = clock_center,
            .velocity = rl.Vector2.init(@cos(angle) * speed, @sin(angle) * speed),
            .life = 2.0 + rand.float(f32), // 2-3 seconds life
            .size = 3 + rand.float(f32) * 4, // 3-7 pixel size
            .color = if (rand.float(f32) < 0.33) neon_pink else if (rand.float(f32) < 0.67) bright_pink else magenta,
        };
    }
}

fn updateParticles(deltaTime: f32) void {
    particle_timer -= deltaTime;
    if (particle_timer <= 0) {
        particles_active = false;
        return;
    }

    for (0..MAX_PARTICLES) |i| {
        if (particles[i].life > 0) {
            particles[i].position = particles[i].position.add(particles[i].velocity.scale(deltaTime));
            particles[i].velocity = particles[i].velocity.scale(0.98); // Slight drag
            particles[i].life -= deltaTime;

            particles[i].life = @max(0.0, particles[i].life);

            // Fade out alpha based on remaining life
            const life_ratio = particles[i].life / 3.0;
            particles[i].color.a = @intFromFloat(255.0 * life_ratio);
        }
    }
}

fn drawParticles() void {
    for (0..MAX_PARTICLES) |i| {
        if (particles[i].life > 0) {
            rl.drawCircleV(particles[i].position, particles[i].size, particles[i].color);
        }
    }
}
