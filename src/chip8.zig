const std = @import("std");
const Allocator = std.mem.Allocator;
const time = std.time;

/// Opcode
const OpCodeTag = @import("opcode.zig").OpCodeTag;
const OpCode = @import("opcode.zig").OpCode;

/// Constants
pub const GRAPHIC_HEIGHT = 32;
pub const GRAPHIC_WIDTH = 64;
pub const MEMORY_SIZE = 4096;
const FONTSET = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

/// Registers, memory
program_counter: u16,

opcode: u16,

/// Memory Map
///
/// 0x000-0x1FF - Interpreter
///     0x050-0x0A0 - Used for 4x5 pixel font set
/// 0x200-0xFFF - Program ROM & Working RAM
memory: [MEMORY_SIZE]u8,

/// Graphics
/// 64 x 32 array of monochrome
///
/// Pixel positions are stored row by row
/// in a single array, (32 rows of width 64)
graphics: [GRAPHIC_WIDTH * GRAPHIC_HEIGHT]u8,

/// 16 Registers V0-VF
registers: [16]u8,

index: u16,

/// Timers
delay_timer: u8,
sound_timer: u8,

/// Stack
stack: [16]u16,
stack_pointer: u16,

/// Input keys
keys: [16]u8,

random: *const std.Random,

const Self = @This();
pub fn init() !Self {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    var memory: [MEMORY_SIZE]u8 = std.mem.zeroes([MEMORY_SIZE]u8);
    for (FONTSET, 0..) |font, i| {
        memory[i] = font;
    }

    return Self{
        .program_counter = 0x200,
        .opcode = 0x00,
        .memory = memory,
        .graphics = std.mem.zeroes([GRAPHIC_HEIGHT * GRAPHIC_WIDTH]u8),
        .registers = std.mem.zeroes([16]u8),
        .index = 0x00,
        .delay_timer = 0,
        .sound_timer = 0,
        .stack = std.mem.zeroes([16]u16),
        .stack_pointer = 0x00,
        .keys = std.mem.zeroes([16]u8),
        .random = &prng.random(),
    };
}

pub fn increment_program_counter(self: *Self) void {
    self.program_counter += 2;
}

pub fn load_rom(self: *Self, filename: []const u8) !void {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const stat = try file.stat();
    const size = stat.size;
    std.debug.print("ROM file {s} of size: {d}\n", .{ filename, size });

    const reader = file.reader();
    var i: usize = 0;
    while (i < size) : (i += 1) {
        self.memory[i + 0x200] = try reader.readByte();
    }
}

fn fetch_opcode(self: *Self) u16 {
    const first = self.memory[self.program_counter];
    const second = self.memory[self.program_counter + 1];
    return @truncate(@as(u16, first) << 8 | second);
}

