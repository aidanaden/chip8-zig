const std = @import("std");
const Allocator = std.mem.Allocator;
const time = std.time;

/// Opcode
const opcode = @import("opcode.zig");
const OpCodeTag = opcode.OpCodeTag;
const OpCode = opcode.OpCode;

/// Constants
const GRAPHIC_HEIGHT = 64;
const GRAPHIC_WIDTH = 32;
const MEMORY_SIZE = 4096;
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
memory: [MEMORY_SIZE]u8,
graphics: [GRAPHIC_HEIGHT * GRAPHIC_WIDTH]u8,
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

const Self = @This();
pub fn init() Self {
    // var prng = std.rand.DefaultPrng.init(blk: {
    //     var seed: u64 = undefined;
    //     try std.posix.getrandom(std.mem.asBytes(&seed));
    //     break :blk seed;
    // });

    var memory: [MEMORY_SIZE]u8 = std.mem.zeroes([MEMORY_SIZE]u8);
    for (FONTSET, 0..) |font, i| {
        memory[i] = font;
    }

    return Self{
        .program_counter = 0x200,
        .opcode = 0,
        .memory = memory,
        .graphics = std.mem.zeroes([GRAPHIC_HEIGHT * GRAPHIC_WIDTH]u8),
        .registers = std.mem.zeroes([16]u8),
        .index = 0,
        .delay_timer = 0,
        .sound_timer = 0,
        .stack = std.mem.zeroes([16]u16),
        .stack_pointer = 0,
        .keys = std.mem.zeroes([16]u8),
    };
}

pub fn increment_program_counter(self: *Self) void {
    self.program_counter += 2;
}

/// Emulate a single Fetch-Decode-Execute cpu cycle
pub fn cycle(self: *Self) void {
    // Fetch
    const raw_opcode = self.fetch_opcode();

    // Decode
    const decoded = opcode.OpCode.decode(raw_opcode);

    // Execute
    switch (decoded) {
        OpCodeTag.Return => |_| {
            self.stack_pointer -= 1;
            self.program_counter = self.stack[self.stack_pointer];
            self.increment_program_counter();
        },
        OpCodeTag.Clear => |_| {
            self.graphics = std.mem.zeroes([GRAPHIC_HEIGHT * GRAPHIC_WIDTH]u8);
            self.increment_program_counter();
        },
        OpCodeTag.Jump => |jump| {
            self.program_counter = jump.jump_address;
        },
        OpCodeTag.Call => |call| {
            self.stack[self.stack_pointer] = self.program_counter;
            self.stack_pointer += 1;
            self.program_counter = call.fn_address;
        },
        OpCodeTag.EqualData => |eq_data| {
            const reg_data = self.registers[eq_data.register];
            if (reg_data == eq_data.data) {
                self.increment_program_counter();
            }
            self.increment_program_counter();
        },
        OpCodeTag.NotEqualData => |ne_data| {
            const reg_data = self.registers[ne_data.register];
            if (reg_data != ne_data.data) {
                self.increment_program_counter();
            }
            self.increment_program_counter();
        },
    }

    self.increment_program_counter();
}

fn fetch_opcode(self: *Self) u16 {
    const first: u16 = @as(u16, @intCast(self.memory[self.program_counter])) << 8;
    const second: u16 = self.memory[self.program_counter + 1];
    return first | second;
}

const expect = std.testing.expect;
test "single cycle CLEAR" {
    var cpu = init();
    cpu.memory[cpu.program_counter] = 0x00;
    cpu.memory[cpu.program_counter + 1] = 0xE0;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = opcode.OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.Clear);
}

test "single cycle RETURN" {
    var cpu = init();
    cpu.memory[cpu.program_counter] = 0x00;
    cpu.memory[cpu.program_counter + 1] = 0xEE;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = opcode.OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.Return);
}

test "single cycle JUMP" {
    var cpu = init();
    cpu.memory[cpu.program_counter] = 0x10;
    cpu.memory[cpu.program_counter + 1] = 0xFF;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = opcode.OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.Jump);
    try expect(decoded.Jump.jump_address == 0x0FF);
}

test "single cycle CALL" {
    var cpu = init();
    cpu.memory[cpu.program_counter] = 0x2A;
    cpu.memory[cpu.program_counter + 1] = 0xEE;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = opcode.OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.Call);
    try expect(decoded.Call.fn_address == 0xAEE);
}

test "single cycle EQUAL DATA" {
    var cpu = init();
    cpu.memory[cpu.program_counter] = 0x31;
    cpu.memory[cpu.program_counter + 1] = 0x69;
    cpu.registers[1] = 0x69;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = opcode.OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.EqualData);
    const register_data = cpu.registers[decoded.EqualData.register];
    try expect(register_data == 0x69);
    try expect(decoded.EqualData.data == 0x69);
    try expect(register_data == decoded.EqualData.data);
}

test "single cycle NOT EQUAL DATA" {
    var cpu = init();
    cpu.memory[cpu.program_counter] = 0x42;
    cpu.memory[cpu.program_counter + 1] = 0x42;
    cpu.registers[2] = 0x69;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = opcode.OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.NotEqualData);
    const register_data = cpu.registers[decoded.NotEqualData.register];
    try expect(register_data == 0x69);
    try expect(decoded.NotEqualData.data == 0x42);
    try expect(register_data != decoded.NotEqualData.data);
}

test "single cycle EQUAL REGISTER" {
    var cpu = init();
    cpu.memory[cpu.program_counter] = 0x54;
    cpu.memory[cpu.program_counter + 1] = 0x20;
    cpu.registers[4] = 0x69;
    cpu.registers[2] = 0x69;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = opcode.OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.EqualRegister);
    const first_reg = cpu.registers[decoded.EqualRegister.first];
    try expect(first_reg == 0x69);
    const second_reg = cpu.registers[decoded.EqualRegister.second];
    try expect(second_reg == 0x69);
    try expect(first_reg == second_reg);
}

test "single cycle NOT EQUAL REGISTER" {
    var cpu = init();
    cpu.memory[cpu.program_counter] = 0x94;
    cpu.memory[cpu.program_counter + 1] = 0x20;
    cpu.registers[4] = 0x69;
    cpu.registers[2] = 0x42;

    // Fetch
    const raw_opcode = cpu.fetch_opcode();

    // Decode
    const decoded = opcode.OpCode.decode(raw_opcode);
    try expect(@as(OpCodeTag, decoded) == OpCodeTag.NotEqualRegister);
    const first_reg = cpu.registers[decoded.NotEqualRegister.first];
    try expect(first_reg == 0x69);
    const second_reg = cpu.registers[decoded.NotEqualRegister.second];
    try expect(second_reg == 0x42);
    try expect(first_reg != second_reg);
}
