const std = @import("std");
const opcode = @import("opcode.zig");

const Opcode = opcode.Opcode;

const ParseError = error{
    Invalid,
    NotImplemented,
};

const RuntimeError = error{
    FunctionNotFound,
    WrongTypeOnStack,
    UnsupportedOpCode,
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
    context: *Context,

    pc: usize = 0,
    function: ?*Function = null,
    param_stack_idx: usize = 0,

    pub fn init(allocator: std.mem.Allocator, context: *Context) Machine {
        return .{
            .allocator = allocator,
            .stack = std.ArrayList(StackEntry).init(allocator),
            .context = context,
        };
    }

    pub fn print(self: *Machine) void {
        for (self.context.functions.items) |f| {
            std.log.info("Fn name {s} type {d}", .{ f.name, f.type_id });

            std.log.info("  expr", .{});
            for (f.expr) |b| {
                std.log.info("  {x}", .{b});
            }
        }
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
        for (self.context.functions.items) |*f| {
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
        inline for (@typeInfo(opcode.Opcode).Enum.fields) |v| {
            if (v.value == oc) {
                return true;
            }
        }

        return false;
    }

    pub fn runFunction(self: *Machine, function: *Function) !void {
        self.function = function;
        self.pc = 0;

        const ty = self.context.types.items[self.function.?.type_id];

        self.param_stack_idx = self.stack.items.len - ty.param_type.len;

        while (true) {
            self.printStack();
            if (self.pc >= self.function.?.expr.len) {
                std.log.info("--> ran out of expressions", .{});
                break;
            }
            const op_b = self.function.?.expr[self.pc];

            if (!self.opcodeSupported(op_b)) {
                return RuntimeError.UnsupportedOpCode;
            }

            const op = @as(Opcode, @enumFromInt(op_b));
            self.pc += 1;
            switch (op) {
                .end => {
                    break;
                },
                .call => {
                    const v = try self.readULEB128(u32);
                    _ = v; // autofix
                    // fixme: call
                },
                .local_get => {
                    // fixme: index != 0?
                    std.log.info("local.get {d} of {d}", .{ self.param_stack_idx, self.stack.items.len });
                    const v = try self.getI32FromStack(self.param_stack_idx);
                    try self.pushI32(v);
                    self.pc += 1;
                },
                .i32_const => {
                    // fixme: Är inte detta LEB128?
                    const v = self.function.?.expr[self.pc];
                    try self.pushI32(v);
                    self.pc += 1;
                },
                .i32_add => {
                    const v0 = try self.popInteger();
                    const v1 = try self.popInteger();

                    try self.pushI32(v0 + v1);
                },
            }
        }
    }
};

// fixme: Is this an Instance? Or a Mocdule
pub const Context = struct {
    allocator: std.mem.Allocator,
    types: std.ArrayList(Type),
    functions: std.ArrayList(Function),
    local_function_index: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .allocator = allocator,
            .types = std.ArrayList(Type).init(allocator),
            .functions = std.ArrayList(Function).init(allocator),
        };
    }
};

const Frame = struct {
    return_arity: u32 = 0,
};

const Type = struct {
    allocator: std.mem.Allocator,
    id: u32,
    param_type: []u8,
    result_type: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        id: u32,
        param_type: []u8,
        result_type: []u8,
    ) Type {
        return .{
            .allocator = allocator,
            .id = id,
            .param_type = param_type,
            .result_type = result_type,
        };
    }
};

const Function = struct {
    allocator: std.mem.Allocator,
    id: u32,
    type_id: u32,

    name: []u8 = undefined,
    expr: []u8 = undefined,

    pub fn init(
        allocator: std.mem.Allocator,
        id: u32,
        type_id: u32,
    ) Function {
        return .{
            .allocator = allocator,
            .id = id,
            .type_id = type_id,
        };
    }

    pub fn print(self: *Function) void {
        std.log.info("Function", .{});
        std.log.info("  Name {s}", .{self.name});
        std.log.info("  Type {d}", .{self.type_id});

        // for (self.param_type) |v| {
        //     const vt = @as(ValueType, @enumFromInt(v));
        //     std.log.info("  Parameter {x} {s}", .{ v, @tagName(vt) });
        // }
        //
        // for (self.result_type) |v| {
        //     const vt = @as(ValueType, @enumFromInt(v));
        //     std.log.info("  Result {x} {s}", .{ v, @tagName(vt) });
        // }
        // std.log.info("  Expressions nr {d}", .{self.expr.len});
        // for (self.expr) |e| {
        //     std.log.info("    : {x}", .{e});
        // }
        // std.log.info("--- end of function", .{});
    }
};

