//! Functions for formatting stack items to be human readable

const std = @import("std");
const datetime = @import("datetime").datetime;
const item = @import("item.zig");

// 24 to 12 hour time conversion
inline fn convert24to12(num: anytype) @TypeOf(num) {
    if (num % 12 == 0) return 12
    else return num % 12;
}

/// Writes a image stack items to a stream in the 'markdown' format, given the last stack item
pub fn markdownImgs(writer: anytype, media_path: []const u8, images: []const item.Metadata) !void {
    // write the opening HTML tag
    try std.fmt.format(writer, "<details>\n    <summary><i>{} Included Image{s}</i></summary>\n", .{
        images.len,
        if (images.len > 1) "s" else "",
    });

    // iterate through the images metadata and write that paths (media files should exist atp)
    for (images) |image| {
        try std.fmt.format(writer, "    <code>{s}</code>\n    <img src=\"{s}/{s}\" alt=\"{s}\">\n", .{
            image.features.image_filename.?,
            media_path,
            image.features.image_filename.?,
            image.features.image_filename.?,
        });
    }

    // write the closing HTML tag
    try writer.writeAll("</details>\n");
}

/// Writes a markdown header if certain conditions are met based upon the
/// current & previous features and also if a new collection has been started
pub fn markdownHeader(writer: anytype, tz_offset: i16, features: item.Features, prev_features: item.Features, new_col: bool) !void {
    // time will be printed between oats of at least an n minute time difference
    const title_time_threshold = 8;

    // if there's no date then simply dip
    if (features.timestamp == null)
        return;

    // get the timezone, accounting for daylight savings (approx)
    var timezone = datetime.Timezone.create("CustomOffset", tz_offset);
    var date = datetime.Datetime.fromTimestamp(features.timestamp.?).shiftTimezone(&timezone);
    if (date.date.month >= 4) {
        timezone = datetime.Timezone.create("SCustomOffset", tz_offset-60);
        date = datetime.Datetime.fromTimestamp(features.timestamp.?).shiftTimezone(&timezone);
    }

    // get the day, month and year
    var prev_date: datetime.Datetime = undefined;
    if (prev_features.timestamp) |timestamp| {
        prev_date = datetime.Datetime.fromTimestamp(timestamp).shiftTimezone(&timezone);
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

        try writer.writeByte('\n');
        if (!new_col) try writer.writeByte('#');
        try std.fmt.format(writer, "## {s}, {}{s} of {s} {} `{:0>2}:{:0>2} {s}`", .{
            weekday,
            date.date.day,
            day_suffix,
            month,
            date.date.year,
            convert24to12(date.time.hour),
            date.time.minute,
            date.time.amOrPm(),
        });
        if (features.is_mobile) |_| try writer.writeAll(" *(on mobile)*");
        try writer.writeByte('\n');
    } else if (prev_features.timestamp == null or new_col or datetime.Datetime.fromTimestamp(features.timestamp.? - prev_features.timestamp.?).toSeconds()/60 > title_time_threshold) {
        try writer.writeByte('\n');
        if (!new_col) try writer.writeByte('#');
        try std.fmt.format(writer, "## `{:0>2}:{:0>2} {s}`", .{
            convert24to12(date.time.hour),
            date.time.minute,
            date.time.amOrPm(),
        });
        if (features.is_mobile) |_| try writer.writeAll(" *(on mobile)*");
        try writer.writeByte('\n');
    }
}

/// Writes a text stack item to a stream in the 'markdown' format
pub fn markdownText(writer: anytype, contents: []const u8) !void { // redundant but whatever
    try std.fmt.format(writer, "- {s}\n", .{contents});
}

/// Writes a stack item's features and contents to a stream in the 'normal' format
pub fn normal(allocator: std.mem.Allocator, file: std.fs.File, id: u64, features: item.Features, contents: []const u8) !void {
    // calculate the 'worst case scenario' length
    const wcs_size = comptime blk: {
        // calculate the largest id
        const largest_id = @as(comptime_int, @intFromFloat(@floor(@log10(@as(comptime_float, @floatFromInt(std.math.maxInt(u64))))))) + 1;

        // labels
        const id_label = "id: ".len;
        const date_label = ", date: ".len;
        const session_id_label = ", sess_id: ".len;
        const img_col_id_label = ", kind: image".len;
        const mobile_label = ", on: mobile".len;

        // features
        const date = 25; // iso-8601 date size
        const session_id = @as(comptime_int, @intFromFloat(@floor(@log10(@as(comptime_float, @floatFromInt(std.math.maxInt(i64))))))) + 2;
        
        break :blk largest_id + id_label + date_label + session_id_label + img_col_id_label + mobile_label + date + session_id;
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

    // write the session id if there is one
    if (features.session_id) |timestamp| {
        const session_id_str = try std.fmt.allocPrint(allocator, ", sess_id: {}", .{timestamp});
        defer allocator.free(session_id_str);
        try file.writeAll(session_id_str);
        current_size += session_id_str.len;
    }

    // write the image flag if it is one
    if (features.image_filename) |_| {
        const label = ", kind: image";
        try writer.writeAll(label);
        current_size += label.len;
    }

    // write the mobile label if there is one
    if (features.is_mobile) |_| {
        const label = ", on: mobile";
        try writer.writeAll(label);
        current_size += label.len;
    }

    // fill the gaps so the separator is in the same place
    try writer.writeByteNTimes(' ', wcs_size - current_size);

    // write the contents if it's text
    if (features.is_void) |_| {
        if (features.image_filename) |filename| {
            try file.writeAll(" # ");
            try std.fmt.format(writer, "{s}: <trimmed image data>\n", .{filename});
        } else {
            try file.writeAll(" | <trimmed oats item>\n");
        }
    } else if (features.image_filename) |filename| {
        try file.writeAll(" # ");
        try std.fmt.format(writer, "{s}: <binary image data>\n", .{filename});
    } else {
        try file.writeAll(" | ");
        try file.writeAll(contents);
        try file.writeAll("\n");
    }
}
