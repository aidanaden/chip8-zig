const std = @import("std");

const OPCODE_CLEAR = 0x00E0;
const OPCODE_RETURN = 0x00EE;

pub const OpCodeTag = enum {
    /// Opcodes involving no arguments
    /// Format: `00__`
    @"00E0",
    @"00EE",

    /// Opcodes involving an address
    /// Format: `_NNN` (`NNN` is a `u16` address)
    @"1NNN",
    @"2NNN",
    ANNN,
    BNNN,

    /// Opcodes involving 1 register and 1 byte (8 bits)
    /// Format: `_XNN` (`X` is register, `NN` is data)
    @"3XNN",
    @"4XNN",
    @"6XNN",
    @"7XNN",
    CXNN,

    /// Opcodes involving 2 registers
    /// Format: `_XY_` (`X` is register 1, `Y` is register 2)
    @"5XY0",
    @"8XY0",
    @"8XY1",
    @"8XY2",
    @"8XY3",
    @"8XY4",
    @"8XY5",
    @"8XY7",
    @"9XY0",

    /// Opcodes involving only 1 register
    /// Format: `_X__` (`X` is register)
    @"8XY6",
    @"8XYE",
    EX9E,
    EXA1,
    FX0A,
    FX07,
    FX15,
    FX18,
    FX1E,
    FX29,
    FX33,
    FX55,
    FX65,

    /// Opcode to draw sprite
    /// Format: `DXYN` (`X` is register 1, `Y` is register 2, `N` is 4 bit data)
    DXYN,
};

pub const OpCode = union(OpCodeTag) {
    @"00E0": struct {},
    @"00EE": struct {},

    @"1NNN": OpAddr,
    @"2NNN": OpAddr,
    ANNN: OpAddr,
    BNNN: OpAddr,

    @"3XNN": OpRegData,
    @"4XNN": OpRegData,
    @"6XNN": OpRegData,
    @"7XNN": OpRegData,
    CXNN: OpRegData,

    @"5XY0": OpRegReg,
    @"8XY0": OpRegReg,
    @"8XY1": OpRegReg,
    @"8XY2": OpRegReg,
    @"8XY3": OpRegReg,
    @"8XY4": OpRegReg,
    @"8XY5": OpRegReg,
    @"8XY7": OpRegReg,
    @"9XY0": OpRegReg,

    @"8XY6": OpReg,
    @"8XYE": OpReg,
    EX9E: OpReg,
    EXA1: OpReg,
    FX0A: OpReg,
    FX07: OpReg,
    FX15: OpReg,
    FX18: OpReg,
    FX1E: OpReg,
    FX29: OpReg,
    FX33: OpReg,
    FX55: OpReg,
    FX65: OpReg,

    DXYN: OpDraw,

    const Self = @This();
    pub fn decode(raw_opcode: u16) ?Self {
        const first = (raw_opcode & 0xF000) >> 12;
        return switch (first) {
            0x0 => {
                if (raw_opcode == OPCODE_CLEAR) {
                    return Self{ .@"00E0" = .{} };
                } else if (raw_opcode == OPCODE_RETURN) {
                    return Self{ .@"00EE" = .{} };
                } else {
                    return null;
                }
            },
            0x1 => {
                return Self{ .@"1NNN" = OpAddr.decode(raw_opcode) };
            },
            0x2 => {
                return Self{ .@"2NNN" = OpAddr.decode(raw_opcode) };
            },
            0x3 => {
                return Self{ .@"3XNN" = OpRegData.decode(raw_opcode) };
            },
            0x4 => {
                return Self{ .@"4XNN" = OpRegData.decode(raw_opcode) };
            },
            0x5 => {
                return Self{ .@"5XY0" = OpRegReg.decode(raw_opcode) };
            },
            0x6 => {
                return Self{ .@"6XNN" = OpRegData.decode(raw_opcode) };
            },
            0x7 => {
                return Self{ .@"7XNN" = OpRegData.decode(raw_opcode) };
            },
            0x8 => {
                const last = raw_opcode & 0x000F;
                return switch (last) {
                    0x0 => {
                        return Self{ .@"8XY0" = OpRegReg.decode(raw_opcode) };
                    },
                    0x1 => {
                        return Self{ .@"8XY1" = OpRegReg.decode(raw_opcode) };
                    },
                    0x2 => {
                        return Self{ .@"8XY2" = OpRegReg.decode(raw_opcode) };
                    },
                    0x3 => {
                        return Self{ .@"8XY3" = OpRegReg.decode(raw_opcode) };
                    },
                    0x4 => {
                        return Self{ .@"8XY4" = OpRegReg.decode(raw_opcode) };
                    },
                    0x5 => {
                        return Self{ .@"8XY5" = OpRegReg.decode(raw_opcode) };
                    },
                    0x6 => {
                        return Self{ .@"8XY6" = OpReg.decode(raw_opcode) };
                    },
                    0x7 => {
                        return Self{ .@"8XY7" = OpRegReg.decode(raw_opcode) };
                    },
                    0xE => {
                        return Self{ .@"8XYE" = OpReg.decode(raw_opcode) };
                    },
                    else => {
                        unreachable;
                    },
                };
            },
            0x9 => {
                return Self{ .@"9XY0" = OpRegReg.decode(raw_opcode) };
            },
            0xA => {
                return Self{ .ANNN = OpAddr.decode(raw_opcode) };
            },
            0xB => {
                return Self{ .BNNN = OpAddr.decode(raw_opcode) };
            },
            0xC => {
                return Self{ .CXNN = OpRegData.decode(raw_opcode) };
            },
            0xD => {
                return Self{ .DXYN = OpDraw.decode(raw_opcode) };
            },
            0xE => {
                const last = raw_opcode & 0x00FF;
                return switch (last) {
                    0x9E => {
                        return Self{ .EX9E = OpReg.decode(raw_opcode) };
                    },
                    0xA1 => {
                        return Self{ .EXA1 = OpReg.decode(raw_opcode) };
                    },
                    else => {
                        unreachable;
                    },
                };
            },
            0xF => {
                const last = raw_opcode & 0x00FF;
                return switch (last) {
                    0x07 => {
                        return Self{ .FX07 = OpReg.decode(raw_opcode) };
                    },
                    0x0A => {
                        return Self{ .FX0A = OpReg.decode(raw_opcode) };
                    },
                    0x15 => {
                        return Self{ .FX15 = OpReg.decode(raw_opcode) };
                    },
                    0x18 => {
                        return Self{ .FX18 = OpReg.decode(raw_opcode) };
                    },
                    0x1E => {
                        return Self{ .FX1E = OpReg.decode(raw_opcode) };
                    },
                    0x29 => {
                        return Self{ .FX29 = OpReg.decode(raw_opcode) };
                    },
                    0x33 => {
                        return Self{ .FX33 = OpReg.decode(raw_opcode) };
                    },
                    0x55 => {
                        return Self{ .FX55 = OpReg.decode(raw_opcode) };
                    },
                    0x65 => {
                        return Self{ .FX65 = OpReg.decode(raw_opcode) };
                    },
                    else => {
                        unreachable;
                    },
                };
            },
            else => {
                unreachable;
            },
        };
    }
};

