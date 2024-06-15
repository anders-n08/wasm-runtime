const std = @import("std");

const types = @import("types.zig");

const ModuleError = error{
    InvalidMagic,
    InvalidVersion,
    InvalidType,
    NotImplemented,
    NoData,
};

const SectionId = enum(u8) {
    custom,
    type,
    import,
    function,
    table,
    memory,
    global,
    @"export",
    start,
    element,
    code,
    data,
    data_count,
};

// ---

const ImportDescTy = enum(u8) {
    func = 0x00,
    table = 0x01,
    mem = 0x02,
    global = 0x03,
};

const LimitsTy = enum(u8) {
    min_only = 0x00,
    min_max = 0x01,
};

const ExportDescTy = enum(u8) {
    func = 0x00,
    table = 0x01,
    mem = 0x02,
    global = 0x03,
};

// ---

const FuncType = struct {
    idx: u32,
    param_type: []const u8,
    result_type: []const u8,
};

const Import = struct {
    idx: u32,
    module: []const u8,
    name: []const u8,
    importdesc: []const u8,
};

const Function = struct {
    idx: u32,
    typeidx: u32,
};

const Memory = struct {
    idx: u32,
    memtype: []const u8,
};

const Global = struct {
    idx: u32,
    // ---
    valtype: types.ValueType,
    mut: types.Mut,
    val: i32,
    // ---
    globaltype: []const u8,
    expr: []const u8,
};

const Export = struct {
    idx: u32,
    name: []const u8,
    exportdesc_ty: ExportDescTy,
    exportdesc_idx: u32,
};

const Start = struct {
    funcidx: u32,
};

pub const Code = struct {
    idx: u32,
    locals_i32_count: u32,
    locals_f32_count: u32,
    expr: []const u8,
};

// ---

