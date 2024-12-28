const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});
const Chip8 = @import("chip8.zig");
const GRAPHIC_HEIGHT = Chip8.GRAPHIC_HEIGHT;
const GRAPHIC_WIDTH = Chip8.GRAPHIC_WIDTH;

const KEYMAP: [16]c_int = [_]c_int{
    sdl.SDL_SCANCODE_X,
    sdl.SDL_SCANCODE_1,
    sdl.SDL_SCANCODE_2,
    sdl.SDL_SCANCODE_3,
    sdl.SDL_SCANCODE_Q,
    sdl.SDL_SCANCODE_W,
    sdl.SDL_SCANCODE_E,
    sdl.SDL_SCANCODE_A,
    sdl.SDL_SCANCODE_S,
    sdl.SDL_SCANCODE_D,
    sdl.SDL_SCANCODE_Z,
    sdl.SDL_SCANCODE_C,
    sdl.SDL_SCANCODE_4,
    sdl.SDL_SCANCODE_R,
    sdl.SDL_SCANCODE_F,
    sdl.SDL_SCANCODE_V,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var arg_it = try std.process.argsWithAllocator(allocator);
    // We skip the first argument since it's
    // the current executable file path
    _ = arg_it.skip();

    const filename = arg_it.next() orelse {
        std.debug.print("No ROM added!", .{});
        return;
    };

    var cpu = try Chip8.init();
    const sdl_context = try SdlContext.init();
    defer sdl_context.deinit();

    // Load ROM into cpu
    try cpu.load_rom(filename);

    var live = true;
    while (live) {
        // Emulator cycle
        cpu.cycle();

        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    live = false;
                },
                sdl.SDL_KEYDOWN => {
                    for (0..16) |i| {
                        if (event.key.keysym.scancode == KEYMAP[i]) {
                            cpu.keys[i] = 1;
                        }
                    }
                },
                sdl.SDL_KEYUP => {
                    for (0..16) |i| {
                        if (event.key.keysym.scancode == KEYMAP[i]) {
                            cpu.keys[i] = 0;
                        }
                    }
                },
                else => {},
            }
        }

        sdl_context.tick(&cpu);
    }
}

pub const SdlContext = struct {
    window: *sdl.SDL_Window,
    renderer: *sdl.SDL_Renderer,
    texture: *sdl.SDL_Texture,

    const Self = @This();
    pub fn init() !Self {
        const window = sdl.SDL_CreateWindow("Chip8-zig", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, 1024, 512, sdl.SDL_WINDOW_OPENGL) orelse
            {
            sdl.SDL_Log("Unable to create window: %s", sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        const renderer = sdl.SDL_CreateRenderer(window, -1, 0) orelse {
            sdl.SDL_Log("Unable to create renderer: %s", sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        const texture = sdl.SDL_CreateTexture(renderer, sdl.SDL_PIXELFORMAT_RGB888, sdl.SDL_TEXTUREACCESS_STREAMING, GRAPHIC_WIDTH, GRAPHIC_HEIGHT) orelse {
            sdl.SDL_Log("Unable to create texture: %s", sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        return Self{ .window = window, .renderer = renderer, .texture = texture };
    }

    // Deinit in reverse order of init
    pub fn deinit(self: *const Self) void {
        sdl.SDL_DestroyTexture(self.texture);
        sdl.SDL_DestroyRenderer(self.renderer);
        sdl.SDL_DestroyWindow(self.window);
        sdl.SDL_Quit();
    }

    // tick rate of 16ms for 60fps
    const TICK_RATE_MS: usize = 400 / 1000;
    pub fn tick(self: *const Self, cpu: *const Chip8) void {
        _ = sdl.SDL_RenderClear(self.renderer);

        // Build texture
        var bytes: ?[*]u32 = null;
        var pitch: c_int = 0;
        _ = sdl.SDL_LockTexture(self.texture, null, @ptrCast(&bytes), &pitch);

        var y: usize = 0;
        while (y < GRAPHIC_HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < GRAPHIC_WIDTH) : (x += 1) {
                // Graphic pixels are stored row by row in a single array
                bytes.?[y * GRAPHIC_WIDTH + x] = if (cpu.graphics[y * GRAPHIC_WIDTH + x] == 1) 0xFFFFFFFF else 0x000000FF;
            }
        }
        sdl.SDL_UnlockTexture(self.texture);

        _ = sdl.SDL_RenderCopy(self.renderer, self.texture, null, null);
        sdl.SDL_RenderPresent(self.renderer);

        sdl.SDL_Delay(TICK_RATE_MS);
    }
};
