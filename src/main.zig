pub const session = @import("session.zig");

const std = @import("std");
const oats = @import("oats");
const options = @import("options");

test binarySearch {
    // test binary searching something that exists
    const slice: []const u8 = &.{ 2, 4, 8, 16, 32 };

    var item: u8 = 4;
    var found, var loc = binarySearch(u8, item, slice, struct{ fn f(x: u8) u8 { return x; } }.f);
    std.debug.assert(found);
    std.debug.assert(loc == 1);

    // test binary searching something that doesn't exist
    item = 13;
    found, loc = binarySearch(u8, item, slice, struct{ fn f(x: u8) u8 { return x; } }.f);
    std.debug.assert(!found);
    std.debug.assert(loc == 3);
}

/// Finds the location of an item in a sorted slice, otherwise where it should be
pub fn binarySearch(comptime num_type: type, item: anytype, slice: []const @TypeOf(item), comptime f: fn(@TypeOf(item)) num_type) struct{bool, usize} {
    var low: usize = 0;
    var high: usize = slice.len - 1;

    while (low <= high) {
        const mid = low + (high - low) / 2;

        // check if x is present at mid
        if (f(slice[mid]) == f(item))
            return .{true, mid};

        // if x greater, ignore left half
        if (f(slice[mid]) < f(item))
            low = mid + 1
        // if x lesser, ignore right half
        else
            high = mid - 1;
    }

    // if this is reached, then item is not present
    return .{false, low}; // giant assumption that this will be the correct spot to insert to
}

pub fn basicLessThan(comptime T: type) fn (context: void, a: T, b: T)bool {
    return struct{
        pub fn call(context: void, a: T, b: T) bool {
            _ = context;
            return a < b;
        }
    }.call;
}

/// Opens and checks an oats database
pub fn openOatsDB(path: []const u8) !std.fs.File {
    // open the read database file
    var file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });

    // double check the magic sequence
    var magic: [oats.magic_seq.len]u8 = undefined;
    _ = try file.readAll(&magic);
    if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

    // make sure it's of the right major version
    const maj_ver = try file.reader().readInt(u8, .big);
    if (maj_ver != oats.maj_ver) return error.MajVersionMismatch;

    return file;
}

pub fn pop(allocator: std.mem.Allocator, to_pop: usize) !void {
    // if database file doesn't exist throw error
    const path = try oats.getHome(allocator);
    if (std.fs.cwd().access(path, .{})) {}
    else |err| {
        std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
        return err;
    }

    const file = try openOatsDB(path);
    defer file.close();

    // get the stack ptr
    var stack_ptr = try file.reader().readInt(u64, .big);

    // print it
    std.debug.print("<<< POPPED OATS (LATEST FIRST) >>>\n", .{});
    for (0..to_pop) |_| {
        // double check there are items to pop
        if (stack_ptr == oats.stack.stack_start_loc)
            return error.EmptyStack;

        // pop the last item and decode it
        const raw_item = try oats.stack.pop(allocator, file, &stack_ptr);
        defer allocator.free(raw_item);
        const item = try oats.item.unpack(allocator, stack_ptr + @sizeOf(u32), raw_item);

        // read it's contents
        const contents = try allocator.alloc(u8, item.size - item.contents_offset);
        defer allocator.free(contents);
        try file.seekTo(item.start_idx + item.contents_offset);
        _ = try file.readAll(contents);

        try oats.format.normal(allocator, std.io.getStdErr(), item.id, item.features, contents);
    }

    // update the stack ptr
    try file.seekTo(oats.stack.stack_ptr_loc);
    try file.writer().writeInt(u64, stack_ptr, .big);
}