pub const Module = struct {
    buf: []const u8,
    stream: std.io.FixedBufferStream([]const u8),
    reader: std.io.FixedBufferStream([]const u8).Reader,

    allocator: std.mem.Allocator,

    types: std.ArrayList(FuncType),
    imports: std.ArrayList(Import),
    functions: std.ArrayList(Function),
    memory: std.ArrayList(Memory),
    globals: std.ArrayList(Global),
    exports: std.ArrayList(Export),
    code: std.ArrayList(Code),

    start: ?Start = null,

    pub fn init(allocator: std.mem.Allocator) Module {
        return .{
            .allocator = allocator,
            .buf = undefined,
            .stream = undefined,
            .reader = undefined,
            .types = std.ArrayList(FuncType).init(allocator),
            .imports = std.ArrayList(Import).init(allocator),
            .functions = std.ArrayList(Function).init(allocator),
            .memory = std.ArrayList(Memory).init(allocator),
            .globals = std.ArrayList(Global).init(allocator),
            .exports = std.ArrayList(Export).init(allocator),
            .code = std.ArrayList(Code).init(allocator),
        };
    }

    pub fn deinit(self: *Module) void {
        self.types.clearAndFree();
        self.imports.clearAndFree();
        self.functions.clearAndFree();
        self.memory.clearAndFree();
        self.globals.clearAndFree();
        self.exports.clearAndFree();
        self.code.clearAndFree();
    }

    pub fn load(self: *Module, binary: []const u8) !void {
        self.buf = binary;
        self.stream = std.io.fixedBufferStream(self.buf);
        self.reader = self.stream.reader();

        const magic = try self.reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &magic, "\x00asm")) {
            return ModuleError.InvalidMagic;
        }
        const version = try self.reader.readInt(u32, .little);
        if (version != 0x00000001) {
            return ModuleError.InvalidVersion;
        }

        while (self.reader.context.pos < binary.len) {
            const section_id = try self.readEnum(SectionId);

            switch (section_id) {
                // zig fmt: off
                .custom     => try self.skipSection(),
                .type       => try self.readTypeSection(),
                .import     => try self.readImportSection(),
                .function   => try self.readFunctionSection(),
                .table      => try self.readTableSection(),
                .memory     => try self.readMemorySection(),
                .global     => try self.readGlobalSection(),
                .@"export"  => try self.readExportSection(),
                .start      => try self.readStartSection(),
                .element    => try self.readElementSection(),
                .code       => try self.readCodeSection(),
                .data       => try self.readDataSection(),
                .data_count => try self.readDataCount(),
                // zig fmt: on
            }
        }
    }

    fn readInt(self: *Module, comptime T: type) !T {
        switch (T) {
            u8 => return try self.reader.readByte(),
            i32 => return try std.leb.readILEB128(T, self.reader),
            u32 => return try std.leb.readULEB128(T, self.reader),
            else => return ModuleError.InvalidType,
        }
    }

    fn readString(self: *Module) ![]const u8 {
        const size = try self.readInt(u32);
        const pos = self.stream.pos;
        try self.reader.skipBytes(size, .{});

        return self.buf[pos..self.stream.pos];
    }

    fn readEnum(self: *Module, comptime T: type) !T {
        return try self.reader.readEnum(T, .little);
    }

    fn readOpAndArg(self: *Module) !types.Opcode {
        const op = try self.readEnum(types.Opcode);
        switch (op) {
            .end,
            .i32_add,
            => {},
            .call,
            .local_get,
            => {
                _ = try self.readInt(u32);
            },
            .i32_const,
            => {
                _ = try self.readInt(i32);
            },
            .i32_load,
            .i32_load8_s,
            .i32_load8_u,
            .i32_load16_s,
            .i32_load16_u,
            .i32_store,
            .i32_store8,
            .i32_store16,
            => {
                _ = try self.readInt(u32);
                _ = try self.readInt(u32);
            },
        }

        return op;
    }

    fn skipSection(self: *Module) !void {
        const section_size = try self.readInt(u32);
        try self.reader.skipBytes(section_size, .{});
    }

    fn readTypeSection(self: *Module) !void {
        const section_size = try self.readInt(u32);
        _ = section_size;

        const functype_count = try self.readInt(u32);

        try self.types.resize(functype_count);

        for (0..functype_count) |i| {
            const functype = try self.readInt(u8);
            if (functype != 0x60) {
                return ModuleError.InvalidType;
            }

            const param_pos = self.stream.pos;
            const param_count = try self.readInt(u32);
            // Only for validation.
            for (0..param_count) |_| {
                const param = try self.readEnum(types.ValueType);
                _ = param;
            }

            const result_pos = self.stream.pos;
            const result_count = try self.readInt(u32);
            // Only for validation.
            for (0..result_count) |_| {
                const result = try self.readEnum(types.ValueType);
                _ = result;
            }

            try self.types.append(.{
                .idx = @intCast(i),
                .param_type = self.buf[param_pos .. param_pos + param_count],
                .result_type = self.buf[result_pos .. result_pos + result_count],
            });
        }
    }

    fn readImportSection(self: *Module) !void {
        const section_size = try self.readInt(u32);
        _ = section_size;

        const import_count = try self.readInt(u32);
        for (0..import_count) |i| {
            const module = try self.readString();
            const name = try self.readString();

            const importdesc_pos = self.stream.pos;
            const importdesc_ty = try self.readEnum(ImportDescTy);
            switch (importdesc_ty) {
                .func => {
                    const typeidx = try self.readInt(u32);
                    _ = typeidx;
                },
                else => return ModuleError.NotImplemented,
            }

            try self.imports.append(.{
                .idx = @intCast(i),
                .module = module,
                .name = name,
                .importdesc = self.buf[importdesc_pos..self.stream.pos],
            });
        }
    }

    fn readFunctionSection(self: *Module) !void {
        const section_size = try self.readInt(u32);
        _ = section_size;

        const typeidx_count = try self.readInt(u32);
        for (0..typeidx_count) |i| {
            const typeidx = try self.readInt(u8);
            try self.functions.append(.{
                .idx = @intCast(i),
                .typeidx = typeidx,
            });
        }
    }

    fn readTableSection(self: *Module) !void {
        try self.skipSection();
    }

    fn readMemorySection(self: *Module) !void {
        const section_size = try self.readInt(u32);
        _ = section_size;

        const mem_count = try self.readInt(u32);
        for (0..mem_count) |i| {
            const memtype_pos = @as(u32, @intCast(self.stream.pos));
            const limits_ty = try self.readEnum(LimitsTy);
            switch (limits_ty) {
                .min_only => {
                    _ = try self.readInt(u32); // min
                },
                .min_max => {
                    _ = try self.readInt(u32); // min
                    _ = try self.readInt(u32); // max
                },
            }

            try self.memory.append(.{
                .idx = @intCast(i),
                .memtype = self.buf[memtype_pos..self.stream.pos],
            });
        }
    }

    fn readGlobalSection(self: *Module) !void {
        const section_size = try self.readInt(u32);
        _ = section_size;

        const global_count = try self.readInt(u32);
        for (0..global_count) |i| {
            const globaltype_pos = self.stream.pos;
            const valtype = try self.readEnum(types.ValueType);
            const mut = try self.readEnum(types.Mut);

            const expr_pos = self.stream.pos;

            var val: i32 = 0;
            var op = try self.readEnum(types.Opcode);
            switch (op) {
                .i32_const => val = try self.readInt(i32),
                else => return ModuleError.NotImplemented,
            }
            op = try self.readEnum(types.Opcode);
            if (op != .end) {
                return ModuleError.NotImplemented;
            }

            try self.globals.append(.{
                .idx = @intCast(i),
                .valtype = valtype,
                .val = val,
                .mut = mut,
                .globaltype = self.buf[globaltype_pos..expr_pos],
                .expr = self.buf[expr_pos..self.stream.pos],
            });
        }
    }

    fn readExportSection(self: *Module) !void {
        const section_size = try self.readInt(u32);
        _ = section_size;

        const export_count = try self.readInt(u32);
        for (0..export_count) |i| {
            const name = try self.readString();
            const exportdesc_ty = try self.readEnum(ExportDescTy);
            const exportdesc_idx = try self.readInt(u32);
            try self.exports.append(.{
                .idx = @intCast(i),
                .name = name,
                .exportdesc_ty = exportdesc_ty,
                .exportdesc_idx = exportdesc_idx,
            });
        }
    }

    fn readStartSection(self: *Module) !void {
        const section_size = try self.readInt(u32);
        _ = section_size;

        const funcidx = try self.readInt(u32);

        self.start = .{
            .funcidx = funcidx,
        };
    }

    fn readElementSection(self: *Module) !void {
        _ = self;
        return ModuleError.NotImplemented;
    }

    fn readCodeSection(self: *Module) !void {
        const section_size = try self.readInt(u32);
        _ = section_size;

        const code_count = try self.readInt(u32);
        for (0..code_count) |ci| {
            var code = Code{
                .idx = @intCast(ci),
                .expr = undefined,
                .locals_i32_count = 0,
                .locals_f32_count = 0,
            };

            const code_size = try self.readInt(u32);
            const code_pos = self.stream.pos;
            const locals_count = try self.readInt(u32);
            for (0..locals_count) |_| {
                const locals_n = try self.readInt(u32);
                const locals_t = try self.readEnum(types.ValueType);
                switch (locals_t) {
                    .vt_i32 => code.locals_i32_count += locals_n,
                    .vt_f32 => code.locals_f32_count += locals_n,
                }
            }

            const expr_pos = self.stream.pos;
            try self.reader.skipBytes(code_size + code_pos - expr_pos, .{});
            code.expr = self.buf[expr_pos..self.stream.pos];

            try self.code.append(code);
        }
    }

    fn readDataSection(self: *Module) !void {
        _ = self;
        return ModuleError.NotImplemented;
    }

    fn readDataCount(self: *Module) !void {
        _ = self;
        return ModuleError.NotImplemented;
    }
};

test "Parse add_and_sub" {
    const allocator = std.testing.allocator;

    const bin = @embedFile("test/add_and_sub.wasm");
    var module = Module.init(allocator);
    defer module.deinit();
    try module.load(bin);
}
