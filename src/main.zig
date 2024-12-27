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
    // allocator: Allocator,

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
    pub fn tick(self: *const Self) void {
        _ = sdl.SDL_RenderClear(self.renderer);

        // Build texture

        _ = sdl.SDL_RenderCopy(self.renderer, self.texture, null, null);

        sdl.SDL_RenderPresent(self.renderer);
        sdl.SDL_Delay(TICK_RATE_MS);
    }
};

pub fn main() !void {
    // const allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const sdl_context = try SdlContext.init();
    defer sdl_context.deinit();

    // Init chip8 cpu
    // const cpu = try Chip8.init();

    // Load ROM into cpu

    var live = true;

    while (live) {
        // Emulator cycle
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    live = false;
                },
                else => {},
            }
        }

        sdl_context.tick();
    }
}
