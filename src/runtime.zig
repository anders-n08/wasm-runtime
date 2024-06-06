const std = @import("std");
const parser = @import("parser.zig");
const types = @import("types.zig");
const util = @import("util.zig");

const Module = parser.Module;
const Function = parser.Function;

const Opcode = types.Opcode;

const RuntimeError = error{
    FunctionNotFound,
    WrongTypeOnStack,
    UnsupportedOpCode,
    NotImplemented,
};

const StackEntryType = enum {
    set_i32,
    set_frame,
};

pub const StackEntry = union(StackEntryType) {
    set_i32: i32,
    set_frame: i32,
};

// fixme: Instance?
pub const Machine = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayList(StackEntry),
    module: *Module,

    pc: usize = 0,
    function: ?*Function = null,
    param_stack_idx: usize = 0,

    pub fn init(allocator: std.mem.Allocator, module: *Module) Machine {
        return .{
            .allocator = allocator,
            .stack = std.ArrayList(StackEntry).init(allocator),
            .module = module,
        };
    }

    pub fn pushI32(self: *Machine, v: i32) !void {
        try self.stack.append(.{
            .set_i32 = v,
        });
    }

    pub fn pop(self: *Machine) StackEntry {
        const v = self.stack.pop();
        return v;
    }

    pub fn popInteger(self: *Machine) !i32 {
        const set = self.stack.pop();
        switch (set) {
            .set_i32 => |v| {
                return v;
            },
            .set_frame => {
                return RuntimeError.WrongTypeOnStack;
            },
        }
    }

    pub fn getFunction(self: *Machine, function_name: []const u8) !*Function {
        for (self.module.functions.items) |*f| {
            if (std.mem.eql(u8, function_name, f.name)) {
                return f;
            }
        }

        return RuntimeError.FunctionNotFound;
    }

    pub fn printStack(self: *Machine) void {
        std.log.info("Stack", .{});
        for (self.stack.items, 0..) |set, idx| {
            switch (set) {
                .set_i32 => |v| {
                    std.log.info("  {d} i32 {d} 0x{X}", .{ idx, v, v });
                },
                .set_frame => |v| {
                    std.log.info("  {d} frame {d} 0x{X}", .{ idx, v, v });
                },
            }
        }
    }

    pub fn readULEB128(self: *Machine, comptime T: type) !T {
        const U = if (@typeInfo(T).Int.bits < 8) u8 else T;
        const ShiftT = std.math.Log2Int(U);

        const max_group = (@typeInfo(U).Int.bits + 6) / 7;

        var value: U = 0;
        var group: ShiftT = 0;

        while (group < max_group) : (group += 1) {
            const byte = self.function.?.expr[self.pc];
            self.pc += 1;

            const ov = @shlWithOverflow(@as(U, byte & 0x7f), group * 7);
            if (ov[1] != 0) return error.Overflow;

            value |= ov[0];
            if (byte & 0x80 == 0) break;
        } else {
            return error.Overflow;
        }

        // only applies in the case that we extended to u8
        if (U != T) {
            if (value > std.math.maxInt(T)) return error.Overflow;
        }

        return @as(T, @truncate(value));
    }

    pub fn getI32FromStack(self: *Machine, idx: usize) !i32 {
        const set = self.stack.items[idx];
        switch (set) {
            .set_i32 => |v| {
                return v;
            },
            .set_frame => {
                return RuntimeError.WrongTypeOnStack;
            },
        }
    }

    fn opcodeSupported(self: *Machine, oc: u8) bool {
        _ = self; // autofix
        inline for (@typeInfo(Opcode).Enum.fields) |v| {
            if (v.value == oc) {
                return true;
            }
        }

        return false;
    }

    pub fn runFunction(self: *Machine, function: *Function) !void {
        self.function = function;
        self.pc = 0;

        std.log.info("Function {s} at {d} len {d}", .{ function.name, function.expr_idx, function.expr.len });
        util.printSlice(function.expr[0..]);

        // for (function.expr[0..]) |b| {
        //     std.debug.print("{x:0>2} ", .{b});
        // }
        // std.debug.print("\n", .{});

        const ty = self.module.types.items[self.function.?.type_id];

        self.param_stack_idx = self.stack.items.len - ty.param_type.len;

        while (true) {
            self.printStack();
            if (self.pc >= self.function.?.expr.len) {
                std.log.info("--> ran out of expressions", .{});
                break;
            }
            const op_b = self.function.?.expr[self.pc];

            if (!self.opcodeSupported(op_b)) {
                std.log.err("{s} : Op 0x{x} at {d} not implemented", .{ @src().fn_name, op_b, self.pc });
                return RuntimeError.UnsupportedOpCode;
            }

            const op = @as(Opcode, @enumFromInt(op_b));
            std.log.info("--> {d:0>4} : {s}", .{ self.pc, @tagName(op) });

            self.pc += 1;
            switch (op) {
                .end => {
                    break;
                },
                .call => {
                    const v = try self.readULEB128(u32);
                    // fixme: call
                    // local or imported...

                    if (v < self.module.local_function_index) {
                        // imported

                        const call_fn = self.module.functions.items[v];
                        std.log.info("ADD 1", .{});
                        if (std.mem.eql(u8, call_fn.name, "add")) {
                            std.log.info("ADD 2", .{});
                            const v0 = try self.popInteger();
                            const v1 = try self.popInteger();
                            std.log.info("ADD {d} {d}", .{ v0, v1 });
                            try self.pushI32(v0 + v1);
                        }
                    } else {
                        // local
                        std.log.err("{s} : Op 0x{x} not implemented", .{ @src().fn_name, @intFromEnum(op) });
                        return RuntimeError.NotImplemented;
                    }
                },
                .local_get => {
                    // fixme: index != 0?
                    std.log.info("local.get {d} of {d}", .{ self.param_stack_idx, self.stack.items.len });
                    const v = try self.getI32FromStack(self.param_stack_idx);
                    try self.pushI32(v);
                    self.pc += 1;
                },
                .i32_const => {
                    const v = try self.readULEB128(i32);
                    try self.pushI32(v);
                },
                .i32_add => {
                    const v0 = try self.popInteger();
                    const v1 = try self.popInteger();

                    try self.pushI32(v0 + v1);
                },
                else => {
                    std.log.err("{s} : Op 0x{x} {s} not implemented", .{ @src().fn_name, @intFromEnum(op), @tagName(op) });
                    return RuntimeError.NotImplemented;
                },
            }
        }
    }
};
