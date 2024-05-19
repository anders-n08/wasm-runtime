pub const Opcode = enum(u8) {
    end = 0x0b,
    call = 0x10,
    local_get = 0x20,
    i32_const = 0x41,
    i32_add = 0x6a,
};
