const std = @import("std");
const types = @import("types.zig");
const util = @import("util.zig");

const Opcode = types.Opcode;
const Data = types.Data;
const ValueType = types.ValueType;
const Mut = types.Mut;
const ExportDesc = types.ExportDesc;

const ParseError = error{
    Invalid,
    NotImplemented,
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

    pub fn printSection(section_name: []const u8, reader: anytype, section_len: u32) void {
        // fixme: One space to little on pad line when last line has less than 8 bytes.
        // fixme: One charactor too many when first line has less than 8 bytes.
        std.debug.print("--- section {s} ---\n", .{section_name});
        util.printSlice(reader.context.buffer[reader.context.pos .. reader.context.pos + section_len]);
    }

    pub fn readTypeSection(self: *Module, reader: anytype) !void {
        const section_len = try std.leb.readULEB128(u32, reader);
        Module.printSection("Type", reader, section_len);

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
        Module.printSection("Function", reader, section_len);

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

    pub fn readGlobalSection(self: *Module, reader: anytype) !void {
        _ = self; // autofix
        const section_len = try Module.readULEB128(u32, reader);
        const section_pos = reader.context.pos;
        _ = section_pos; // autofix

        Module.printSection("Global", reader, section_len);

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

            // std.log.err("{s} : Mut to read at 0x{x}", .{ @src().fn_name, reader.context.pos - section_pos });
            const mut = try Module.readType(Mut, reader);
            _ = mut; // autofix

            // fixme: should we execute the expression?

            var op = try Module.readType(Opcode, reader);
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

                op = try Module.readType(Opcode, reader);
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

                var op = try Module.readType(Opcode, reader);
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

                    op = try Module.readType(Opcode, reader);
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

pub const Function = struct {
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
