pub const Opcode = enum(u8) {
    end = 0x0b,
    call = 0x10,
    local_get = 0x20,
    i32_load = 0x28,
    i32_load8_s = 0x2c,
    i32_load8_u = 0x2d,
    i32_load16_s = 0x2e,
    i32_load16_u = 0x2f,
    i32_store = 0x36,
    i32_store8 = 0x3a,
    i32_store16 = 0x3b,
    i32_const = 0x41,
    i32_add = 0x6a,
    i32_sub = 0x6b,
};

pub const Mut = enum(u8) {
    mut_const = 0,
    mut_var = 1,
};

pub const ValueType = enum(u8) {
    vt_i32 = 0x7f,
    vt_f32 = 0x7d,
    // vt_i64 = 0x7e,
    // vt_f64 = 0x7c,
    // fixme: vt_v128 = 0x7b,
    // fixme: vt_funcref = 0x70,
    // fixme: vt_externref = 0x6f,
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

pub const ExportDesc = enum(u8) {
    func = 0x00,
    table = 0x01,
    mem = 0x02,
    global = 0x03,
};

pub const Data = enum(u8) {
    active_mem_0 = 0x00,
    passive = 0x01,
    active_mem_x = 0x02,
};
