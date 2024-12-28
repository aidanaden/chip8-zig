const std = @import("std");

const OPCODE_CLEAR = 0x00E0;
const OPCODE_RETURN = 0x00EE;

pub const OpCodeTag = enum {
    op_void,
    op_address,
    op_register,
    op_register_data,
    op_register_register,
    op_draw,
};

pub const OpCode = union(OpCodeTag) {
    op_void: OpVoidTag,
    op_address: OpAddress,
    op_register: OpRegister,
    op_register_data: OpRegisterData,
    op_register_register: OpRegisterRegister,
    op_draw: OpDraw,

    const Self = @This();
    pub fn decode(raw_opcode: u16) ?Self {
        const first = (raw_opcode & 0xF000) >> 12;
        return switch (first) {
            0x0 => {
                if (raw_opcode == OPCODE_CLEAR) {
                    return Self{ .op_void = OpVoidTag.Clear };
                } else if (raw_opcode == OPCODE_RETURN) {
                    return Self{ .op_void = OpVoidTag.Return };
                } else {
                    return null;
                }
            },
            0x1 => {
                return Self{ .op_address = OpAddress.decode(OpAddressTag.Jump, raw_opcode) };
            },
            0x2 => {
                return Self{ .op_address = OpAddress.decode(OpAddressTag.Call, raw_opcode) };
            },
            0x3 => {
                return Self{ .op_register_data = OpRegisterData.decode(OpRegisterDataTag.Equal, raw_opcode) };
            },
            0x4 => {
                return Self{ .op_register_data = OpRegisterData.decode(OpRegisterDataTag.NotEqual, raw_opcode) };
            },
            0x5 => {
                return Self{ .op_register_register = OpRegisterRegister.decode(OpRegisterRegisterTag.Equal, raw_opcode) };
            },
            0x6 => {
                return Self{ .op_register_data = OpRegisterData.decode(OpRegisterDataTag.Set, raw_opcode) };
            },
            0x7 => {
                return Self{ .op_register_data = OpRegisterData.decode(OpRegisterDataTag.Increment, raw_opcode) };
            },
            0x8 => {
                const last = raw_opcode & 0x000F;
                return switch (last) {
                    0x0 => {
                        return Self{ .op_register_register = OpRegisterRegister.decode(OpRegisterRegisterTag.Set, raw_opcode) };
                    },
                    0x1 => {
                        return Self{ .op_register_register = OpRegisterRegister.decode(OpRegisterRegisterTag.Or, raw_opcode) };
                    },
                    0x2 => {
                        return Self{ .op_register_register = OpRegisterRegister.decode(OpRegisterRegisterTag.And, raw_opcode) };
                    },
                    0x3 => {
                        return Self{ .op_register_register = OpRegisterRegister.decode(OpRegisterRegisterTag.Xor, raw_opcode) };
                    },
                    0x4 => {
                        return Self{ .op_register_register = OpRegisterRegister.decode(OpRegisterRegisterTag.Increment, raw_opcode) };
                    },
                    0x5 => {
                        return Self{ .op_register_register = OpRegisterRegister.decode(OpRegisterRegisterTag.Decrement, raw_opcode) };
                    },
                    0x6 => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.RightShift, raw_opcode) };
                    },
                    0x7 => {
                        return Self{ .op_register_register = OpRegisterRegister.decode(OpRegisterRegisterTag.Subtract, raw_opcode) };
                    },
                    0xE => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.LeftShift, raw_opcode) };
                    },
                    else => {
                        unreachable;
                    },
                };
            },
            0x9 => {
                return Self{ .op_register_register = OpRegisterRegister.decode(OpRegisterRegisterTag.NotEqual, raw_opcode) };
            },
            0xA => {
                return Self{ .op_address = OpAddress.decode(OpAddressTag.SetIdx, raw_opcode) };
            },
            0xB => {
                return Self{ .op_address = OpAddress.decode(OpAddressTag.JumpReg, raw_opcode) };
            },
            0xC => {
                return Self{ .op_register_data = OpRegisterData.decode(OpRegisterDataTag.AndRand, raw_opcode) };
            },
            0xD => {
                return Self{ .op_draw = OpDraw.decode(raw_opcode) };
            },
            0xE => {
                const last = raw_opcode & 0x00FF;
                return switch (last) {
                    0x9E => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.EqualKey, raw_opcode) };
                    },
                    0xA1 => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.NotEqualKey, raw_opcode) };
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
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.GetDelay, raw_opcode) };
                    },
                    0x0A => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.GetKey, raw_opcode) };
                    },
                    0x15 => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.SetDelay, raw_opcode) };
                    },
                    0x18 => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.SetSound, raw_opcode) };
                    },
                    0x1E => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.IncrementIdx, raw_opcode) };
                    },
                    0x29 => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.SetIdxSprite, raw_opcode) };
                    },
                    0x33 => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.SetBcd, raw_opcode) };
                    },
                    0x55 => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.Dump, raw_opcode) };
                    },
                    0x65 => {
                        return Self{ .op_register = OpRegister.decode(OpRegisterTag.Load, raw_opcode) };
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

/// Opcodes involving no arguments
///
/// Format: `00__`
pub const OpVoidTag = enum {
    /// 0x00E0
    Clear,
    /// 0x00EE
    Return,
};

/// Opcodes involving an address
///
/// Format: `_NNN` (`NNN` is a `u16` address)
pub const OpAddressTag = enum {
    /// 0x1NNN
    Jump,
    /// 0x2NNN
    Call,
    /// 0xANNN
    SetIdx,
    /// 0xBNNN
    JumpReg,
};

pub const OpAddress = struct {
    tag: OpAddressTag,
    address: u16,

    const Self = @This();
    pub fn decode(tag: OpAddressTag, raw_opcode: u16) Self {
        // Address is last 12 bits
        const address = raw_opcode & 0x0FFF;
        return Self{
            .tag = tag,
            .address = address,
        };
    }
};

/// Opcodes involving 1 register and 1 byte (8 bits)
///
/// Format: `_XNN` (`X` is register, `NN` is data)
pub const OpRegisterDataTag = enum {
    /// `3XNN`
    Equal,
    /// `4XNN`
    NotEqual,
    /// `6XNN`
    Set,
    /// `7XNN`
    Increment,
    /// `CXNN`
    AndRand,
};

pub const OpRegisterData = struct {
    tag: OpRegisterDataTag,
    register: u4,
    data: u8,

    const Self = @This();
    pub fn decode(tag: OpRegisterDataTag, raw_opcode: u16) Self {
        // First register is bits 4-8
        const register: u4 = @intCast((raw_opcode & 0x0F00) >> 8);
        // Data is last 8 bits
        const data: u8 = @intCast(raw_opcode & 0x00FF);
        return Self{
            .tag = tag,
            .register = register,
            .data = @truncate(data),
        };
    }
};

/// Opcodes involving 2 registers
///
/// Format: `_XY_` (`X` is register 1, `Y` is register 2)
pub const OpRegisterRegisterTag = enum {
    /// `5XY0`
    Equal,
    /// `8XY0`
    Set,
    /// `8XY1`
    Or,
    /// `8XY2`
    And,
    /// `8XY3`
    Xor,
    /// `8XY4`
    Increment,
    /// `8XY5`
    Decrement,
    /// `8XY7`
    Subtract,
    /// `9XY0`
    NotEqual,
};

pub const OpRegisterRegister = struct {
    tag: OpRegisterRegisterTag,
    first: u4,
    second: u4,

    const Self = @This();
    pub fn decode(tag: OpRegisterRegisterTag, raw_opcode: u16) Self {
        // First register is bits 4-8
        const first: u4 = @intCast((raw_opcode & 0x0F00) >> 8);
        // Second register is bits 8-12
        const second: u4 = @intCast((raw_opcode & 0x00F0) >> 4);
        return Self{ .tag = tag, .first = first, .second = second };
    }
};

/// Opcodes involving only 1 register
///
/// Format: `_X__` (`X` is register)
pub const OpRegisterTag = enum {
    /// `8XY6`
    RightShift,
    /// `8XYE`
    LeftShift,
    /// `EX9E`
    EqualKey,
    /// `EXA1`
    NotEqualKey,
    /// `FX0A`
    GetKey,
    /// `FX07`
    GetDelay,
    /// `FX15`
    SetDelay,
    /// `FX18`
    SetSound,
    /// `FX1E`
    IncrementIdx,
    /// `FX29`
    SetIdxSprite,
    /// `FX33`
    SetBcd,
    /// `FX55`
    Dump,
    /// `FX65`
    Load,
};

pub const OpRegister = struct {
    tag: OpRegisterTag,
    register: u4,

    const Self = @This();
    pub fn decode(tag: OpRegisterTag, raw_opcode: u16) Self {
        // Register is bits 4-8
        const register: u4 = @intCast((raw_opcode & 0x0F00) >> 8);
        return Self{ .tag = tag, .register = register };
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
