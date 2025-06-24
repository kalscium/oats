pub const stack = @import("stack.zig");
pub const item = @import("item.zig");
pub const format = @import("format.zig");
pub const datetime = @import("datetime");

const std = @import("std");

/// The current semantic version
pub const version = "0.12.5";

/// The current major version of this cli (semantic versioning)
pub const maj_ver = blk: {
    // what the comptime 💀
    var split = std.mem.splitScalar(u8, version, '.');
    break :blk std.fmt.parseInt(u8, split.first(), 10) catch @compileError("invalid version");
};

/// The magic sequence for oats
pub const magic_seq = "oats";

/// Returns the path of the oats stack/database, owned by the caller
pub fn getHome(allocator: std.mem.Allocator) ![]const u8 {
    // get env map
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    // if there is an oats home override then just return that
    if (env_map.get("OATS_DB_PATH")) |path| {
        const path_clone = try allocator.alloc(u8, path.len);
        @memcpy(path_clone, path);
        return path_clone;
    }

    // get the user-home
    const user_home = env_map.get("HOME") orelse env_map.get("APPDATA") orelse return error.HomeEnvVarUnset;

    // construct and allocate the napkin home
    const home = try std.fmt.allocPrint(allocator, "{s}/.oats", .{user_home});
    return home;
}

/// Returns the path of the temporary oats stack/database, owned by the caller
pub fn getTmpHome(allocator: std.mem.Allocator) ![]const u8 {
    // get env map
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    // get the oats home
    const home = try getHome(allocator);
    defer allocator.free(home);

    // construct and allocate the tmp home
    const tmp_home = try std.fmt.allocPrint(allocator, "{s}.tmp.oats", .{home});
    return tmp_home;
}
