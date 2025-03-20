//! A singular item stored on the stack in the thoughts/notes database

const std = @import("std");

/// A bitfield that determines the features enabled in each item (for easy
/// backwards compatibility)
pub const FeaturesBitfield = packed struct(u8) {
    /// (does nothing now) in case in the future I need more features
    extended: bool = false,
    has_timestamp: bool,

    _padding: u6 = 0,
};

/// The actual data of the features defined by the features bitfield
pub const Features = struct {
    /// The UNIX timestamp creation date of the stack item
    timestamp: ?i64,
};

/// Calculates the size based upon the features enabled
pub fn featuresSize(features: Features) usize {
    var size: usize = @sizeOf(FeaturesBitfield);
    if (features.timestamp != null) size += @sizeOf(@TypeOf(features.timestamp.?));

    return size;
}

/// Packs together contents with the feature bitfield and returns it, owned by the caller
pub fn pack(allocator: std.mem.Allocator, id: u64, features: Features, contents: []const u8) ![]const u8 {
    const total_size = @sizeOf(@TypeOf(id)) + featuresSize(features) + contents.len;
    const buffer = try allocator.alloc(u8, total_size);

    // offset to make things easier (no collisions)
    var offset: usize = 0;

    // write the id
    @memcpy(buffer[0..@sizeOf(u64)], std.mem.asBytes(&std.mem.nativeToBig(u64, id)));
    offset += @sizeOf(u64);

    // write the bitfield
    const bitfield = FeaturesBitfield{
        .has_timestamp = features.timestamp != null,
    };
    buffer[offset] = std.mem.nativeToBig(u8, @bitCast(bitfield));
    offset += @sizeOf(FeaturesBitfield);

    // write the date
    if (features.timestamp) |date| {
        @memcpy(buffer[offset..offset+@sizeOf(@TypeOf(date))], std.mem.asBytes(&std.mem.nativeToBig(@TypeOf(date), date)));
        offset += @sizeOf(@TypeOf(date));
    }

    // write the rest of the contents
    @memcpy(buffer[offset..], contents);

    return buffer;
}

/// Unpacks the stack item
/// note: the returned contents reference the item data
pub fn unpack(item: []const u8) struct{ id: u64, features: Features, contents: []const u8 } {
    // offset to make things easier
    var offset: usize = 0;

    // result
    var features = Features{ .timestamp = null };

    // decode the id
    const id = std.mem.bigToNative(u64, std.mem.bytesToValue(u64, item[0..@sizeOf(u64)]));
    offset = @sizeOf(u64);
    
    // decode the features bitfield
    const features_bitfield: FeaturesBitfield = @bitCast(std.mem.bigToNative(u8, item[offset]));
    offset += @sizeOf(u8);

    // decode the date
    if (features_bitfield.has_timestamp) {
        features.timestamp = std.mem.bigToNative(@TypeOf(features.timestamp.?), std.mem.bytesToValue(@TypeOf(features.timestamp.?), item[offset..offset+@sizeOf(@TypeOf(features.timestamp.?))]));
        offset += @sizeOf(@TypeOf(features.timestamp.?));
    }

    return .{
        .id = id,
        .features = features,
        .contents = item[offset..]
    };
}
