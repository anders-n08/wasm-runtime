const std = @import("std");

const Store = @import("store.zig").Store;
const FuncInst = @import("store.zig").FuncInst;
const Opcode = @import("types.zig").Opcode;

const MachineError = error{
    NotImplemented,
    InvalidType,
    NotFound,
};

const Frame = struct {
    function: FuncInst,
    local_stack_idx: u32 = 0,
    params_on_stack: u32 = 0,
};

pub const Machine = struct {
    allocator: std.mem.Allocator,

    store: *Store,

    value_stack: std.ArrayList(u32),
    frame_stack: std.ArrayList(Frame),

    params_on_stack: u32 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        store: *Store,
    ) Machine {
        return .{
            .allocator = allocator,
            .store = store,
            .value_stack = std.ArrayList(u32).init(allocator),
            .frame_stack = std.ArrayList(Frame).init(allocator),
        };
    }

    pub fn deinit(self: *Machine) void {
        self.value_stack.clearAndFree();
        self.frame_stack.clearAndFree();
    }

    pub fn prepareFunction(self: *Machine, name: []const u8) !void {
        var function: FuncInst = undefined;

        for (self.store.functions.items) |f| {
            if (std.mem.eql(u8, name, f.name)) {
                function = f;
                break;
            }
        } else {
            return MachineError.NotFound;
        }

        const frame = Frame{
            .function = function,
            .local_stack_idx = @as(u32, @intCast(self.value_stack.items.len)),
            .params_on_stack = 0,
        };
        try self.frame_stack.append(frame);
    }

    pub fn pushParam(self: *Machine, comptime T: type, value: T) !void {
        try self.push(T, value);
        var frame = self.frame_stack.getLast();
        frame.params_on_stack += 1;
    }

    pub fn callExternFunc(self: *Machine, idx: u32) !void {
        const imp = self.store.imports.items[idx];
        if (imp.cb) |cb| {
            try cb(self);
        }
    }

    pub fn executeFunction(self: *Machine) !void {
        const frame = self.frame_stack.getLast();
        const function = frame.function;

        for (0..function.code.locals_i32_count) |_| {
            try self.value_stack.append(0);
        }

        var expr = function.expr;
        var op = try expr.readEnum(Opcode);
        while (op != .end) {
            switch (op) {
                .call => {
                    const funcidx = try expr.readInt(u32);
                    try self.callExternFunc(funcidx);
                },
                .local_get => {
                    const idx = try expr.readInt(u32);
                    const v = self.value_stack.items[frame.local_stack_idx + idx];
                    try self.push(u32, v);
                },
                .i32_add => {
                    const v0 = try self.pop(i32);
                    const v1 = try self.pop(i32);
                    try self.push(i32, v0 + v1);
                },
                .i32_sub => {
                    const v0 = try self.pop(i32);
                    const v1 = try self.pop(i32);
                    try self.push(i32, v1 - v0);
                },
                else => return MachineError.NotImplemented,
            }

            op = try expr.readEnum(Opcode);
        }

        for (0..frame.params_on_stack) |_| {
            _ = self.value_stack.pop();
        }

        _ = self.frame_stack.pop();
    }

    pub fn push(self: *Machine, comptime T: type, value: T) !void {
        const v: u32 = switch (T) {
            u8, u16, u32 => value,
            i8, i16, i32 => @as(u32, @bitCast(@as(i32, @intCast(value)))),
            else => return MachineError.InvalidType,
        };
        try self.value_stack.append(v);
    }

    pub fn pop(self: *Machine, comptime T: type) !T {
        const v = switch (T) {
            u8, u16, u32 => @as(T, @truncate(self.value_stack.pop())),
            i8, i16, i32 => @as(T, @truncate(@as(i32, @bitCast(self.value_stack.pop())))),
            else => return MachineError.InvalidType,
        };
        return v;
    }
};

const Module = @import("module.zig").Module;

test "Basic functionality" {
    const allocator = std.testing.allocator;

    const bin = @embedFile("test/add_and_sub.wasm");
    var m = Module.init(allocator);
    defer m.deinit();
    try m.load(bin);

    var store = try Store.init(allocator, &m);
    defer store.deinit();

    var machine = Machine.init(allocator, &store);
    defer machine.deinit();

    try machine.push(u8, 100);
    try std.testing.expectEqual(try machine.pop(u8), 100);

    try machine.push(u16, 100);
    try std.testing.expectEqual(machine.pop(u16), 100);

    try machine.push(u32, 100);
    try std.testing.expectEqual(machine.pop(u32), 100);

    try machine.push(i8, -1);
    try std.testing.expectEqual(machine.pop(i8), -1);

    try machine.push(i16, -1);
    try std.testing.expectEqual(machine.pop(i16), -1);

    try machine.push(i32, -1);
    try std.testing.expectEqual(machine.pop(i32), -1);
}

test "Test add_and_sub" {
    const allocator = std.testing.allocator;

    const bin = @embedFile("test/add_and_sub.wasm");
    var m = Module.init(allocator);
    defer m.deinit();
    try m.load(bin);

    var store = try Store.init(allocator, &m);
    defer store.deinit();

    var machine = Machine.init(allocator, &store);
    defer machine.deinit();

    try machine.prepareFunction("add");
    try machine.pushParam(i32, 22);
    try machine.pushParam(i32, 20);
    try machine.executeFunction();
    try std.testing.expectEqual(42, machine.pop(i32));

    try machine.prepareFunction("add");
    try machine.pushParam(i32, 42);
    try machine.pushParam(i32, 20);
    try machine.executeFunction();
    try std.testing.expectEqual(62, machine.pop(i32));

    try machine.prepareFunction("add");
    try machine.pushParam(i32, 42);
    try machine.pushParam(i32, -64);
    try machine.executeFunction();
    try std.testing.expectEqual(-22, machine.pop(i32));

    try machine.prepareFunction("sub");
    try machine.pushParam(i32, 42);
    try machine.pushParam(i32, 20);
    try machine.executeFunction();
    try std.testing.expectEqual(22, machine.pop(i32));
}

fn add(machine: *Machine) anyerror!void {
    const v0 = try machine.pop(i32);
    const v1 = try machine.pop(i32);
    try machine.push(i32, v0 + v1);
}

test "Test function_call" {
    const allocator = std.testing.allocator;

    const bin = @embedFile("test/function_call.wasm");
    var m = Module.init(allocator);
    defer m.deinit();
    try m.load(bin);

    var store = try Store.init(allocator, &m);
    defer store.deinit();

    try store.addCallback("add", &add);

    var machine = Machine.init(allocator, &store);
    defer machine.deinit();

    try machine.prepareFunction("add_with_offset");
    try machine.pushParam(i32, 10);
    try machine.pushParam(i32, 20);
    try machine.pushParam(i32, 30);
    try machine.executeFunction();
    try std.testing.expectEqual(60, machine.pop(i32));
}
