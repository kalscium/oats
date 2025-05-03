//! A singular item stored on the stack in the thoughts/notes database

const std = @import("std");

/// A bitfield that determines the features enabled in each item (for easy
/// backwards compatibility)
pub const FeaturesBitfield = packed struct(u8) {
    /// (does nothing now) in case in the future I need more features
    extended: bool = false,
    has_timestamp: bool,
    has_session_id: bool,

    _padding: u5 = 0,
};

/// General metadata of a stack item (for reading) so you don't have to keep
/// the entirety of the item's contents in memory
pub const Metadata = struct {
    /// The unique identifier for the stack item
    id: u64,
    /// The features & feature data of the stack item
    features: Features,
    /// The start index of the item's data in the database file
    start_idx: usize,
    /// The offset of the contents from the start index
    /// (accounts for features, features should not be larger than 256 bytes)
    contents_offset: u8,
    /// The size of the stack entry
    size: u32,

    /// Finds if the id of this is less or larger than another item
    pub fn idLessThan(context: void, a: Metadata, b: Metadata) bool {
        _ = context;
        return a.id < b.id;
    }
};

/// The actual data of the features defined by the features bitfield
pub const Features = struct {
    /// The UNIX timestamp creation date of the stack item
    timestamp: ?i64,
    /// The UNIX timestamp/id of an oats session
    session_id: ?i64,
};

/// Calculates the size based upon the features enabled
pub fn featuresSize(features: Features) usize {
    var size: usize = @sizeOf(FeaturesBitfield);
    if (features.timestamp != null) size += @sizeOf(@TypeOf(features.timestamp.?));
    if (features.session_id != null) size += @sizeOf(@TypeOf(features.session_id.?));

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
        .has_session_id = features.session_id != null,
    };
    buffer[offset] = std.mem.nativeToBig(u8, @bitCast(bitfield));
    offset += @sizeOf(FeaturesBitfield);

    // write the date
    if (features.timestamp) |date| {
        @memcpy(buffer[offset..offset+@sizeOf(@TypeOf(date))], std.mem.asBytes(&std.mem.nativeToBig(@TypeOf(date), date)));
        offset += @sizeOf(@TypeOf(date));
    }

    // write the session id
    if (features.session_id) |timestamp| {
        @memcpy(buffer[offset..offset+@sizeOf(@TypeOf(timestamp))], std.mem.asBytes(&std.mem.nativeToBig(@TypeOf(timestamp), timestamp)));
        offset += @sizeOf(@TypeOf(timestamp));
    }

    // write the rest of the contents
    @memcpy(buffer[offset..], contents);

    return buffer;
}

/// Unpacks the stack item from it's encoded form and also it's location (offset) in the database file
pub fn unpack(start_idx: usize, item: []const u8) Metadata {
    // offset to make things easier
    var offset: usize = 0;

    // result
    var features = Features{ .timestamp = null, .session_id = null };

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

    // decode the session id
    if (features_bitfield.has_session_id) {
        features.session_id = std.mem.bigToNative(@TypeOf(features.session_id.?), std.mem.bytesToValue(@TypeOf(features.session_id.?), item[offset..offset+@sizeOf(@TypeOf(features.session_id.?))]));
        offset += @sizeOf(@TypeOf(features.session_id.?));
    }

    return .{
        .id = id,
        .features = features,
        .start_idx = start_idx,
        .contents_offset = @intCast(offset),
        .size = @intCast(item.len),
    };
}
