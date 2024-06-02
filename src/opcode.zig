pub const Opcode = enum(u8) {
    end = 0x0b,
    call = 0x10,
    local_get = 0x20,
    i32_store = 0x36,
    i32_store8 = 0x3a,
    i32_store16 = 0x3b,
    i32_const = 0x41,
    i32_add = 0x6a,
};
