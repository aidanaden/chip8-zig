const std = @import("std");

const OPCODE_CLEAR = 0x00E0;
const OPCODE_RETURN = 0x00EE;

pub const OpCodeTag = enum {
    Clear,
    Return,
    Jump,
    Call,
    EqualData,
    NotEqualData,
    EqualRegister,
    NotEqualRegister,
};

pub const OpCode = union(OpCodeTag) {
    Clear: OpCodeTag,
    Return: OpCodeTag,
    Jump: OpJump,
    Call: OpCall,
    EqualData: OpEqualData,
    NotEqualData: OpNotEqualData,
    EqualRegister: OpEqualRegister,
    NotEqualRegister: OpNotEqualRegister,

    const Self = @This();
    pub fn decode(raw_opcode: u16) Self {
        const first = raw_opcode >> 12;
        return switch (first) {
            0x0 => {
                if (raw_opcode == OPCODE_CLEAR) {
                    return Self{ .Clear = OpCodeTag.Clear };
                }
                if (raw_opcode == OPCODE_RETURN) {
                    return Self{ .Return = OpCodeTag.Return };
                }
                unreachable;
            },
            0x1 => {
                // Address is last 12 bits
                const address = raw_opcode & 0x0FFF;
                return Self{ .Jump = .{ .jump_address = address } };
            },
            0x2 => {
                // Address is last 12 bits
                const address = raw_opcode & 0x0FFF;
                return Self{ .Call = .{ .fn_address = address } };
            },
            0x3 => {
                // Register is bits 4-8
                const register: u4 = @intCast((raw_opcode & 0x0F00) >> 8);
                // Data is last 8 bits
                const data: u8 = @intCast(raw_opcode & 0x00FF);
                return Self{ .EqualData = .{ .register = register, .data = data } };
            },
            0x4 => {
                // Register is bits 4-8
                const register: u4 = @intCast((raw_opcode & 0x0F00) >> 8);
                // Data is last 8 bits
                const data: u8 = @intCast(raw_opcode & 0x00FF);
                return Self{ .NotEqualData = .{ .register = register, .data = data } };
            },
            0x5 => {
                // First register is bits 4-8
                const first_reg: u4 = @intCast((raw_opcode & 0x0F00) >> 8);
                // Second register is bits 8-12
                const second_reg: u4 = @intCast((raw_opcode & 0x00F0) >> 4);
                return Self{ .EqualRegister = .{ .first = first_reg, .second = second_reg } };
            },
            0x9 => {
                // First register is bits 4-8
                const first_reg: u4 = @intCast((raw_opcode & 0x0F00) >> 8);
                // Second register is bits 8-12
                const second_reg: u4 = @intCast((raw_opcode & 0x00F0) >> 4);
                return Self{ .NotEqualRegister = .{ .first = first_reg, .second = second_reg } };
            },
            else => {
                unreachable;
            },
        };
    }
};

pub const OpJump = struct {
    jump_address: u16,
};

pub const OpCall = struct {
    fn_address: u16,
};

pub const OpEqualData = struct {
    register: u4,
    data: u8,
};

pub const OpNotEqualData = struct {
    register: u4,
    data: u8,
};

pub const OpEqualRegister = struct {
    first: u4,
    second: u4,
};

pub const OpNotEqualRegister = struct {
    first: u4,
    second: u4,
};
