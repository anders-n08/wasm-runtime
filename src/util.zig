const std = @import("std");

pub fn printSlice(slice: []const u8) void {
    // fixme: One space to little on pad line when last line has less than 8 bytes.
    // fixme: One charactor too many when first line has less than 8 bytes.
    var as_text: [16]u8 = undefined;
    for (slice, 0..) |x, idx| {
        if (idx == 0) {
            std.debug.print("{x:0>4}: ", .{idx});
        }
        if (idx != 0 and idx % 8 == 0) {
            std.debug.print(" ", .{});
        }
        if (idx != 0 and idx % 16 == 0) {
            std.debug.print("{s}\n{x:0>4}: ", .{ as_text[0..], idx });
        }
        std.debug.print("{x:0>2} ", .{x});
        if (x < 32 or x >= 127) {
            as_text[idx & 15] = '.';
        } else {
            as_text[idx & 15] = x;
        }
        if ((idx + 1) == slice.len) {
            const pad = " " ** 48;
            std.debug.print(" {s}{s}\n", .{
                pad[0 .. (16 - (slice.len & 15)) * 3],
                as_text[0 .. (slice.len & 15) + 1],
            });
        }
    }
}
