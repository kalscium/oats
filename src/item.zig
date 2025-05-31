//! A singular item stored on the stack in the thoughts/notes database

const std = @import("std");

/// A bitfield that determines the features enabled in each item (for easy
/// backwards compatibility)
pub const FeaturesBitfield = packed struct(u8) {
    /// (does nothing now) in case in the future I need more features
    extended: bool = false,
    has_timestamp: bool,
    has_session_id: bool,
    is_image: bool,
    is_mobile: bool,
    is_void: bool,
    is_file: bool,

    _padding: u1 = 0,
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
    timestamp: ?i64 = null,
    /// The UNIX timestamp/id of an oats session
    session_id: ?i64 = null,
    /// The image filename
    image_filename: ?[]const u8 = null,
    /// If it was written on mobile or not
    is_mobile: ?void = null,
    /// If the item is trimmed (shallow copy) (no contents)
    is_void: ?void = null,
    /// The filename of a stored file
    /// 
    /// note: independant and mutually exclusive of `image_filename`
    ///       for backwards compatibility reasons
    filename: ?[]const u8 = null,
};

/// Calculates the size based upon the features enabled
pub fn featuresSize(features: Features) usize {
    var size: usize = @sizeOf(FeaturesBitfield);

    // generic comptime for getting the struct size of features
    inline for (comptime @typeInfo(Features).Struct.fields) |field| {
        // only add to it, if it's enabled
        if (@field(features, field.name)) |feature|
            size += @sizeOf(@TypeOf(feature));
    }

    // special case for filenames as they have a dynamic sizes
    if (features.image_filename) |filename| {
        // remove the size of the slice
        size -= @sizeOf(@TypeOf(filename));
        // push the size of the filename and size of the length
        size += @sizeOf(u16) + filename.len;
    } if (features.filename) |filename| {
        // remove the size of the slice
        size -= @sizeOf(@TypeOf(filename));
        // push the size of the filename and size of the length
        size += @sizeOf(u16) + filename.len;
    }

    return size;
}

/// Generates a features bitfield based on the features enabled
pub fn featuresToBitfield(features: Features) FeaturesBitfield {
    return FeaturesBitfield{
        .has_timestamp = features.timestamp != null,
        .has_session_id = features.session_id != null,
        .is_image = features.image_filename != null,
        .is_mobile = features.is_mobile != null,
        .is_void = features.is_void != null,
        .is_file = features.filename != null,
    };
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
    const bitfield = featuresToBitfield(features);
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

    // write the image filename
    if (features.image_filename) |filename| {
        // write the length of the filename
        @memcpy(buffer[offset..offset+@sizeOf(u16)], std.mem.asBytes(&std.mem.nativeToBig(u16, @intCast(filename.len))));
        offset += @sizeOf(u16);

        // write the contents
        @memcpy(buffer[offset..offset+filename.len], filename);
        offset += filename.len;
    }

    // write the filename
    if (features.filename) |filename| {
        // write the length of the filename
        @memcpy(buffer[offset..offset+@sizeOf(u16)], std.mem.asBytes(&std.mem.nativeToBig(u16, @intCast(filename.len))));
        offset += @sizeOf(u16);

        // write the contents
        @memcpy(buffer[offset..offset+filename.len], filename);
        offset += filename.len;
    }

    // write the rest of the contents
    @memcpy(buffer[offset..], contents);

    return buffer;
}

/// Unpacks the stack item from it's encoded form and also it's location (offset) in the database file
pub fn unpack(allocator: std.mem.Allocator, start_idx: usize, item: []const u8) !Metadata {
    // offset to make things easier
    var offset: usize = 0;

    // result
    var features = Features{};

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

    // decode the image metadata
    if (features_bitfield.is_image) {
        // decode the filename length
        const fn_len = std.mem.bigToNative(u16, std.mem.bytesToValue(u16, item[offset..offset+@sizeOf(u16)]));
        offset += @sizeOf(u16);

        // decode the filename
        // allocate the filename
        const filename = try allocator.alloc(u8, fn_len);
        @memcpy(filename, item[offset..offset+fn_len]);
        offset += fn_len;
        features.image_filename = filename;
    }

    // decode the file metadata
    if (features_bitfield.is_file) {
        // decode the filename length
        const fn_len = std.mem.bigToNative(u16, std.mem.bytesToValue(u16, item[offset..offset+@sizeOf(u16)]));
        offset += @sizeOf(u16);

        // decode the filename
        // allocate the filename
        const filename = try allocator.alloc(u8, fn_len);
        @memcpy(filename, item[offset..offset+fn_len]);
        offset += fn_len;
        features.filename = filename;
    }

    // mobile flag
    features.is_mobile = if (features_bitfield.is_mobile) {} else null;

    // is_void flag
    features.is_void = if (features_bitfield.is_void) {} else null;

    return .{
        .id = id,
        .features = features,
        .start_idx = start_idx,
        .contents_offset = @intCast(offset),
        .size = @intCast(item.len),
    };
}
