const std = @import("std");
const Allocator = std.mem.Allocator;
const time = std.time;

/// Opcode
const opcode = @import("opcode.zig");
const OpCodeTag = opcode.OpCodeTag;
const OpCode = opcode.OpCode;
const OpAddressTag = opcode.OpAddressTag;
const OpVoidTag = opcode.OpVoidTag;
const OpRegisterTag = opcode.OpRegisterTag;
const OpRegisterDataTag = opcode.OpRegisterDataTag;
const OpRegisterRegisterTag = opcode.OpRegisterRegisterTag;

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

/// Emulate a single Fetch-Decode-Execute cpu cycle
pub fn cycle(self: *Self) void {
    // Fetch
    self.fetch_opcode();

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
        OpCodeTag.op_void => |op_void| {
            switch (op_void) {
                // `00E0`
                OpVoidTag.Clear => {
                    self.graphics = std.mem.zeroes([GRAPHIC_HEIGHT * GRAPHIC_WIDTH]u8);
                },
                // `00EE`
                OpVoidTag.Return => {
                    self.stack_pointer -= 1;
                    self.program_counter = self.stack[self.stack_pointer];
                },
            }
        },

        OpCodeTag.op_address => |op_addr| {
            switch (op_addr.tag) {
                // `1NNN`
                OpAddressTag.Jump => {
                    self.program_counter = op_addr.address;
                    return;
                },
                // `2NNN`
                OpAddressTag.Call => {
                    self.stack[self.stack_pointer] = self.program_counter;
                    self.stack_pointer += 1;
                    self.program_counter = op_addr.address;
                    return;
                },
                // `ANNN`
                OpAddressTag.SetIdx => {
                    self.index = op_addr.address;
                },
                // `BNNN`
                OpAddressTag.JumpReg => {
                    self.program_counter = @as(u16, self.registers[0]) + op_addr.address;
                    return;
                },
            }
        },

        OpCodeTag.op_register => |op_reg| {
            switch (op_reg.tag) {
                // `8XY6`
                OpRegisterTag.RightShift => {
                    const reg = self.registers[op_reg.register];
                    const lsb: u1 = @truncate(reg & 1);
                    self.registers[op_reg.register] = (reg >> 1);
                    self.registers[0xF] = lsb;
                },
                // `8XYE`
                OpRegisterTag.LeftShift => {
                    const reg = self.registers[op_reg.register];
                    const msb: u8 = (reg & 0x80) >> 7;
                    self.registers[op_reg.register] = (reg << 1);
                    self.registers[0xF] = msb;
                },
                // `EX9E`
                OpRegisterTag.EqualKey => {
                    const key = self.keys[self.registers[op_reg.register]];
                    if (key == 1) {
                        self.increment_program_counter();
                    }
                },
                // `EXA1`
                OpRegisterTag.NotEqualKey => {
                    const key = self.keys[self.registers[op_reg.register]];
                    if (key == 0) {
                        self.increment_program_counter();
                    }
                },
                // `FX07`
                OpRegisterTag.GetDelay => {
                    self.registers[op_reg.register] = self.delay_timer;
                },
                // `FX0A`
                OpRegisterTag.GetKey => {
                    var pressed = false;
                    for (self.keys, 0..) |key, idx| {
                        if (key > 0) {
                            pressed = true;
                            self.registers[op_reg.register] = @intCast(idx);
                            break;
                        }
                    }
                    // Break if no key pressed, prevent program counter
                    // from incrementing until key press found
                    if (!pressed) {
                        return;
                    }
                },
                // `FX15`
                OpRegisterTag.SetDelay => {
                    self.delay_timer = self.registers[op_reg.register];
                },
                // `FX18`
                OpRegisterTag.SetSound => {
                    self.sound_timer = self.registers[op_reg.register];
                },
                // `FX1E`
                OpRegisterTag.IncrementIdx => {
                    self.index += self.registers[op_reg.register];
                },
                // `FX29`
                OpRegisterTag.SetIdxSprite => {
                    const reg = self.registers[op_reg.register];
                    if (reg >= 80) {
                        std.log.err("invalid font index found: {}", .{.reg});
                        @panic("invalid font index");
                    }
                    self.index = self.registers[op_reg.register] * 5;
                },
                // `FX33`
                OpRegisterTag.SetBcd => {
                    self.memory[self.index] = self.registers[op_reg.register] / 100;
                    self.memory[self.index + 1] = (self.registers[op_reg.register] / 10) % 10;
                    self.memory[self.index + 2] = self.registers[op_reg.register] % 10;
                },
                // `FX55`
                OpRegisterTag.Dump => {
                    var i: u16 = 0;
                    while (i <= op_reg.register) : (i += 1) {
                        self.memory[self.index + i] = self.registers[i];
                    }
                },
                // `FX65`
                OpRegisterTag.Load => {
                    var i: u16 = 0;
                    while (i <= op_reg.register) : (i += 1) {
                        self.registers[i] = self.memory[self.index + i];
                    }
                },
            }
        },

        OpCodeTag.op_register_data => |op_reg_data| {
            switch (op_reg_data.tag) {
                // `3XNN`
                OpRegisterDataTag.Equal => {
                    const reg_data = self.registers[op_reg_data.register];
                    if (reg_data == op_reg_data.data) {
                        self.increment_program_counter();
                    }
                },
                // `4XNN`
                OpRegisterDataTag.NotEqual => {
                    const reg_data = self.registers[op_reg_data.register];
                    if (reg_data != op_reg_data.data) {
                        self.increment_program_counter();
                    }
                },
                // `6XNN`
                OpRegisterDataTag.Set => {
                    self.registers[op_reg_data.register] = op_reg_data.data;
                },
                // `7XNN`
                OpRegisterDataTag.Increment => {
                    const sum = @addWithOverflow(self.registers[op_reg_data.register], op_reg_data.data);
                    self.registers[op_reg_data.register] = sum[0];
                },
                // `CXNN`
                OpRegisterDataTag.AndRand => {
                    const random = self.random.intRangeAtMost(u8, 0, 255);
                    self.registers[op_reg_data.register] = (random & op_reg_data.data);
                },
            }
        },

        OpCodeTag.op_register_register => |op_reg_reg| {
            switch (op_reg_reg.tag) {
                // `5XY0`
                OpRegisterRegisterTag.Equal => {
                    const first_reg_data = self.registers[op_reg_reg.first];
                    const second_reg_data = self.registers[op_reg_reg.second];
                    if (first_reg_data == second_reg_data) {
                        self.increment_program_counter();
                    }
                },
                // `9XY0`
                OpRegisterRegisterTag.NotEqual => {
                    const first_reg_data = self.registers[op_reg_reg.first];
                    const second_reg_data = self.registers[op_reg_reg.second];
                    if (first_reg_data != second_reg_data) {
                        self.increment_program_counter();
                    }
                },
                // `8XY0`
                OpRegisterRegisterTag.Set => {
                    self.registers[op_reg_reg.first] = self.registers[op_reg_reg.second];
                },
                // `8XY1`
                OpRegisterRegisterTag.Or => {
                    self.registers[op_reg_reg.first] |= self.registers[op_reg_reg.second];
                },
                // `8XY2`
                OpRegisterRegisterTag.And => {
                    self.registers[op_reg_reg.first] &= self.registers[op_reg_reg.second];
                },
                // `8XY3`
                OpRegisterRegisterTag.Xor => {
                    self.registers[op_reg_reg.first] ^= self.registers[op_reg_reg.second];
                },
                // `8XY4`
                OpRegisterRegisterTag.Increment => {
                    const res = @addWithOverflow(self.registers[op_reg_reg.first], self.registers[op_reg_reg.second]);
                    self.registers[op_reg_reg.first] = res[0];
                    self.registers[0xF] = res[1];
                },
                // `8XY5`
                OpRegisterRegisterTag.Decrement => {
                    const first = self.registers[op_reg_reg.first];
                    const second = self.registers[op_reg_reg.second];
                    const res = @subWithOverflow(first, second);
                    self.registers[op_reg_reg.first] = res[0];
                    const bit: u1 = if (second >= first) 1 else 0;
                    self.registers[0xF] = bit;
                },
                // `8XY7`
                OpRegisterRegisterTag.Subtract => {
                    const first = self.registers[op_reg_reg.first];
                    const second = self.registers[op_reg_reg.second];
                    const res = @subWithOverflow(second, first);
                    self.registers[op_reg_reg.first] = res[0];
                    const bit: u1 = if (first >= second) 1 else 0;
                    self.registers[0xF] = bit;
                },
            }
        },

        OpCodeTag.op_draw => |op_draw| {
            self.registers[0xF] = 0;

            const x = self.registers[op_draw.first];
            const y = self.registers[op_draw.second];

            var y_line: usize = 0;
            while (y_line < op_draw.height) : (y_line += 1) {
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
    }

    self.increment_program_counter();

    if (self.delay_timer > 0) {
        self.delay_timer -= 1;
    }

    if (self.sound_timer > 0) {
        self.sound_timer -= 1;
    }
}

fn fetch_opcode(self: *Self) void {
    const first = self.memory[self.program_counter];
    const second = self.memory[self.program_counter + 1];
    self.opcode = @truncate(@as(u16, first) << 8 | second);
}

const expect = std.testing.expect;
test "single cycle CLEAR" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x00;
    cpu.memory[cpu.program_counter + 1] = 0xE0;

    // Fetch
    cpu.fetch_opcode();

    // Decode
    const decoded = OpCode.decode(cpu.opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.op_void);
    try expect(decoded.op_void == OpVoidTag.Clear);
}