/// Emulate a single Fetch-Decode-Execute cpu cycle
pub fn cycle(self: *Self) void {
    // Fetch
    self.opcode = self.fetch_opcode();

    // Decode
    const decoded_opt = OpCode.decode(self.opcode);

    // Skip skipped opcode
    if (decoded_opt == null) {
        self.increment_program_counter();
        return;
    }

    // Execute
    const decoded = decoded_opt.?;
    switch (decoded) {
        .@"00E0" => {
            self.graphics = std.mem.zeroes([GRAPHIC_HEIGHT * GRAPHIC_WIDTH]u8);
        },

        .@"00EE" => {
            self.stack_pointer -= 1;
            self.program_counter = self.stack[self.stack_pointer];
        },

        .@"1NNN" => |parsed| {
            self.program_counter = parsed.address;
            return;
        },

        .@"2NNN" => |parsed| {
            self.stack[self.stack_pointer] = self.program_counter;
            self.stack_pointer += 1;
            self.program_counter = parsed.address;
            return;
        },

        .@"3XNN" => |parsed| {
            const reg_data = self.registers[parsed.register];
            if (reg_data == parsed.data) {
                self.increment_program_counter();
            }
        },

        .@"4XNN" => |parsed| {
            const reg_data = self.registers[parsed.register];
            if (reg_data != parsed.data) {
                self.increment_program_counter();
            }
        },

        .@"5XY0" => |parsed| {
            const first_reg_data = self.registers[parsed.first];
            const second_reg_data = self.registers[parsed.second];
            if (first_reg_data == second_reg_data) {
                self.increment_program_counter();
            }
        },

        .@"6XNN" => |parsed| {
            self.registers[parsed.register] = parsed.data;
        },

        .@"7XNN" => |parsed| {
            const sum = @addWithOverflow(self.registers[parsed.register], parsed.data);
            self.registers[parsed.register] = sum[0];
        },

        .@"8XY0" => |parsed| {
            self.registers[parsed.first] = self.registers[parsed.second];
        },

        .@"8XY1" => |parsed| {
            self.registers[parsed.first] |= self.registers[parsed.second];
        },

        .@"8XY2" => |parsed| {
            self.registers[parsed.first] &= self.registers[parsed.second];
        },

        .@"8XY3" => |parsed| {
            self.registers[parsed.first] ^= self.registers[parsed.second];
        },

        .@"8XY4" => |parsed| {
            const res = @addWithOverflow(self.registers[parsed.first], self.registers[parsed.second]);
            self.registers[parsed.first] = res[0];
            self.registers[0xF] = res[1];
        },

        .@"8XY5" => |parsed| {
            const first = self.registers[parsed.first];
            const second = self.registers[parsed.second];
            const res = @subWithOverflow(first, second);
            self.registers[parsed.first] = res[0];
            const bit: u1 = if (second >= first) 1 else 0;
            self.registers[0xF] = bit;
        },

        .@"8XY6" => |parsed| {
            const reg = self.registers[parsed.register];
            const lsb: u1 = @truncate(reg & 1);
            self.registers[parsed.register] = (reg >> 1);
            self.registers[0xF] = lsb;
        },

        .@"8XY7" => |parsed| {
            const first = self.registers[parsed.first];
            const second = self.registers[parsed.second];
            const res = @subWithOverflow(second, first);
            self.registers[parsed.first] = res[0];
            const bit: u1 = if (first >= second) 1 else 0;
            self.registers[0xF] = bit;
        },

        .@"8XYE" => |parsed| {
            const reg = self.registers[parsed.register];
            const msb: u8 = (reg & 0x80) >> 7;
            self.registers[parsed.register] = (reg << 1);
            self.registers[0xF] = msb;
        },

        .@"9XY0" => |parsed| {
            const first_reg_data = self.registers[parsed.first];
            const second_reg_data = self.registers[parsed.second];
            if (first_reg_data != second_reg_data) {
                self.increment_program_counter();
            }
        },

        .ANNN => |parsed| {
            self.index = parsed.address;
        },

        .BNNN => |parsed| {
            self.program_counter = @as(u16, self.registers[0]) + parsed.address;
            return;
        },

        .CXNN => |parsed| {
            const random = self.random.intRangeAtMost(u8, 0, 255);
            self.registers[parsed.register] = (random & parsed.data);
        },

        .DXYN => |parsed| {
            self.registers[0xF] = 0;

            const x = self.registers[parsed.first];
            const y = self.registers[parsed.second];

            var y_line: usize = 0;
            while (y_line < parsed.height) : (y_line += 1) {
                const pixel = self.memory[self.index + y_line];
                var x_line: usize = 0;

                while (x_line < 8) : (x_line += 1) {
                    const msb: u8 = 0x80;
                    const is_active: u8 = (pixel & (msb >> @intCast(x_line)));
                    // Skip if pixel is disabled
                    if (is_active == 0) {
                        continue;
                    }

                    // Calculate the x-value WITHIN the current row
                    // `tY` here is used to calculate the current row
                    const tX = (x + x_line) % GRAPHIC_WIDTH;
                    const tY = (y + y_line) % GRAPHIC_HEIGHT;

                    // Pixel position = row number (y-coordinate) * width + x-coordinate
                    const idx = tX + tY * GRAPHIC_WIDTH;
                    const current_pixel_state = self.graphics[idx];

                    // Set carry flag if conflict
                    if (current_pixel_state == 1) {
                        self.registers[0xF] = 1;
                    }
                    self.graphics[idx] ^= 1;
                }
            }
        },

        .EX9E => |parsed| {
            const key = self.keys[self.registers[parsed.register]];
            if (key == 1) {
                self.increment_program_counter();
            }
        },

        .EXA1 => |parsed| {
            const key = self.keys[self.registers[parsed.register]];
            if (key == 0) {
                self.increment_program_counter();
            }
        },

        .FX07 => |parsed| {
            self.registers[parsed.register] = self.delay_timer;
        },

        .FX0A => |parsed| {
            var pressed = false;
            for (self.keys, 0..) |key, idx| {
                if (key > 0) {
                    pressed = true;
                    self.registers[parsed.register] = @intCast(idx);
                    break;
                }
            }
            // Break if no key pressed, prevent program counter
            // from incrementing until key press found
            if (!pressed) {
                return;
            }
        },

        .FX15 => |parsed| {
            self.delay_timer = self.registers[parsed.register];
        },

        .FX18 => |parsed| {
            self.sound_timer = self.registers[parsed.register];
        },

        .FX1E => |parsed| {
            self.index += self.registers[parsed.register];
        },

        .FX29 => |parsed| {
            const reg = self.registers[parsed.register];
            if (reg >= 80) {
                std.log.err("invalid font index found: {}", .{.reg});
                @panic("invalid font index");
            }
            self.index = self.registers[parsed.register] * 5;
        },

        .FX33 => |parsed| {
            self.memory[self.index] = self.registers[parsed.register] / 100;
            self.memory[self.index + 1] = (self.registers[parsed.register] / 10) % 10;
            self.memory[self.index + 2] = self.registers[parsed.register] % 10;
        },

        .FX55 => |parsed| {
            var i: u16 = 0;
            while (i <= parsed.register) : (i += 1) {
                self.memory[self.index + i] = self.registers[i];
            }
        },

        .FX65 => |parsed| {
            var i: u16 = 0;
            while (i <= parsed.register) : (i += 1) {
                self.registers[i] = self.memory[self.index + i];
            }
        },
    }

    self.increment_program_counter();

    if (self.delay_timer > 0) {
        self.delay_timer -= 1;
    }

    if (self.sound_timer > 0) {
        self.sound_timer -= 1;
    }
}
