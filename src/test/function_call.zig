extern fn add(a: i32, b: i32) i32;

export fn add_with_offset(a: i32, b: i32, offset: i32) i32 {
    return add(a, b) + offset;
}