test "single cycle RETURN" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x00;
    cpu.memory[cpu.program_counter + 1] = 0xEE;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.op_void);
    try expect(decoded.op_void == OpVoidTag.Return);
}

test "single cycle JUMP" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x10;
    cpu.memory[cpu.program_counter + 1] = 0xFF;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = OpCode.decode(raw_opcode);
    try expect(decoded.op_address.tag == OpAddressTag.Jump);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.op_address);
    try expect(decoded.op_address.address == 0x0FF);
}

test "single cycle CALL" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x2A;
    cpu.memory[cpu.program_counter + 1] = 0xEE;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.op_address);
    try expect(decoded.op_address.tag == OpAddressTag.Call);
    try expect(decoded.op_address.address == 0xAEE);
}

test "single cycle EQUAL DATA" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x31;
    cpu.memory[cpu.program_counter + 1] = 0x69;
    cpu.registers[1] = 0x69;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.op_register_data);
    try expect(decoded.op_register_data.tag == OpRegisterDataTag.Equal);
    const register_data = cpu.registers[decoded.op_register_data.register];
    try expect(decoded.op_register_data.register == 1);
    try expect(register_data == 0x69);
    try expect(register_data == decoded.op_register_data.data);
}

test "single cycle NOT EQUAL DATA" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x42;
    cpu.memory[cpu.program_counter + 1] = 0x42;
    cpu.registers[2] = 0x69;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.op_register_data);
    try expect(decoded.op_register_data.tag == OpRegisterDataTag.NotEqual);
    const register_data = cpu.registers[decoded.op_register_data.register];
    try expect(decoded.op_register_data.register == 2);
    try expect(register_data == 0x69);
    try expect(decoded.op_register_data.data == 0x42);
    try expect(register_data != decoded.op_register_data.data);
}

