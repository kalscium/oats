const std = @import("std");
const oats = @import("oats");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var file = try std.fs.cwd().createFile("test.bin", .{ .read = true });
    defer file.close();

    var stack_ptr: u64 = 0;
    try oats.stack.push(&file, &stack_ptr, "hello, world");
    try oats.stack.push(&file, &stack_ptr, "help");

    var read_ptr: u64 = 0;
    while (read_ptr != stack_ptr) {
        const value = try oats.stack.readStackEntry(allocator, &file, &read_ptr);
        defer allocator.free(value);
        std.debug.print("{s}\n", .{value});
    }

    // pack and unpack
    const features = oats.item.Features{ .id = null, .date = 56 };
    const packed_contents = try oats.item.pack(allocator, features, "hello, world");
    defer allocator.free(packed_contents);
    const unpacked = oats.item.unpack(packed_contents);
    std.debug.print("features: {any}\n", .{unpacked.features});
    std.debug.print("contents: {s}\n", .{unpacked.contents});
}