const SectionId = enum(u8) {
    id_custom,
    id_type,
    id_import,
    id_function,
    id_table,
    id_memory,
    id_global,
    id_export,
    id_start,
    id_element,
    id_code,
    id_data,
    id_data_count,
};

const ValueType = enum(u8) {
    vt_i32 = 0x7f,
    vt_f32 = 0x7d,

    // vt_i64 = 0x7e,
    // vt_f64 = 0x7c,
    // fixme: vt_v128 = 0x7b,
    // fixme: vt_funcref = 0x70,
    // fixme: vt_externref = 0x6f,

    pub fn readEnum(reader: anytype) !ValueType {
        const vt_b = try reader.readByte();
        return @as(ValueType, @enumFromInt(vt_b));
    }
};

pub const Value = union(ValueType) {
    vt_i32: i32,
    vt_f32: f32,

    // vt_i64: i64,
    // vt_f64: f64,
    // fixme: vt_v128:
    // fixme: vt_funcref:
    // fixme: vt_externref:
};

const ExportDesc = enum(u8) {
    funcidx = 0x00,
    tableidx = 0x01,
    memidx = 0x02,
    globalidx = 0x03,
};

// fixme: anytype
pub fn skipSection(reader: anytype) !void {
    // std.log.info("{s}", .{@typeName(@TypeOf(reader))});
    const section_len = try std.leb.readULEB128(u32, reader);
    try reader.skipBytes(section_len, .{});
}

pub fn readTypeSection(allocator: std.mem.Allocator, reader: anytype, context: *Context) !void {
    const section_len = try std.leb.readULEB128(u32, reader);
    _ = section_len;

    // fixme: Should this be i128?
    const vec_type_count = try std.leb.readULEB128(u32, reader);
    var i: u32 = 0;
    while (i < vec_type_count) : (i += 1) {
        const functype = try reader.readByte();
        if (functype != 0x60) {
            return ParseError.Invalid;
        }

        const vec_param_type_count = try std.leb.readULEB128(u32, reader);
        const vec_param_type_pos = reader.context.pos;
        try reader.skipBytes(vec_param_type_count, .{});

        const vec_result_type_count = try std.leb.readULEB128(u32, reader);
        const vec_result_type_pos = reader.context.pos;
        try reader.skipBytes(vec_result_type_count, .{});

        const ty = Type.init(
            allocator,
            i,
            reader.context.buffer[vec_param_type_pos .. vec_param_type_pos + vec_param_type_count],
            reader.context.buffer[vec_result_type_pos .. vec_result_type_pos + vec_result_type_count],
        );
        try context.types.append(ty);
    }
}

pub fn readImportSection(allocator: std.mem.Allocator, reader: anytype, context: *Context) !void {
    const section_len = try std.leb.readULEB128(u32, reader);
    _ = section_len;

    const vec_import_count = try std.leb.readULEB128(u32, reader);
    var i: u32 = 0;
    while (i < vec_import_count) : (i += 1) {
        const module_name_len = try std.leb.readULEB128(u32, reader);
        try reader.skipBytes(module_name_len, .{});
        const import_name_len = try std.leb.readULEB128(u32, reader);
        const import_name_start = @as(u32, @intCast(reader.context.pos));
        try reader.skipBytes(import_name_len, .{});
        const import_desc = try reader.readByte();

        // 0x00 typeidx
        // 0x01 tabletype
        // 0x02 memtype
        // 0x03 globaltype

        if (import_desc == 0x00) {
            const ty = try reader.readByte();
            var function = Function.init(allocator, i, ty);
            function.name = reader.context.buffer[import_name_start .. import_name_start + import_name_len];
            function.expr = &.{};
            try context.functions.append(function);
        } else {
            return ParseError.NotImplemented;
        }
    }
}

