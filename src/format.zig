//! Functions for formatting stack items to be human readable

const std = @import("std");
const datetime = @import("datetime").datetime;
const item = @import("item.zig");

/// Writes a stack item's features to a stream in the 'normal' format
pub fn normalFeatures(allocator: std.mem.Allocator, file: std.fs.File, id: u64, features: item.Features) !void {
    // calculate the 'worst case scenario' length
    const wcs_size = comptime blk: {
        // calculate the largest id
        const largest_id = std.fmt.comptimePrint("{}", .{std.math.maxInt(u64)}).len;

        // additional variables
        const date = 25; // iso-8601 date size
        const padding = 12; // padding and also the labels
        
        break :blk largest_id + date + padding;
    };

    var writer = file.writer();

    // current size to make things easier
    var current_size: usize = 0;

    // calculate the size of the current id
    const id_str = try std.fmt.allocPrint(allocator, "{}", .{id});
    defer allocator.free(id_str);
    current_size += id_str.len;

    // write the id
    try file.writeAll("id: ");
    try file.writeAll(id_str);
    current_size += 4;

    // write the date if there is one
    if (features.timestamp) |timestamp| {
        const date = datetime.Datetime.fromTimestamp(timestamp);
        const date_str = try date.formatISO8601(allocator, false);
        defer allocator.free(date_str);
        try file.writeAll(", date: ");
        try file.writeAll(date_str);
        current_size += 25 + 8;
    }

    // fill the gaps so the separator is in the same place
    try writer.writeByteNTimes(' ', wcs_size - current_size);
    try file.writeAll(" | ");
}
