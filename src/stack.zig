const std = @import("std");

/// The location of the major version within the database file
pub const maj_ver_loc = 0;
/// The location of the stack ptr within the database file
pub const stack_ptr_loc = @sizeOf(u8);
/// The location of the start of the stack within the database file
pub const stack_start_loc = @sizeOf(u8) + @sizeOf(u64);

/// Pushes a value onto a 'stack' by writing to a file
pub fn push(writer: *std.fs.File, stack_ptr: *u64, bytes: []const u8) !void {
    try writer.seekTo(stack_ptr.*);
    try writeInt(u32, @intCast(bytes.len), writer); // write the first padding length
    try writer.writeAll(bytes); // write the actual contents
    try writeInt(u32, @intCast(bytes.len), writer); // write the last padding length

    // update the stack ptr
    stack_ptr.* += bytes.len + comptime @sizeOf(u32) * 2;
}

/// Reads a big-endian number of a specified type from a file and returns it
pub fn readInt(comptime T: anytype, file: *std.fs.File) !T {
    // make sure it's a number
    if (@typeInfo(T) != std.builtin.TypeId.Int)
        @compileError("readInt must only read integers");

    // allocate the buffer and read
    var buffer: [@typeInfo(T).Int.bits/8]u8 = undefined;
    _ = try file.readAll(&buffer);

    // parse and convert endian-ness
    const big_end: T = @bitCast(buffer);
    const native_end = std.mem.bigToNative(T, big_end);

    return native_end;
}

/// Writes a big-endian number of a specified type to a file
pub fn writeInt(comptime T: anytype, val: T, file: *std.fs.File) !void {
    // make sure it's a number
    if (@typeInfo(T) != std.builtin.TypeId.Int)
        @compileError("writeInt must only write intergers");

    // convert to big endian and create the 'buffer'
    const big_end = std.mem.nativeToBig(T, val);
    const buffer: [@typeInfo(T).Int.bits/8]u8 = @bitCast(big_end);

    // write it to the file
    try file.writeAll(&buffer);
}

/// Pops a value off the 'stack' by reading it from a stremm and returns it,
/// owned by the caller
/// 
/// It does this by reading the length that's always situated at the end of the
/// stack entry to determine the lenght.
pub fn pop(allocator: std.mem.Allocator, reader: *std.fs.File, stack_ptr: *u64) ![]const u8 {
    // seek to the size of a u32 before the stack_ptr so you can read the
    // correct value
    stack_ptr.* -= @sizeOf(u32);
    try reader.seekTo(stack_ptr.*);
    const length = try readInt(u32, reader.reader());

    // seek to the start of the stack entry's contents, read it to a buffer
    stack_ptr.* -= length;
    const buffer: []u8 = try allocator.alloc(u8, length);
    try reader.seekTo(stack_ptr.*);
    _ = try reader.reader().readAll(buffer);

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
pub fn readStackEntry(allocator: std.mem.Allocator, reader: *std.fs.File, read_ptr: *u64) ![]const u8 {
    try reader.seekTo(read_ptr.*);

    // read the length of the stack entry and progress the read_ptr
    const length = try readInt(u32, reader);
    read_ptr.* += @sizeOf(u32);

    // read and allocate the actual contents of the stack entry
    const buffer: []u8 = try allocator.alloc(u8, length);
    _ = try reader.readAll(buffer);

    // update the read ptr and return
    read_ptr.* += length + @sizeOf(u32);
    return buffer;
}