/// Opcodes involving an address
///
/// Format: `_NNN` (`NNN` is a `u16` address)
pub const OpAddr = struct {
    address: u16,

    const Self = @This();
    pub fn decode(raw_opcode: u16) Self {
        // Address is last 12 bits
        const address = raw_opcode & 0x0FFF;
        return Self{
            .address = address,
        };
    }
};

pub const OpRegData = struct {
    register: u4,
    data: u8,

    const Self = @This();
    pub fn decode(raw_opcode: u16) Self {
        // First register is bits 4-8
        const register: u4 = @intCast((raw_opcode & 0x0F00) >> 8);
        // Data is last 8 bits
        const data: u8 = @intCast(raw_opcode & 0x00FF);
        return Self{
            .register = register,
            .data = @truncate(data),
        };
    }
};

pub const OpRegReg = struct {
    first: u4,
    second: u4,

    const Self = @This();
    pub fn decode(raw_opcode: u16) Self {
        // First register is bits 4-8
        const first: u4 = @intCast((raw_opcode & 0x0F00) >> 8);
        // Second register is bits 8-12
        const second: u4 = @intCast((raw_opcode & 0x00F0) >> 4);
        return Self{ .first = first, .second = second };
    }
};

pub const OpReg = struct {
    register: u4,

    const Self = @This();
    pub fn decode(raw_opcode: u16) Self {
        // Register is bits 4-8
        const register: u4 = @intCast((raw_opcode & 0x0F00) >> 8);
        return Self{ .register = register };
    }
};

pub const OpDraw = struct {
    first: u4,
    second: u4,
    height: u4,

    const Self = @This();
    pub fn decode(raw_opcode: u16) Self {
        // First register is bits 4-8
        const first: u4 = @intCast((raw_opcode & 0x0F00) >> 8);
        // Second register is bits 8-12
        const second: u4 = @intCast((raw_opcode & 0x00F0) >> 4);
        // Data bytes is bits 12-16
        const height: u4 = @intCast(raw_opcode & 0x000F);
        return Self{ .first = first, .second = second, .height = height };
    }
};
