pub export fn test1() u32 {
    return 42;
}

pub export fn test2(base: u32) u32 {
    return 42 + base;
}

extern fn add(v0: u32, v1: u32) u32;

pub export fn test3(base: u32) u32 {
    return add(base, 20);
}

// pub export fn add(v0: u32, v1: u32) u32 {
//     return v0 + v1;
// }
