const rl = @import("raylib");
const std = @import("std");

var grid_lines = false;
var grid_segments: i32 = 8;

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 512;
    const screenHeight = 512;

    rl.setConfigFlags(.{ .window_transparent = true });

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    var angle: f32 = 180;
    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        const deltaTime = rl.getFrameTime();

        if (rl.isKeyPressed(.g)) {
            grid_lines = !grid_lines;
        }

        if (rl.isKeyPressed(.kp_subtract)) {
            grid_segments -= 1;
        }

        if (rl.isKeyPressed(.kp_add)) {
            grid_segments += 1;
        }

        const h = rl.getScreenHeight();
        const w = rl.getScreenWidth();

        const segment_x_step = @divTrunc(w, grid_segments);
        const segment_y_step = @divTrunc(h, grid_segments);

        const screen_center_x = @divTrunc(w, 2);
        const screen_center_y = @divTrunc(h, 2);

        const inner_radius = 195;
        const outer_radius = 200;

        const minute_thickness = 4;
        const second_thickness = minute_thickness - 2;

        const minute_hand = 150;
        const second_hand = 190;

        const minute_color: rl.Color = .red;
        const second_color: rl.Color = .white;

        angle += 10 * std.math.pi * deltaTime;
        // const second_hand = inner_radius - 10;
        //----------------------------------------------------------------------------------
        {
            rl.beginDrawing();
            defer rl.endDrawing();
            rl.clearBackground(rl.Color.blank);
            rl.drawCircle(screen_center_x, screen_center_y, outer_radius, .pink);
            rl.drawCircle(screen_center_x, screen_center_y, inner_radius, .black);

            const minute_rect = rl.Rectangle.init(@floatFromInt(screen_center_x), @floatFromInt(screen_center_y), @floatFromInt(minute_thickness * 2), @floatFromInt(minute_hand));
            const second_rect = rl.Rectangle.init(@floatFromInt(screen_center_x), @floatFromInt(screen_center_y), @floatFromInt(second_thickness * 2), @floatFromInt(second_hand));

            rl.drawRectanglePro(minute_rect, rl.Vector2.init(minute_thickness, minute_thickness), angle, minute_color);
            rl.drawRectanglePro(second_rect, rl.Vector2.init(second_thickness, second_thickness), -angle, second_color);

            if (grid_lines) {
                const segments: usize = @intCast(grid_segments);
                for (0..(segments + 1)) |step| {
                    const stepi: i32 = @intCast(step);
                    rl.drawLine(0, stepi * segment_y_step, w, stepi * segment_y_step, .red);
                    rl.drawLine(stepi * segment_x_step, 0, stepi * segment_x_step, h, .red);
                }
            }
        }

        //----------------------------------------------------------------------------------
    }
}
