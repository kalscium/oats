//! Functions for formatting stack items to be human readable

const std = @import("std");
const datetime = @import("datetime").datetime;
const item = @import("item.zig");

// 24 to 12 hour time conversion
inline fn convert24to12(num: anytype) @TypeOf(num) {
    if (num % 12 == 0) return 12
    else return num % 12;
}

/// Writes a stack item to a stream in the 'markdown' format, given the last stack item
pub fn markdown(writer: anytype, tz_offset: i16, features: item.Features, contents: []const u8, prev_features: item.Features) !void {
    // time will be printed between oats of at least a n minute time difference
    const title_time_threshold = 8;

    // if there's no date then simply write the contents and dip
    if (features.timestamp == null)
        return std.fmt.format(writer, "- {s}\n", .{contents});

    // get the day, month and year
    const date = datetime.Datetime.fromTimestamp(features.timestamp.?).shiftTimezone(&datetime.Timezone.create("CustomOffset", tz_offset));
    var prev_date: datetime.Datetime = undefined;
    if (prev_features.timestamp) |timestamp| {
        prev_date = datetime.Datetime.fromTimestamp(timestamp).shiftTimezone(&datetime.Timezone.create("CustomOffset", tz_offset));
    }

    // if it's not the same day, or the previous item had no date, then write the date
    if (prev_features.timestamp == null or prev_date.date.day != date.date.day or prev_date.date.month != date.date.month or prev_date.date.year != date.date.year) {
        // format the date
        const weekday = date.date.weekdayName();
        const month = date.date.monthName();
        const day_suffix =
            if (date.date.day % 10 == 1 and date.date.day != 11) "st"
            else if (date.date.day % 10 == 2 and date.date.day != 12) "nd"
            else if (date.date.day % 10 == 3 and date.date.day != 13) "rd"
            else "th";
        try std.fmt.format(writer, "## {s}, {}{s} of {s} {} `{:0>2}:{:0>2} {s}`\n", .{
            weekday,
            date.date.day,
            day_suffix,
            month,
            date.date.year,
            convert24to12(date.time.hour),
            date.time.minute,
            date.time.amOrPm(),
        });
    } else if (prev_features.timestamp == null or datetime.Datetime.fromTimestamp(features.timestamp.? - prev_features.timestamp.?).toSeconds()/60 > title_time_threshold) {
        try std.fmt.format(writer, "#### `{:0>2}:{:0>2} {s}`\n", .{
            convert24to12(date.time.hour),
            date.time.minute,
            date.time.amOrPm(),
        });
    }

    // write the actual contents
    try std.fmt.format(writer, "- {s}\n", .{contents});
}

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
