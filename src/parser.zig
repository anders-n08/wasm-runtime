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

    pub fn print(self: *Machine) void {
        for (self.module.functions.items) |f| {
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

        std.log.info("Function {s} at {d} len {d}", .{ function.name, function.expr_idx, function.expr.len });
        for (function.expr[0..]) |b| {
            std.debug.print("{x:0>2} ", .{b});
        }
        std.debug.print("\n", .{});

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
                else => return RuntimeError.NotImplemented,
            }
        }
    }
};

pub const Module = struct {
    allocator: std.mem.Allocator,
    types: std.ArrayList(Type),
    functions: std.ArrayList(Function),
    memory: std.ArrayList(u8),
    memory_len: u32 = 0, // Allocated memory
    local_function_index: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) Module {
        return .{
            .allocator = allocator,
            .types = std.ArrayList(Type).init(allocator),
            .functions = std.ArrayList(Function).init(allocator),
            .memory = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn readerPos(reader: anytype) u32 {
        const pos = @as(u32, @intCast(reader.context.pos));
        return pos;
    }

    pub fn readULEB128(T: type, reader: anytype) !T {
        return try std.leb.readULEB128(T, reader);
    }

    pub fn read(T: type, reader: anytype) !T {
        switch (T) {
            u8, u16, u32, i8, i16, i32 => return try reader.readInt(T, std.builtin.Endian.little),
            else => return ParseError.Invalid,
        }
    }

    pub fn readType(T: type, reader: anytype) !T {
        const v = try Module.read(@typeInfo(T).Enum.tag_type, reader);
        std.log.info("readType value {d}", .{v});
        return @as(T, @enumFromInt(v));
    }

    pub fn skipBytes(len: u32, reader: anytype) !void {
        try reader.skipBytes(len, .{});
    }

    pub fn skipSection(self: *Module, reader: anytype) !void {
        _ = self; // autofix
        const section_len = try std.leb.readULEB128(u32, reader);
        try reader.skipBytes(section_len, .{});
    }

    pub fn readTypeSection(self: *Module, reader: anytype) !void {
        const section_len = try std.leb.readULEB128(u32, reader);
        _ = section_len;

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
                self.allocator,
                i,
                reader.context.buffer[vec_param_type_pos .. vec_param_type_pos + vec_param_type_count],
                reader.context.buffer[vec_result_type_pos .. vec_result_type_pos + vec_result_type_count],
            );
            try self.types.append(ty);
        }
    }

    pub fn readImportSection(self: *Module, reader: anytype) !void {
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
                var function = Function.init(self.allocator, i, ty);
                function.name = reader.context.buffer[import_name_start .. import_name_start + import_name_len];
                try self.functions.append(function);
            } else {
                std.log.err("{s} : Import descriptor {d} not supported", .{ @src().fn_name, import_desc });
                return ParseError.NotImplemented;
            }
        }
    }

    pub fn readFunctionSection(self: *Module, reader: anytype) !void {
        const section_len = try std.leb.readULEB128(u32, reader);
        _ = section_len;

        self.local_function_index = @as(u32, @intCast(self.functions.items.len));

        const id_base = @as(u32, @intCast(self.functions.items.len));

        // fixme: Should this be i128?
        const vec_type_count = try std.leb.readULEB128(u32, reader);
        var i: u32 = 0;
        while (i < vec_type_count) : (i += 1) {
            const ty = try std.leb.readULEB128(u32, reader);
            const function = Function.init(self.allocator, i + id_base, ty);
            try self.functions.append(function);
        }
    }

    pub fn readMemorySection(self: *Module, reader: anytype) !void {
        const section_len = try std.leb.readULEB128(u32, reader);
        _ = section_len;

        const vec_mem_count = try std.leb.readULEB128(u32, reader);
        var i: u32 = 0;
        while (i < vec_mem_count) : (i += 1) {
            if (i != 0) {
                std.log.err("{s} - Only memory index 0 supported", .{@src().fn_name});
                return ParseError.NotImplemented;
            }
            const limit_ty = try std.leb.readULEB128(u32, reader);
            if (limit_ty == 0x00) {
                const limit_min = try std.leb.readULEB128(u32, reader);
                std.log.info("mem limit min {d}", .{limit_min});
                try self.memory.ensureTotalCapacity(limit_min * 0x10000);
                self.memory_len = limit_min * 0x10000;
            } else if (limit_ty == 0x01) {
                std.log.err("{s} : Limit type {d} not implemented", .{ @src().fn_name, limit_ty });
                return ParseError.NotImplemented;
                // const limit_min = try std.leb.readULEB128(u32, reader);
                // const limit_max = try std.leb.readULEB128(u32, reader);
                // std.log.info("mem limit min {d} limit max {d}", .{ limit_min, limit_max });
            } else {
                return ParseError.Invalid;
            }
        }
    }

    pub fn readCodeSection(self: *Module, reader: anytype) !void {
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

            var function = &self.functions.items[self.local_function_index + i];
            // fixme: locals
            // function.locals = reader.context.buffer[local_pos..expr_pos];
            function.expr = reader.context.buffer[expr_pos..reader.context.pos];
            function.expr_idx = @as(u32, @intCast(expr_pos));
        }
    }

    // Contents of section Global:
    // 000003c: 067f 0141 80c0 000b 7f00 4194 c000 0b7f  ...A......A.....
    // 000004c: 0041 80c0 000b 7f00 4194 e000 0b7f 0041  .A......A......A
    // 000005c: 84c0 000b 7f00 4190 c000 0b              ......A....
    //
    //   (global (;0;) (mut i32) (i32.const 8192))
    //   (global (;1;) i32 (i32.const 8212))
    //   (global (;2;) i32 (i32.const 8192))
    //   (global (;3;) i32 (i32.const 12308))
    //   (global (;4;) i32 (i32.const 8196))
    //   (global (;5;) i32 (i32.const 8208))
    //   (export "memory" (memory 0))
    //   (export "framebuffer" (global 1))
    //   (export "my_global2" (global 2))
    //   (export "framebuffer2" (global 3))
    //   (export "my_array" (global 4))
    //   (export "my_global" (global 5))

    pub fn readGlobalSection(self: *Module, reader: anytype) !void {
        _ = self; // autofix
        const section_len = try Module.readULEB128(u32, reader);
        _ = section_len;

        const p0 = Module.readerPos(reader);
        _ = p0; // autofix
        const vec_mem_count = try Module.readULEB128(u32, reader);

        var i: u32 = 0;
        while (i < vec_mem_count) : (i += 1) {
            const value_type = try Module.readType(ValueType, reader);
            switch (value_type) {
                .vt_i32 => {},
                .vt_f32 => return ParseError.Invalid,
            }

            const mut = try Module.readType(Mut, reader);
            _ = mut; // autofix

            // fixme: should we execute the expression?

            var op = try Module.readType(opcode.Opcode, reader);
            while (op != .end) {
                switch (op) {
                    .i32_const => {
                        const v = try Module.readULEB128(i32, reader);
                        _ = v; // autofix
                    },
                    else => {
                        std.log.err("{s} : Op code {d} not implemented", .{ @src().fn_name, @intFromEnum(op) });
                        return ParseError.NotImplemented;
                    },
                }

                op = try Module.readType(opcode.Opcode, reader);
            }
        }
    }

    // Contents of section Export:
    // 0000069: 0c06 6d65 6d6f 7279 0200 0574 6573 7431  ..memory...test1
    // 0000079: 0001 0574 6573 7432 0002 0574 6573 7433  ...test2...test3
    // 0000089: 0003 0b66 7261 6d65 6275 6666 6572 0301  ...framebuffer..
    // 0000099: 0370 7472 0004 0373 6662 0005 0367 6662  .ptr...sfb...gfb
    // 00000a9: 0006 0a6d 795f 676c 6f62 616c 3203 020c  ...my_global2...
    // 00000b9: 6672 616d 6562 7566 6665 7232 0303 086d  framebuffer2...m
    // 00000c9: 795f 6172 7261 7903 0409 6d79 5f67 6c6f  y_array...my_glo
    // 00000d9: 6261 6c03 05                             bal..
    pub fn readExportSection(self: *Module, reader: anytype) !void {
        const section_len = try Module.readULEB128(u32, reader);
        _ = section_len;

        const vec_export_count = try Module.readULEB128(u32, reader);
        var i: u32 = 0;
        while (i < vec_export_count) : (i += 1) {
            const name_len = try Module.readULEB128(u32, reader);
            const name_pos = reader.context.pos;
            try reader.skipBytes(name_len, .{});

            const exportdesc = try Module.readType(ExportDesc, reader);

            switch (exportdesc) {
                .func => {
                    const funcidx = try Module.read(u8, reader);
                    if (funcidx < self.functions.items.len) {
                        var function = &self.functions.items[funcidx];
                        function.name = reader.context.buffer[name_pos .. name_pos + name_len];
                    }
                },
                .mem => {
                    const memidx = try Module.read(u8, reader);
                    _ = memidx; // autofix
                },
                .table => {
                    const tableidx = try Module.read(u8, reader);
                    _ = tableidx; // autofix
                },
                .global => {
                    const blobalidx = try Module.read(u8, reader);
                    _ = blobalidx; // autofix
                },
            }
        }
    }

    pub fn readDataSection(self: *Module, reader: anytype) !void {
        _ = self; // autofix
        const section_len = try Module.readULEB128(u32, reader);
        _ = section_len;

        const vec_data_count = try Module.readULEB128(u32, reader);
        var i: u32 = 0;
        while (i < vec_data_count) : (i += 1) {
            // (memory (;0;) 1)
            //
            // (global (;2;) i32 (i32.const 8192))
            // (global (;4;) i32 (i32.const 8196))
            //
            // (export "my_global2" (global 2))
            // (export "my_array" (global 4))
            //
            // (data (;0;) (i32.const 8192) "4\12\00\00")
            // (data (;1;) (i32.const 8196) "\01\02\03\04\05\06\07\08\09\00\00\004\12\00\00"))
            //
            // Contents of section Data:
            // 0000131: 0200 4180 c000 0b04 3412 0000 0041 84c0  ..A.....4....A..
            // 0000141: 000b 1001 0203 0405 0607 0809 0000 0034  ...............4
            // 0000151: 1200 00

            // Notes:
            // Data has no (in data format) connection to globals.
            // It just shares memory locations.

            std.log.info("pos {d}", .{Module.readerPos(reader)});
            const data_ty = try Module.readType(Data, reader);

            std.log.info("data ty {d}", .{@intFromEnum(data_ty)});

            // data_ty    02
            //
            // memidx     00
            // i32_const  41
            // 8192       80 c0 00
            // end        0b
            // memcount   04
            // bytes      34 12 00 00
            //
            // 0041 84c0  ..A.....4....A..
            //

            if (data_ty == .active_mem_0 or data_ty == .active_mem_x) {
                const memidx = blk: {
                    if (data_ty == .active_mem_0) {
                        break :blk 0;
                    }
                    break :blk try Module.readULEB128(u32, reader);
                };

                if (memidx != 0) {
                    return ParseError.NotImplemented;
                }

                var op = try Module.readType(opcode.Opcode, reader);
                while (op != .end) {
                    switch (op) {
                        .i32_const => {
                            const v = try Module.readULEB128(i32, reader);
                            _ = v; // autofix
                        },
                        else => {
                            std.log.err("{s} : Op code {d} not implemented", .{ @src().fn_name, @intFromEnum(op) });
                            return ParseError.NotImplemented;
                        },
                    }

                    op = try Module.readType(opcode.Opcode, reader);
                }

                const vec_byte_count = try Module.readULEB128(u32, reader);
                // fixme: This data should be copied to the v extracted above...
                try Module.skipBytes(vec_byte_count, reader);
            } else {
                std.log.err("{s} - data type {d} not implemented", .{ @src().fn_name, @intFromEnum(data_ty) });
                return ParseError.NotImplemented;
            }
        }
    }

    pub fn parse(self: *Module, source: []u8) !void {
        var stream = std.io.fixedBufferStream(source[0..]);
        var reader = stream.reader();
        _ = try reader.readInt(u32, std.builtin.Endian.little); // magic
        _ = try reader.readInt(u32, std.builtin.Endian.little); // version

        while (true) {
            // fixme: Only expect eof stream.
            const section_id_int = reader.readByte() catch break;
            // fixme: Can fail enum conversion.
            const section_id = @as(SectionId, @enumFromInt(section_id_int));

            std.log.info("--- read section {d} ---", .{section_id_int});

            switch (section_id) {
                .id_custom => {
                    try self.skipSection(reader);
                },
                .id_type => {
                    try self.readTypeSection(reader);
                },
                .id_import => {
                    try self.readImportSection(reader);
                },
                .id_function => {
                    try self.readFunctionSection(reader);
                },
                .id_table => {
                    try self.skipSection(reader);
                },
                .id_memory => {
                    try self.readMemorySection(reader);
                },
                .id_global => {
                    try self.readGlobalSection(reader);
                },
                .id_export => {
                    try self.readExportSection(reader);
                },
                .id_start => {
                    try self.skipSection(reader);
                },
                .id_element => {
                    try self.skipSection(reader);
                },
                .id_code => {
                    try self.readCodeSection(reader);
                },
                .id_data => {
                    try self.readDataSection(reader);
                },
                .id_data_count => {
                    try self.skipSection(reader);
                },
            }
        }
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

    name: []u8 = &.{},
    expr: []u8 = &.{},
    expr_idx: u32 = 0,

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
};

const Mut = enum(u8) {
    mut_const = 0,
    mut_var = 1,
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
    func = 0x00,
    table = 0x01,
    mem = 0x02,
    global = 0x03,
};

const Data = enum(u8) {
    active_mem_0 = 0x00,
    passive = 0x01,
    active_mem_x = 0x02,
};
