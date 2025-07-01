const std = @import("std");
const oats = @import("root.zig");

/// The location of the major version within the database file
pub const maj_ver_loc = oats.magic_seq.len;
/// The location of the stack ptr within the database file
pub const stack_ptr_loc = maj_ver_loc + @sizeOf(u8);
/// The location of the start of the stack within the database file
pub const stack_start_loc = stack_ptr_loc + @sizeOf(u64);

/// Pushes a value onto a 'stack' by writing to a file
pub fn push(file: std.fs.File, stack_ptr: *u64, bytes: []const u8) !void {
    var writer = file.writer();

    try file.seekTo(stack_ptr.*);
    try writer.writeInt(u32, @intCast(bytes.len), .big); // write the first padding length
    try writer.writeAll(bytes); // write the actual contents
    try writer.writeInt(u32, @intCast(bytes.len), .big); // write the last padding length

    // update the stack ptr
    stack_ptr.* += bytes.len + comptime @sizeOf(u32) * 2;
}

/// Pops a value off the 'stack' by reading it from a stremm and returns it,
/// owned by the caller
/// 
/// It does this by reading the length that's always situated at the end of the
/// stack entry to determine the lenght.
pub fn pop(allocator: std.mem.Allocator, file: std.fs.File, stack_ptr: *u64) ![]const u8 {
    var reader = file.reader();

    // seek to the size of a u32 before the stack_ptr so you can read the
    // correct value
    stack_ptr.* -= @sizeOf(u32);
    try file.seekTo(stack_ptr.*);
    const length = try reader.readInt(u32, .big);

    // seek to the start of the stack entry's contents, read it to a buffer
    stack_ptr.* -= length;
    const buffer: []u8 = try allocator.alloc(u8, length);
    errdefer allocator.free(buffer);
    try file.seekTo(stack_ptr.*);
    _ = try reader.readAll(buffer);

    // update the stack_ptr to before the first padding length
    stack_ptr.* -= @sizeOf(u32);

    // return the contents
    return buffer;
}

/// Reads another stack entry from the stack based upon the 'read_ptr', and
/// returns it, (owned by the caller).
///
/// The read_ptr is similar to the stack ptr and must always be aligned to the
/// start of each stack entry (including the length padding).
///
/// Ensure that THERE IS another stack entry as this function will NOT check.
pub fn readStackEntry(allocator: std.mem.Allocator, file: std.fs.File, read_ptr: *u64) ![]const u8 {
    var reader = file.reader();
    try file.seekTo(read_ptr.*);

    // read the length of the stack entry and progress the read_ptr
    const length = try reader.readInt(u32, .big);
    read_ptr.* += @sizeOf(u32);

    // read and allocate the actual contents of the stack entry
    const buffer: []u8 = try allocator.alloc(u8, length);
    errdefer allocator.free(buffer);
    _ = try reader.readAll(buffer);

    // update the read ptr and return
    read_ptr.* += length + @sizeOf(u32);
    return buffer;
}