test "single cycle EQUAL REGISTER" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x54;
    cpu.memory[cpu.program_counter + 1] = 0x20;
    cpu.registers[4] = 0x69;
    cpu.registers[2] = 0x69;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.op_register_register);
    try expect(decoded.op_register_register.tag == OpRegisterRegisterTag.Equal);
    const first_reg = cpu.registers[decoded.op_register_register.first];
    try expect(first_reg == 0x69);
    const second_reg = cpu.registers[decoded.op_register_register.second];
    try expect(second_reg == 0x69);
    try expect(first_reg == second_reg);
}

test "single cycle NOT EQUAL REGISTER" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x94;
    cpu.memory[cpu.program_counter + 1] = 0x20;
    cpu.registers[4] = 0x69;
    cpu.registers[2] = 0x42;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.op_register_register);
    try expect(decoded.op_register_register.tag == OpRegisterRegisterTag.NotEqual);
    const first_reg = cpu.registers[decoded.op_register_register.first];
    try expect(first_reg == 0x69);
    const second_reg = cpu.registers[decoded.op_register_register.second];
    try expect(second_reg == 0x42);
    try expect(first_reg != second_reg);
}

test "single cycle 0x8XY5 overflow" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x81;
    cpu.memory[cpu.program_counter + 1] = 0x25;
    cpu.registers[1] = 0x42;
    cpu.registers[2] = 0x42;

    cpu.cycle();
    try expect(cpu.registers[0xF] == 1);
}

test "single cycle 0x8XY6 bit 1" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x81;
    cpu.memory[cpu.program_counter + 1] = 0x26;
    cpu.registers[1] = 0x43;

    cpu.cycle();
    try expect(cpu.registers[0xF] == 1);
}

test "single cycle 0x8XY6 bit 0" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x81;
    cpu.memory[cpu.program_counter + 1] = 0x26;
    cpu.registers[1] = 0x42;

    cpu.cycle();
    try expect(cpu.registers[0xF] == 0);
}

test "single cycle 0x8XYE bit 1" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x81;
    cpu.memory[cpu.program_counter + 1] = 0x2E;
    cpu.registers[1] = 0x80;

    cpu.cycle();
    try expect(cpu.registers[0xF] == 1);
}

test "single cycle 0x8XYE bit 0" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0x81;
    cpu.memory[cpu.program_counter + 1] = 0x2E;
    cpu.registers[1] = 0x3F;

    cpu.cycle();
    try expect(cpu.registers[0xF] == 0);
}

test "single cycle 0xCXNN" {
    var cpu = try init();
    cpu.memory[cpu.program_counter] = 0xC1;
    cpu.memory[cpu.program_counter + 1] = 0x42;
    cpu.registers[1] = 0x3F;

    cpu.cycle();
    try expect(cpu.registers[1] != 0x3F);
}
