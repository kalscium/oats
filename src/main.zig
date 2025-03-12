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
}
