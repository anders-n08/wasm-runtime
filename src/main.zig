const std = @import("std");
const parser = @import("parser.zig");

const Value = parser.Value;

const usage =
    \\Usage: zig-obsidian-open <path-to-meta>
    \\
    \\-h, --help               Print help and exit
    \\
;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const all_args = try std.process.argsAlloc(allocator);
    const args = all_args[1..];

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var file_path: ?[]const u8 = null;
    var arg_index: usize = 0;

    while (arg_index < args.len) : (arg_index += 1) {
        if (std.mem.eql(u8, "-h", args[arg_index]) or std.mem.eql(u8, "--help", args[arg_index])) {
            return stdout.writeAll(usage);
        } else {
            file_path = args[arg_index];
        }
    }

    if (file_path == null) {
        return stdout.writeAll(usage);
    }

    const file = std.fs.cwd().openFile(file_path.?, .{}) catch {
        return stderr.writeAll("Unable to open meta file\n\n");
    };
    defer file.close();
    const source = file.readToEndAlloc(allocator, std.math.maxInt(u32)) catch {
        return stderr.writeAll("Unable to read meta file\n\n");
    };

    // fixme: Move away from parser...
    var context = parser.Context.init(allocator);
    var machine = parser.Machine.init(allocator, &context);

    try parser.parse(allocator, source[0..], &machine);

    // fixme: wtf should the api look like?

    std.log.info("run function test1", .{});

    var function = try machine.getFunction("test1");
    function.print();

    try machine.runFunction(function);

    var stack_entry = machine.pop();
    switch (stack_entry) {
        .set_i32 => |v| {
            std.log.info("Value was {?}", .{v});
        },
        else => {},
    }

    std.log.info("run function test2", .{});
    function = try machine.getFunction("test2");
    function.print();

    try machine.pushI32(-20); // p0
    try machine.runFunction(function);

    stack_entry = machine.pop();
    switch (stack_entry) {
        .set_i32 => |v| {
            std.log.info("Value was {?}", .{v});
        },
        else => {},
    }
}
