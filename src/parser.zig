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
};

const StackEntryType = enum {
    set_i32,
    set_frame,
};

pub const StackEntry = union(StackEntryType) {
    set_i32: i32,
    set_frame: i32,
};

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

    pub fn runFunction(self: *Machine, function: *Function) !void {
        self.function = function;
        self.pc = 0;

        self.param_stack_idx = self.stack.items.len - function.param_type.len;

        while (true) {
            std.log.info("--> pc {d} param idx {d}", .{ self.pc, self.param_stack_idx });
            self.printStack();
            if (self.pc >= self.function.?.expr.len) {
                std.log.info("--> ran out of expressions", .{});
                break;
            }
            const op_b = self.function.?.expr[self.pc];
            std.log.info("--> {x}", .{op_b});
            const op = @as(Opcode, @enumFromInt(op_b));
            self.pc += 1;
            switch (op) {
                .end => {
                    break;
                },
                .local_get => {
                    // fixme: index != 0?
                    const v = try self.getI32FromStack(self.param_stack_idx);
                    std.log.info("local.get v {d}\n", .{v});
                    try self.pushI32(v);
                    self.pc += 1;
                },
                .i32_const => {
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

// fixme: Is this an Instance?
pub const Context = struct {
    allocator: std.mem.Allocator,
    functions: std.ArrayList(Function),

    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .allocator = allocator,
            .functions = std.ArrayList(Function).init(allocator),
        };
    }

    pub fn print(self: Context) void {
        std.log.info("--- context ---", .{});
        for (self.functions.items) |*f| {
            f.print();
        }
    }
};

const Frame = struct {
    return_arity: u32 = 0,
};

const Function = struct {
    allocator: std.mem.Allocator,
    id: u32,
    param_type: []u8,
    result_type: []u8,

    name: []u8 = undefined,
    expr: []u8 = undefined,

    pub fn init(
        allocator: std.mem.Allocator,
        id: u32,
        param_type: []u8,
        result_type: []u8,
    ) Function {
        return .{
            .allocator = allocator,
            .id = id,
            .param_type = param_type,
            .result_type = result_type,
        };
    }

    pub fn setLocal(self: *Function, comptime T: type, index: usize, value: T) !void {
        _ = self; // autofix
        _ = index; // autofix
        _ = value; // autofix
        switch (T) {
            i32 => {},
            i64 => {},
            f32 => {},
            f64 => {},
            else => {},
        }

        // _ = value; // autofix
        // if (self.locals.len > index) {}
    }

    pub fn print(self: *Function) void {
        std.log.info("Function", .{});
        std.log.info("  Name {s}", .{self.name});

        for (self.param_type) |v| {
            const vt = @as(ValueType, @enumFromInt(v));
            std.log.info("  Parameter {x} {s}", .{ v, @tagName(vt) });
        }

        for (self.result_type) |v| {
            const vt = @as(ValueType, @enumFromInt(v));
            std.log.info("  Result {x} {s}", .{ v, @tagName(vt) });
        }
        std.log.info("  Expressions nr {d}", .{self.expr.len});
        for (self.expr) |e| {
            std.log.info("    : {x}", .{e});
        }
        std.log.info("--- end of function", .{});
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
    std.log.info("Section len {d}", .{section_len});
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

        std.log.info("!!!!!!! Init function {d}\n", .{i});
        const function = Function.init(
            allocator,
            i,
            reader.context.buffer[vec_param_type_pos .. vec_param_type_pos + vec_param_type_count],
            reader.context.buffer[vec_result_type_pos .. vec_result_type_pos + vec_result_type_count],
        );
        try context.functions.append(function);
    }
}

pub fn readCodeSection(reader: anytype, context: *Context) !void {
    std.log.info("reader pos 0 {x}", .{reader.context.pos});
    const section_len = try std.leb.readULEB128(u32, reader);
    _ = section_len;

    std.log.info("reader pos 1 {x}", .{reader.context.pos});
    const vec_function_count = try std.leb.readULEB128(u32, reader);
    std.log.info("reader pos 2 {x}", .{reader.context.pos});
    var i: u32 = 0;
    while (i < vec_function_count) : (i += 1) {
        std.log.info("!!!!!!! Init code {d}\n", .{i});
        std.log.info("reader pos {x}", .{reader.context.pos});

        const code_block_len = try std.leb.readULEB128(u32, reader);
        const code_block_pos = reader.context.pos;

        // -- locals

        // fixme:
        const p0 = reader.context.pos;
        const local_pos = reader.context.pos;
        const local_count = try std.leb.readULEB128(u32, reader);
        _ = local_count;

        // -- function body i.e. expression

        const expr_pos = reader.context.pos;
        std.log.info("{d} cb len {d} local pos {d} cb pos {d}", .{ p0, code_block_len, local_pos, code_block_pos });
        const skip_len = code_block_len - (expr_pos - local_pos);
        reader.skipBytes(skip_len, .{}) catch |err| {
            // fixme: Make sure that we end the loop if we reach the end of the stream.
            if (err != error.EndOfStream) {
                return err;
            }
        };

        var function = &context.functions.items[i];
        // fixme: locals
        // function.locals = reader.context.buffer[local_pos..expr_pos];
        std.log.info("expr pos {d} reader pos {d}", .{ expr_pos, reader.context.pos });
        function.expr = reader.context.buffer[expr_pos..reader.context.pos];

        std.log.info("!!", .{});
        for (function.expr) |x| {
            std.log.info("!! {x}", .{x});
        }
    }
}

pub fn readExportSection(reader: anytype, context: *Context) !void {
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
                    // fixme: Is this ok? Function only holds slices to a static memory. Or should
                    // I handle the allocations?
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
        std.log.info("Section {s}", .{@tagName(section_id)});
        switch (section_id) {
            .id_custom => {
                try skipSection(&reader);
            },
            .id_type => {
                try readTypeSection(allocator, &reader, machine.context);
            },
            .id_import => {
                try skipSection(&reader);
            },
            .id_function => {
                try skipSection(&reader);
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
                try readExportSection(&reader, machine.context);
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

    machine.context.print();
}