pub fn pushImg(allocator: std.mem.Allocator, session_id: ?i64, img_paths: []const []const u8) !void {
    // if database file doesn't exist throw error
    const path = try oats.getHome(allocator);
    if (std.fs.cwd().access(path, .{})) {}
    else |err| {
        std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
        return err;
    }

    const file = try openOatsDB(path);
    defer file.close();

    // get the stack ptr
    var stack_ptr = try file.reader().readInt(u64, .big);

    // iterate through the image paths and push each of them
    for (img_paths) |img_path| {
        // open the image file
        const fimage = try std.fs.cwd().openFile(img_path, .{});
        const image = try fimage.readToEndAlloc(allocator, (try fimage.metadata()).size());
        defer allocator.free(image);

        // get the time & construct the stack item
        const time = std.time.milliTimestamp();
        var path_iter = std.mem.splitBackwardsScalar(u8, img_path, '/');
        const features: oats.item.Features = .{
            .timestamp = time,
            .session_id = session_id,
            .image_filename = path_iter.first(),
            .is_mobile = if (options.is_mobile) {} else null,
        };
        const item = try oats.item.pack(allocator, @bitCast(time), features, image);
        defer allocator.free(item);

        // push the item
        try oats.stack.push(file, &stack_ptr, item);

        std.debug.print("pushed image '{s}'\n", .{img_path});
    }

    // update the stack ptr
    try file.seekTo(oats.stack.stack_ptr_loc);
    try file.writer().writeInt(u64, stack_ptr, .big);
}

pub fn tail(allocator: std.mem.Allocator, to_pop: usize) !void {
    // if database file doesn't exist throw error
    const path = try oats.getHome(allocator);
    if (std.fs.cwd().access(path, .{})) {}
    else |err| {
        std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
        return err;
    }

    const file = try openOatsDB(path);
    defer file.close();

    // get the stack ptr
    var stack_ptr = try file.reader().readInt(u64, .big);

    // print it
    std.debug.print("<<< OATS (LATEST FIRST) >>>\n", .{});
    for (0..to_pop) |_| {
        // double check there are items to pop
        if (stack_ptr == oats.stack.stack_start_loc)
            return error.EmptyStack;

        // pop the last item and decode it
        const raw_item = try oats.stack.pop(allocator, file, &stack_ptr);
        defer allocator.free(raw_item);
        const item = try oats.item.unpack(allocator, stack_ptr + @sizeOf(u32), raw_item);

        // read it's contents
        const contents = try allocator.alloc(u8, item.size - item.contents_offset);
        defer allocator.free(contents);
        try file.seekTo(item.start_idx + item.contents_offset);
        _ = try file.readAll(contents);

        try oats.format.normal(allocator, std.io.getStdErr(), item.id, item.features, contents);
    }

    // note how the stack pointer isn't written, so the 'pops' are
    // temporary and the same as reads
}

