const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});
const Chip8 = @import("chip8.zig");

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
        const texture = sdl.SDL_CreateTexture(renderer, sdl.SDL_PIXELFORMAT_RGB888, sdl.SDL_TEXTUREACCESS_STREAMING, 64, 32) orelse {
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
    const TICK_RATE_MS: usize = 16 * 1000 * 1000;
    pub fn tick(self: *const Self, cpu: *const Chip8) void {
        _ = sdl.SDL_RenderClear(self.renderer);

        // Build texture
        var bytes: ?[*]u32 = null;
        var pitch: c_int = 0;
        _ = sdl.SDL_LockTexture(self.texture, null, @ptrCast(&bytes), &pitch);

        var y: usize = 0;
        while (y < 32) : (y += 1) {
            var x: usize = 0;
            while (x < 64) : (x += 1) {
                bytes.?[y * 64 + x] = if (cpu.graphics[y * 64 + x] == 1) 0xFFFFFFFF else 0x000000FF;
            }
        }
        sdl.SDL_UnlockTexture(self.texture);

        _ = sdl.SDL_RenderCopy(self.renderer, self.texture, null, null);
        sdl.SDL_RenderPresent(self.renderer);

        std.time.sleep(12 * 1000 * 1000 * 1);
        // sdl.SDL_Delay(TICK_RATE_MS);
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var arg_it = try std.process.argsWithAllocator(allocator);

    _ = arg_it.skip();

    const filename = arg_it.next() orelse {
        std.debug.print("No ROM added!", .{});
        return;
    };

    var cpu = try Chip8.init();
    const sdl_context = try SdlContext.init();

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
                else => {},
            }
        }

        sdl_context.tick(&cpu);
    }
}
