const std = @import("std");

const StoreError = error{
    NotImplemented,
    InvalidModule,
    InvalidType,
    NoData,
};

const Module = @import("module.zig").Module;
const Code = @import("module.zig").Code;

const types = @import("types.zig");

pub const BufferReader = struct {
    idx: u32,
    mem: []const u8,

    pub fn init(mem: []const u8) BufferReader {
        return .{
            .idx = 0,
            .mem = mem,
        };
    }

    pub fn resetReader(self: *BufferReader) void {
        self.idx = 0;
    }

    pub fn readByte(self: *BufferReader) anyerror!u8 {
        if (self.idx >= self.mem.len) {
            return StoreError.NoData;
        }
        const b = self.mem[self.idx];
        self.idx += 1;
        return b;
    }

    pub fn readInt(self: *BufferReader, comptime T: type) !T {
        switch (T) {
            u8 => return try self.readByte(),
            u32 => return try std.leb.readULEB128(T, self),
            i32 => return try std.leb.readILEB128(T, self),
            else => return StoreError.InvalidType,
        }
    }

    pub fn readEnum(self: *BufferReader, comptime T: type) !T {
        const b = try self.readByte();
        return try std.meta.intToEnum(T, b);
    }
};

pub const FuncInst = struct {
    name: []const u8,
    code: *const Code,
    expr: BufferReader,
};

// fixme: Necessary to import here?
const Machine = @import("machine.zig").Machine;
const Import = struct {
    name: []const u8,
    cb: ?*const fn (m: *Machine) anyerror!void = null,
};

const GlobalInst = struct {};

pub const Store = struct {
    allocator: std.mem.Allocator,
    module: *Module,
    functions: std.ArrayList(FuncInst),
    globals: std.ArrayList(GlobalInst),
    imports: std.ArrayList(Import),

    memory: std.ArrayList(u8),

    rm: []const u8 = undefined,
    rm_idx: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, module: *Module) !Store {
        var store = Store{
            .allocator = allocator,
            .module = module,
            .functions = std.ArrayList(FuncInst).init(allocator),
            .globals = std.ArrayList(GlobalInst).init(allocator),
            .memory = std.ArrayList(u8).init(allocator),
            .imports = std.ArrayList(Import).init(allocator),
        };

        const mem_size = try store.readMemoryLimitMin();
        try store.memory.ensureTotalCapacity(mem_size);
        std.debug.print("set memory size to 0x{x}\n", .{mem_size});

        for (module.imports.items) |imp| {
            try store.imports.append(.{
                .name = imp.name,
            });
        }

        // Functions are referenced through function indices, starting with the
        // smallest index not referencing a function import.
        const funcidx_base = module.imports.items.len;

        for (module.functions.items) |f| {
            var func_inst = FuncInst{
                .name = undefined,
                .code = undefined,
                .expr = undefined,
            };

            for (module.exports.items) |exp| {
                if (exp.exportdesc_ty == .func and exp.exportdesc_idx == (f.idx + funcidx_base)) {
                    func_inst.name = exp.name;
                }
            }

            const code = module.code.items[f.idx];
            func_inst.code = &code;
            func_inst.expr = BufferReader.init(code.expr);

            try store.functions.append(func_inst);
        }

        return store;
    }

    pub fn deinit(self: *Store) void {
        self.functions.clearAndFree();
        self.globals.clearAndFree();
        self.memory.clearAndFree();
        self.imports.clearAndFree();
    }

    pub fn readByte(self: *Store) anyerror!u8 {
        const b = self.rm[self.rm_idx];
        self.rm_idx += 1;
        return b;
    }

    fn readIntAt(self: *Store, comptime T: type, buf: []const u8) !T {
        _ = self; // autofix
        switch (T) {
            u8 => return std.mem.readInt(T, buf[0..@sizeOf(T)], .little),
            else => return StoreError.InvalidType,
        }
    }

    fn readInt(self: *Store, comptime T: type, reader: *BufferReader) !T {
        _ = self;
        switch (T) {
            u8 => return try reader.readByte(),
            u32 => return try std.leb.readULEB128(T, reader),
            i32 => return try std.leb.readILEB128(T, reader),
            else => return StoreError.InvalidType,
        }
    }

    fn readMemoryLimitMin(self: *Store) !u32 {
        if (self.module.memory.items.len != 1) {
            return StoreError.InvalidModule;
        }

        const mem = self.module.memory.items[0];
        var memtype_reader = BufferReader.init(mem.memtype);
        _ = try memtype_reader.readInt(u8);
        const mem_size = try memtype_reader.readInt(u32);

        return mem_size * 0x10000;
    }

    pub fn addCallback(self: *Store, name: []const u8, cb: *const fn (m: *Machine) anyerror!void) !void {
        for (self.imports.items) |*imp| {
            if (std.mem.eql(u8, name, imp.name)) {
                imp.cb = cb;
                break;
            }
        } else return StoreError.NotImplemented;
    }
};

test "Initialize add_and_sub" {
    const allocator = std.testing.allocator;

    const bin = @embedFile("test/add_and_sub.wasm");
    var m = Module.init(allocator);
    defer m.deinit();
    try m.load(bin);

    var store = try Store.init(allocator, &m);
    defer store.deinit();
}
