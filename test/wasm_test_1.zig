pub export fn test1() u32 {
    return 42;
}

pub export fn test2(base: u32) u32 {
    return 42 + base;
}

extern fn add(v0: u32, v1: u32) u32;

export const my_global2: u32 = 0x1234;
export var framebuffer = [_]u8{0} ** 4096;
export var framebuffer2 = [_]u8{0} ** 3000;
export var my_array = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 0 };
export var my_global: u32 = 0x1234;

pub export fn test3(base: u32) u32 {
    framebuffer[20] = @truncate(base);
    return add(base, 20);
}

pub export fn ptr() [*]u8 {
    return @ptrCast(&framebuffer);
}

pub export fn sfb(idx: i32, v: u8) void {
    framebuffer[@as(usize, @intCast(idx))] = v;
}

pub export fn gfb(idx: i32) u8 {
    return framebuffer[@as(usize, @intCast(idx))];
}

// pub export fn add(v0: u32, v1: u32) u32 {
//     return v0 + v1;
//