pub fn main() !void {
    // initialize the allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // get the arguments
    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    // check for no arguments
    if (args.len == 1)
        return printHelp();

    // checks for the 'help' command
    if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h"))
        return printHelp();
    // checks for the 'version' command
    if (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "-V"))
        return std.debug.print("oats {s}\n", .{oats.version});

    // checks for the 'wipe' command
    if (std.mem.eql(u8, args[1], "wipe")) {
        const path = try oats.getHome(allocator);
        defer allocator.free(path);

        // check if the file exists or not if so, then make sure the user knows
        // what they're doing
        if (std.fs.cwd().access(path, .{})) |_|
            if (args.len > 2 and std.mem.eql(u8, args[2], "--everything")) {}
            else {
                std.debug.print("warning: pre-existing oat database detected, include the flag '--everything' after the wipe command to confirm the wipe\n", .{});
                return error.PreexistingOatsDB;
            }
        else |_| {}

        var file = try std.fs.cwd().createFile(path, .{});
        var writer = file.writer();
        defer file.close();

        // write the magic sequence
        try file.writeAll(oats.magic_seq);

        // write the major version and stack ptr
        try writer.writeInt(u8, oats.maj_ver, .big);
        try writer.writeInt(u64, oats.stack.stack_start_loc, .big);

        return;
    }

    // checks for the 'session' command
    if (std.mem.eql(u8, args[1], "session")) {
        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.cwd().access(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        const file = try openOatsDB(path);
        defer file.close();

        // get the session id
        const session_id = if (args.len >= 3)
            try std.fmt.parseInt(i64, args[2], 10)
        else std.time.milliTimestamp();
        std.debug.print("starting session with id '{}'\n", .{session_id});

        // start the stack session
        try session.session(allocator, file, session_id);

        return;
    }

    // checks for the 'push' command
    if (std.mem.eql(u8, args[1], "push")) {
        // check for the arg
        if (args.len < 3) {
            printHelp();
            return error.ExpectedArgument;
        }

        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.cwd().access(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        const file = try openOatsDB(path);
        defer file.close();

        // get the stack ptr
        var stack_ptr = try file.reader().readInt(u64, .big);

        // get the time & construct the stack item
        const time = std.time.milliTimestamp();
        const features: oats.item.Features = .{
            .timestamp = time,
            .session_id = null,
            .is_mobile = if (options.is_mobile) {} else null,
        };
        const item = try oats.item.pack(allocator, @bitCast(time), features, args[2]);
        defer allocator.free(item);

        // push the item
        try oats.stack.push(file, &stack_ptr, item);

        // update the stack ptr
        try file.seekTo(oats.stack.stack_ptr_loc);
        try file.writer().writeInt(u64, stack_ptr, .big);
        return;
    }

    // checks for the 'push-img' command
    if (std.mem.eql(u8, args[1], "push-img")) {
        // check for the arg
        if (args.len < 3) {
            printHelp();
            return error.ExpectedArgument;
        }

        try pushImg(allocator, null, args[2..]);

        return;
    }

    // checks for the 'pop' command
    if (std.mem.eql(u8, args[1], "pop")) {
        // parse the arg as int
        const to_pop = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 1;
        return pop(allocator, to_pop);
    }

    // checks for the 'tail' command
    if (std.mem.eql(u8, args[1], "tail")) {
        // parse the arg as int
        const to_pop = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 1;
        try tail(allocator, to_pop);

        return;
    }

    // checks for the 'head' command
    if (std.mem.eql(u8, args[1], "head")) {
        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.cwd().access(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        const file = try openOatsDB(path);
        defer file.close();

        // get the stack ptr
        try file.seekTo(oats.stack.stack_ptr_loc);
        const stack_ptr = try file.reader().readInt(u64, .big);

        // parse the arg as int
        const to_read = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 1;

        // read ptr instead of stack ptr (read from start)
        var read_ptr: u64 = oats.stack.stack_start_loc;

        // print it
        std.debug.print("<<< OATS (LATEST LAST) >>>\n", .{});
        for (0..to_read) |_| {
            // double check there are still items to read
            if (read_ptr == stack_ptr)
                return error.EmptyStack;

            // read the next item and decode it
            const start_idx = read_ptr + @sizeOf(u32);
            const raw_item = try oats.stack.readStackEntry(allocator, file, &read_ptr);
            defer allocator.free(raw_item);
            const item = try oats.item.unpack(allocator, start_idx, raw_item);

            // read the contents
            const contents = try allocator.alloc(u8, item.size - item.contents_offset);
            defer allocator.free(contents);
            try file.seekTo(item.start_idx + item.contents_offset);
            _ = try file.readAll(contents);

            try oats.format.normal(allocator, std.io.getStdErr(), item.id, item.features, contents);
        }

        return;
    }

    // checks for the 'sort' command
    if (std.mem.eql(u8, args[1], "sort")) {
        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.cwd().access(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        const file = try openOatsDB(path);
        defer file.close();

        // get the stack ptr
        try file.seekTo(oats.stack.stack_ptr_loc);
        var stack_ptr = try file.reader().readInt(u64, .big);

        // read ptr instead of stack ptr (read from start)
        var read_ptr: u64 = oats.stack.stack_start_loc;

        // store the metadata of the stack items into a void arraylist
        // and a non-void arraylist
        var items = std.ArrayList(oats.item.Metadata).init(allocator);
        defer items.deinit();
        var void_items = std.ArrayList(oats.item.Metadata).init(allocator);
        defer void_items.deinit();

        while (read_ptr != stack_ptr) {
            // read the next item and decode it
            const start_idx = read_ptr + @sizeOf(u32);
            const raw_item = try oats.stack.readStackEntry(allocator, file, &read_ptr);
            defer allocator.free(raw_item);
            const item = try oats.item.unpack(allocator, start_idx, raw_item);

            if (item.features.is_void == null) try items.append(item)
            else try void_items.append(item);
        }

        // sort the items
        std.mem.sortUnstable(std.meta.Elem(@TypeOf(items.items)), items.items, {}, oats.item.Metadata.idLessThan);

        // only insert the void items, if they don't already exist
        for (void_items.items) |item| {
            const exists, const pre_loc = binarySearch(u64, item, items.items, struct{
                fn f(metadata: oats.item.Metadata) u64 {
                    return metadata.id;
                }
            }.f);

            if (!exists)
                try items.insert(pre_loc, item);
        }

        // create a new temporary database file
        const tmp_path = try oats.getTmpHome(allocator);
        defer allocator.free(tmp_path);
        var tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
        defer tmp_file.close();

        // write the boilerplate to the tmp
        
        // write the magic sequence
        try tmp_file.writeAll(oats.magic_seq);

        // write the major version and stack ptr
        try tmp_file.writer().writeInt(u8, oats.maj_ver, .big);
        try tmp_file.writer().writeInt(u64, oats.stack.stack_start_loc, .big);

        // write them back to the new file
        stack_ptr = oats.stack.stack_start_loc; // set stack pointer to stack start to 'wipe' everything
        for (items.items) |item| {
            const raw_item = try allocator.alloc(u8, item.size);
            defer allocator.free(raw_item);
            try file.seekTo(item.start_idx);
            _ = try file.readAll(raw_item);
            try oats.stack.push(tmp_file, &stack_ptr, raw_item);
        }

        // write stack pointer back to the database
        try tmp_file.seekTo(oats.stack.stack_ptr_loc);
        try tmp_file.writer().writeInt(u64, stack_ptr, .big);

        // replace the database with the temporary one
        try std.fs.cwd().deleteFile(path);
        try std.fs.cwd().rename(tmp_path, path);

        return;
    }

    // checks for the 'import' command
    if (std.mem.eql(u8, args[1], "import")) {
        // check for the arg
        if (args.len < 3) {
            printHelp();
            return error.ExpectedArgument;
        }

        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.cwd().access(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        const file = try openOatsDB(path);
        defer file.close();

        // get the stack ptr
        try file.seekTo(oats.stack.stack_ptr_loc);
        var stack_ptr = try file.reader().readInt(u64, .big);

        // read ptr instead of stack ptr (read from start)
        var read_ptr: u64 = oats.stack.stack_start_loc;

        // store the items in the stack in an arraylist to check later (cache locality)
        var items = std.ArrayList(oats.item.Metadata).init(allocator); // store if it's void or not aswell
        defer items.deinit();
        while (read_ptr != stack_ptr) {
            // read the next item and decode it
            const start_idx = read_ptr + @sizeOf(u32);
            const raw_item = try oats.stack.readStackEntry(allocator, file, &read_ptr);
            defer allocator.free(raw_item);
            const item = try oats.item.unpack(allocator, start_idx, raw_item);
            try items.append(item);
        }
        // sort the ids (for binary search)
        std.mem.sortUnstable(oats.item.Metadata, items.items, {}, oats.item.Metadata.idLessThan);

        // read the contents of the database to import

        // if database file doesn't exist throw error
        if (std.fs.cwd().access(args[2], .{})) {}
        else |err| {
            std.debug.print("info: error while importing database\n", .{});
            return err;
        }

        const ifile = try openOatsDB(args[2]);
        defer ifile.close();

        // get the stack ptr
        try ifile.seekTo(oats.stack.stack_ptr_loc);
        const istack_ptr = try ifile.reader().readInt(u64, .big);

        // read ptr instead of stack ptr (read from start)
        read_ptr = oats.stack.stack_start_loc;

        // check the id against the list of pre-existing stack items to avoid collisions
        while (read_ptr != istack_ptr) {
            // read the next item and decode it's id
            const start_idx = read_ptr + @sizeOf(u32);
            const raw_item = try oats.stack.readStackEntry(allocator, ifile, &read_ptr);
            defer allocator.free(raw_item);
            const item = try oats.item.unpack(allocator, start_idx, raw_item);

            // make sure there are no duplicates

            // first check if the id is even within the already established 'bounds'
            if (items.items.len != 0 and item.id >= items.items[0].id and item.id <= items.items[items.items.len-1].id) {
                // check if the id is present already, and if it's a void or not
                const is_found, const found = binarySearch(u64, item, items.items, struct{ fn f(x: oats.item.Metadata) u64 { return x.id; } }.f);
                // don't import if the item already exists and the existing item isn't stubbed or the imported item is void
                if (is_found and (items.items[found].features.is_void == null or item.features.is_void == {}))
                    continue;
            }

            // write the item to the stack
            try oats.stack.push(file, &stack_ptr, raw_item);
            try items.append(item);
        }

        // write stack pointer back to the database
        try file.seekTo(oats.stack.stack_ptr_loc);
        try file.writer().writeInt(u64, stack_ptr, .big);

        std.debug.print("note: after importing the stack items will be out of order, run `oats sort` to sort them.\n", .{});

        return;
    }

    // checks for the 'count' command
    if (std.mem.eql(u8, args[1], "count")) {
        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.cwd().access(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        const file = try openOatsDB(path);
        defer file.close();

        // get the stack ptr
        try file.seekTo(oats.stack.stack_ptr_loc);
        const stack_ptr = try file.reader().readInt(u64, .big);

        // read ptr instead of stack ptr (read from start)
        var read_ptr: u64 = oats.stack.stack_start_loc;

        // count the stack items
        var count: usize = 0;
        while (read_ptr != stack_ptr) {
            allocator.free(try oats.stack.readStackEntry(allocator, file, &read_ptr));
            count += 1;
        }

        std.debug.print("stack item count: ", .{});
        try std.fmt.format(std.io.getStdOut().writer(), "{}", .{count});
        try std.io.getStdOut().writer().writeByte('\n');

        return;
    }

    // checks for the 'raw' command
    if (std.mem.eql(u8, args[1], "raw")) {
        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.cwd().access(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        const file = try openOatsDB(path);
        defer file.close();

        // get the stack ptr
        const stack_ptr = try file.reader().readInt(u64, .big);
        var read_ptr: u64 = 0;

        // read and write everything in blocks of 64K until stack_ptr
        const buffer = try allocator.alloc(u8, 64 * 1024);
        defer allocator.free(buffer);
        const stdout = std.io.getStdOut().writer();
        try file.seekTo(read_ptr);
        while (read_ptr < stack_ptr) : (read_ptr += buffer.len) {
            if (read_ptr + buffer.len >= stack_ptr) {
                _ = try file.readAll(buffer[0..stack_ptr-read_ptr]);
                _ = try stdout.writeAll(buffer[0..stack_ptr-read_ptr]);
            } else {
                _ = try file.readAll(buffer);
                _ = try stdout.writeAll(buffer);
            }
        }

        return;
    }

    // check for the 'markdown' command
    if (std.mem.eql(u8, args[1], "markdown")) {
        // check for the arg
        if (args.len < 3) {
            printHelp();
            return error.ExpectedArgument;
        }

        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.cwd().access(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        const file = try openOatsDB(path);
        defer file.close();

        // get the stack ptr and create the read ptr
        const stack_ptr = try file.reader().readInt(u64, .big);
        var read_ptr: u64 = oats.stack.stack_start_loc;

        // get the timezone
        const tz_offset = try std.fmt.parseInt(i16, args[2], 10)*60;

        // get the media path
        const media_path = if (args.len > 3) args[3] else null;

        try std.io.getStdOut().writeAll("# Oats (Thoughts & Notes)\n---\n");

        // iterate through all the item metadatas and collect them into groups (based on session id)
        var collections = std.AutoHashMap(i64, std.ArrayList(oats.item.Metadata)).init(allocator);
        defer { // free everything
            var iter = collections.valueIterator();
            while (iter.next()) |list| list.deinit();
            collections.deinit();
        }
        var null_sess_prev: ?i64 = null; // if the last thought had a null session id, then this would have the id/timestamp of it
        while (read_ptr != stack_ptr) {
            // read the next item and decode it
            const start_idx = read_ptr + @sizeOf(u32);
            const raw_item = try oats.stack.readStackEntry(allocator, file, &read_ptr);
            defer allocator.free(raw_item);
            const item = try oats.item.unpack(allocator, start_idx, raw_item);

            // if it has a session id, then append to that session
            if (item.features.session_id) |id| {
                null_sess_prev = null;
                // create the list if it doesn't exist already
                const list = collections.getPtr(id) orelse getlist: {
                    try collections.put(id, std.ArrayList(oats.item.Metadata).init(allocator));
                    break :getlist collections.getPtr(id).?;
                };
                try list.append(item);
                continue;
            }

            // otherwise, if there is a previous null session, then simply append to it, otherwise create a new one
            if (null_sess_prev) |sess| {
                try collections.getPtr(sess).?.append(item);
            } else {
                try collections.put(@bitCast(item.id), std.ArrayList(oats.item.Metadata).init(allocator));
                try collections.getPtr(@bitCast(item.id)).?.append(item);
                null_sess_prev = @bitCast(item.id);
            }
        }

        // collect the keys and sort them
        const coll_keys = try allocator.alloc(i64, collections.count());
        defer allocator.free(coll_keys);
        var coll_key_iter = collections.keyIterator();
        var coll_key_i: usize = 0;
        while (coll_key_iter.next()) |key| : (coll_key_i += 1)
            coll_keys[coll_key_i] = key.*;
        std.mem.sortUnstable(i64, coll_keys, {}, basicLessThan(i64));

        // buffer stdout
        var buffered = std.io.bufferedWriter(std.io.getStdOut().writer());
        defer buffered.flush() catch {};

        // iterate through the collections, format them and print them
        var prev_features = oats.item.Features{ .timestamp = null, .session_id = null };
        for (coll_keys) |key| {
            const collection = collections.getPtr(key).?;

            // iterate through the items, format them and print them
            var i: usize = 0;
            while (i < collection.items.len) : (i += 1) {
                const item = collection.items[i];

                // write the markdown header
                try oats.format.markdownHeader(buffered.writer(), tz_offset, item.features, prev_features, i == 0);
                defer prev_features = item.features;

                // if it's a trimmed item, then count them and write it
                if (item.features.is_void != null) {
                    const start = i;
                    while (i < collection.items.len and collection.items[i].features.is_void != null)
                        i += 1;
                    const items = i - start;
                    try std.fmt.format(buffered.writer(), "*{} Trimmed Item", .{items});
                    if (items > 1) _ = try buffered.writer().writeByte('s');
                    try buffered.writer().writeAll("*\n");
                    continue;
                }

                // if it's simply a text item, then read the contents and write it
                if (item.features.image_filename == null) {
                    const contents = try allocator.alloc(u8, item.size - item.contents_offset);
                    defer allocator.free(contents);
                    try file.seekTo(item.start_idx + item.contents_offset);
                    _ = try file.readAll(contents);

                    try oats.format.markdownText(buffered.writer(), contents);
                    continue;
                }

                // otherwise, collect together all the consecutive images into a slice
                var img_idx: usize = i;
                while (img_idx < collection.items.len and collection.items[img_idx].features.image_filename != null)
                    img_idx += 1;
                const images = collection.items[i..img_idx];
                i = img_idx - 1;

                // create the media path and try write the image files
                const media = media_path orelse continue; // if a media path isn't included, dispose of images
                std.fs.cwd().access(media, .{}) catch try std.fs.cwd().makeDir(media);
                const media_session = try std.fmt.allocPrint(allocator, "{s}/{}", .{
                    media,
                    item.features.session_id orelse item.features.timestamp orelse 0,
                });
                defer allocator.free(media_session);
                std.fs.cwd().access(media, .{}) catch try std.fs.cwd().makeDir(media);
                std.fs.cwd().access(media_session, .{}) catch try std.fs.cwd().makeDir(media_session);
                for (images) |image| {
                    // read contents
                    const contents = try allocator.alloc(u8, image.size - image.contents_offset);
                    defer allocator.free(contents);
                    try file.seekTo(image.start_idx + image.contents_offset);
                    _ = try file.readAll(contents);

                    // write to file path
                    const image_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ media_session, image.features.image_filename.? });
                    defer allocator.free(image_path);
                    var img_file = try std.fs.cwd().createFile(image_path, .{});
                    try img_file.writeAll(contents);
                    img_file.close();
                }

                // export the image in markdown format (actually HTML)
                try oats.format.markdownImgs(buffered.writer(), media_session, images);
            }
        }

        return;
    }

    // checks for the 'trim' command
    if (std.mem.eql(u8, args[1], "trim")) {
        // check for the arg
        if (args.len < 3) {
            printHelp();
            return error.ExpectedArgument;
        }

        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.cwd().access(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        const ifile = try openOatsDB(path);
        defer ifile.close();

        // get the stack ptr
        try ifile.seekTo(oats.stack.stack_ptr_loc);
        const istack_ptr = try ifile.reader().readInt(u64, .big);

        // read ptr instead of stack ptr (read from start)
        var read_ptr: u64 = oats.stack.stack_start_loc;

        // create the output file (path is the last arg)
        var ofile = try std.fs.cwd().createFile(args[args.len-1], .{});
        var writer = ofile.writer();
        defer ofile.close();

        // write the magic sequence
        try ofile.writeAll(oats.magic_seq);

        // write the major version and stack ptr
        try writer.writeInt(u8, oats.maj_ver, .big);
        try writer.writeInt(u64, oats.stack.stack_start_loc, .big);

        var ostack_ptr: u64 = oats.stack.stack_start_loc;

        // iterate through the oats items and trim them based upon their features
        read_items: while (read_ptr != istack_ptr) {
            // read the item
            const start_idx = read_ptr + @sizeOf(u32);
            const raw_item = try oats.stack.readStackEntry(allocator, ifile, &read_ptr);
            defer allocator.free(raw_item);
            const item = try oats.item.unpack(allocator, start_idx, raw_item);

            const item_features_bitfield = oats.item.featuresToBitfield(item.features);

            // comptime attribute trimming
            // ugly & inefficient, but works
            for (args[2..args.len-1]) |attr| {
                inline for (@typeInfo(oats.item.FeaturesBitfield).Struct.fields) |field|{
                    if (comptime field.type == bool)
                    if (std.mem.eql(u8, field.name, attr) or std.mem.eql(u8, attr, "everything")) {
                        // check if the item should be trimmed
                        if (@field(item_features_bitfield, field.name) or std.mem.eql(u8, attr, "everything")) {
                            // copy the item's features and push stubbed version
                            var features = item.features;
                            features.is_void = {};
                            const stubbed = try oats.item.pack(allocator, item.id, features, &.{});

                            try oats.stack.push(ofile, &ostack_ptr, stubbed);

                            continue :read_items;
                        }
                        break;
                    };
                } else {
                    return error.AttributeNotFound;
                }
            }

            // only reaches here if the item shouldn't be trimmed
            try oats.stack.push(ofile, &ostack_ptr, raw_item);
        }

        // update stack ptr
        try ofile.seekTo(oats.stack.stack_ptr_loc);
        try writer.writeInt(u64, ostack_ptr, .big);

        return;
    }

    // checks for the 'filter' command
    if (std.mem.eql(u8, args[1], "filter")) {
        // check for the arg
        if (args.len < 3) {
            printHelp();
            return error.ExpectedArgument;
        }

        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.cwd().access(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        const ifile = try openOatsDB(path);
        defer ifile.close();

        // get the stack ptr
        try ifile.seekTo(oats.stack.stack_ptr_loc);
        const istack_ptr = try ifile.reader().readInt(u64, .big);

        // read ptr instead of stack ptr (read from start)
        var read_ptr: u64 = oats.stack.stack_start_loc;

        // create the output file (path is the last arg)
        var ofile = try std.fs.cwd().createFile(args[args.len-1], .{});
        var writer = ofile.writer();
        defer ofile.close();

        // write the magic sequence
        try ofile.writeAll(oats.magic_seq);

        // write the major version and stack ptr
        try writer.writeInt(u8, oats.maj_ver, .big);
        try writer.writeInt(u64, oats.stack.stack_start_loc, .big);

        var ostack_ptr: u64 = oats.stack.stack_start_loc;

        // iterate through the oats items and trim them based upon their features
        read_items: while (read_ptr != istack_ptr) {
            // read the item
            const start_idx = read_ptr + @sizeOf(u32);
            const raw_item = try oats.stack.readStackEntry(allocator, ifile, &read_ptr);
            defer allocator.free(raw_item);
            const item = try oats.item.unpack(allocator, start_idx, raw_item);

            const item_features_bitfield = oats.item.featuresToBitfield(item.features);

            // comptime attribute filtering
            // ugly & inefficient, but works
            for (args[2..args.len-1]) |attr| {
                inline for (@typeInfo(oats.item.FeaturesBitfield).Struct.fields) |field|{
                    if (comptime field.type == bool)
                    if (std.mem.eql(u8, field.name, attr)) {
                        // check if the item should be trimmed
                        if (!@field(item_features_bitfield, field.name)) {
                            // copy the item's features and push stubbed version
                            var features = item.features;
                            features.is_void = {};
                            const stubbed = try oats.item.pack(allocator, item.id, features, &.{});

                            try oats.stack.push(ofile, &ostack_ptr, stubbed);

                            continue :read_items;
                        }
                        break;
                    };
                } else {
                    return error.AttributeNotFound;
                }
            }

            // only reaches here if the item shouldn't be trimmed
            try oats.stack.push(ofile, &ostack_ptr, raw_item);
        }

        // update stack ptr
        try ofile.seekTo(oats.stack.stack_ptr_loc);
        try writer.writeInt(u64, ostack_ptr, .big);

        return;
    }

    // only occurs when there is an invalid command
    printHelp();
    return error.CommandNotFound;
}

/// Prints the help menu message for this cli
fn printHelp() void {
    const help =
        \\Usage: oats [command]
        \\Commands:
        \\    session <?sess_id>      | starts an interactive session that pushes thoughts/notes to the stack from stdin with the specificed session id (defaults to current timestamp)
        \\    push <text>             | push a singular thought/note to the oats stack
        \\    push-img <*paths>       | pushs images to the oats stack
        \\    pop  <?n>               | pops <n> (defaults to 1) items off the stack (removes it)
        \\    tail <?n>               | prints the last <n> (defaults to 1) stack items (thoughts/notes)
        \\    head <?n>               | prints the first <n> (defaults to 1) stack items (thoughts/notes)
        \\    count                   | counts the amount of items on the stack and prints it to stdout
        \\    sort                    | sorts the contents of the oats database based on id
        \\    markdown <tz> <?media>  | pretty-prints the items on the stack in the markdown format, provided with a timezone offset and a path to put media (images & videos) (discarded if not provided)
        \\    raw                     | writes the raw contents of the database to stdout (pipe to a file for backups)
    	\\    import <path>           | reads the raw contents of a database (backup) from the path provided and combines it with the current database
    	\\    trim <?*attrs> <path>   | copies a trimmed version (without items with <attrs> attributes) of the database to <path>
    	\\    filter <?*attrs> <path> | copies a filtered version (only with items with <attrs> attributes) of the database to <path>
        \\    wipe                    | wipes all the contents of the stack and creates a new one
        \\Options:
        \\    -h, --help              | prints this help message
        \\    -V, --version           | prints the version
        \\
    ;
    std.debug.print(help, .{});
}