pub fn readFunctionSection(allocator: std.mem.Allocator, reader: anytype, context: *Context) !void {
    const section_len = try std.leb.readULEB128(u32, reader);
    _ = section_len;

    context.local_function_index = @as(u32, @intCast(context.functions.items.len));

    const id_base = @as(u32, @intCast(context.functions.items.len));

    // fixme: Should this be i128?
    const vec_type_count = try std.leb.readULEB128(u32, reader);
    var i: u32 = 0;
    while (i < vec_type_count) : (i += 1) {
        const ty = try std.leb.readULEB128(u32, reader);
        const function = Function.init(allocator, i + id_base, ty);
        try context.functions.append(function);
    }
}

pub fn readCodeSection(reader: anytype, context: *Context) !void {
    const section_len = try std.leb.readULEB128(u32, reader);
    _ = section_len;

    const vec_function_count = try std.leb.readULEB128(u32, reader);
    var i: u32 = 0;
    while (i < vec_function_count) : (i += 1) {
        const code_block_len = try std.leb.readULEB128(u32, reader);
        const code_block_pos = reader.context.pos;
        _ = code_block_pos; // autofix

        // -- locals

        // fixme:
        const local_pos = reader.context.pos;
        const local_count = try std.leb.readULEB128(u32, reader);
        _ = local_count;

        // -- function body i.e. expression

        const expr_pos = reader.context.pos;
        const skip_len = code_block_len - (expr_pos - local_pos);
        reader.skipBytes(skip_len, .{}) catch |err| {
            // fixme: Make sure that we end the loop if we reach the end of the stream.
            if (err != error.EndOfStream) {
                return err;
            }
        };

        var function = &context.functions.items[context.local_function_index + i];
        // fixme: locals
        // function.locals = reader.context.buffer[local_pos..expr_pos];
        function.expr = reader.context.buffer[expr_pos..reader.context.pos];
    }
}

pub fn readExportSection(allocator: std.mem.Allocator, reader: anytype, context: *Context) !void {
    _ = allocator; // autofix
    const section_len = try std.leb.readULEB128(u32, reader);
    _ = section_len;

    const vec_export_count = try std.leb.readULEB128(u32, reader);
    var i: u32 = 0;
    while (i < vec_export_count) : (i += 1) {
        const export_len = try std.leb.readULEB128(u32, reader);
        const export_pos = reader.context.pos;
        try reader.skipBytes(export_len, .{});

        const export_desc_b = try reader.readByte();
        const export_index = try reader.readByte();

        const export_desc = @as(ExportDesc, @enumFromInt(export_desc_b));
        switch (export_desc) {
            .funcidx => {
                if (export_index < context.functions.items.len) {
                    var function = &context.functions.items[export_index];
                    function.name = reader.context.buffer[export_pos .. export_pos + export_len];
                }
            },
            .memidx => {
                // fixme:
                // return ParseError.NotImplemented;
            },
            .tableidx => {
                return ParseError.NotImplemented;
            },
            .globalidx => {
                return ParseError.NotImplemented;
            },
        }
    }
}

pub fn parse(allocator: std.mem.Allocator, source: []u8, machine: *Machine) !void {
    var stream = std.io.fixedBufferStream(source[0..]);
    var reader = stream.reader();
    _ = try reader.readInt(u32, std.builtin.Endian.little); // magic
    _ = try reader.readInt(u32, std.builtin.Endian.little); // version

    while (true) {
        // fixme: Only expect eof stream.
        const section_id_int = reader.readByte() catch break;
        // fixme: Can fail enum conversion.
        const section_id = @as(SectionId, @enumFromInt(section_id_int));
        switch (section_id) {
            .id_custom => {
                try skipSection(&reader);
            },
            .id_type => {
                try readTypeSection(allocator, &reader, machine.context);
            },
            .id_import => {
                try readImportSection(allocator, &reader, machine.context);
            },
            .id_function => {
                try readFunctionSection(allocator, &reader, machine.context);
            },
            .id_table => {
                try skipSection(&reader);
            },
            .id_memory => {
                try skipSection(&reader);
            },
            .id_global => {
                try skipSection(&reader);
            },
            .id_export => {
                try readExportSection(allocator, &reader, machine.context);
            },
            .id_start => {
                try skipSection(&reader);
            },
            .id_element => {
                try skipSection(&reader);
            },
            .id_code => {
                try readCodeSection(&reader, machine.context);
            },
            .id_data => {
                try skipSection(&reader);
            },
            .id_data_count => {
                try skipSection(&reader);
            },
        }
    }
}
