pub const session = @import("session.zig");

const std = @import("std");
const oats = @import("oats");

/// Finds the location of an item in a slice, returns null if not present
pub fn binarySearch(item: anytype, slice: []const @TypeOf(item)) ?usize {
    var low: usize = 0;
    var high: usize = slice.len - 1;

    while (low <= high) {
        const mid = low + (high - low) / 2;

        // check if x is present at mid
        if (slice[mid] == item)
            return mid;

        // if x greater, ignore left half
        if (slice[mid] < item)
            low = mid + 1
        // if x lesser, ignore right half
        else
            high = mid - 1;
    }

    // if this is reached, then item is not present
    return null;
}

pub fn basicLessThan(comptime T: type) fn (context: void, a: T, b: T)bool {
    return struct{
        pub fn call(context: void, a: T, b: T) bool {
            _ = context;
            return a < b;
        }
    }.call;
}

pub fn pop(allocator: std.mem.Allocator, to_pop: usize) !void {
    // if database file doesn't exist throw error
    const path = try oats.getHome(allocator);
    if (std.fs.accessAbsolute(path, .{})) {}
    else |err| {
        std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
        return err;
    }

    // open the database file
    defer allocator.free(path);
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
    defer file.close();

    // double-check the magic sequence
    var magic: [oats.magic_seq.len]u8 = undefined;
    _ = try file.readAll(&magic);
    if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

    // make sure it's of the right major version
    const maj_ver = try file.reader().readInt(u8, .big);
    if (maj_ver != oats.maj_ver) return error.MajVersionMismatch;

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
        const item = oats.item.unpack(stack_ptr + @sizeOf(u32), raw_item);

        // read it's contents
        const contents = try allocator.alloc(u8, item.size - item.contents_offset);
        defer allocator.free(contents);
        try file.seekTo(item.start_idx + item.contents_offset);
        _ = try file.readAll(contents);

        try oats.format.normalFeatures(allocator, std.io.getStdErr(), item.id, item.features);
        try std.fmt.format(std.io.getStdOut().writer(), "{s}\n", .{contents});
    }

    // update the stack ptr
    try file.seekTo(oats.stack.stack_ptr_loc);
    try file.writer().writeInt(u64, stack_ptr, .big);
}

pub fn tail(allocator: std.mem.Allocator, to_pop: usize) !void {
    // if database file doesn't exist throw error
    const path = try oats.getHome(allocator);
    if (std.fs.accessAbsolute(path, .{})) {}
    else |err| {
        std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
        return err;
    }

    // open the database file
    defer allocator.free(path);
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
    defer file.close();

    // double-check the magic sequence
    var magic: [oats.magic_seq.len]u8 = undefined;
    _ = try file.readAll(&magic);
    if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

    // make sure it's of the right major version
    const maj_ver = try file.reader().readInt(u8, .big);
    if (maj_ver != oats.maj_ver) return error.MajVersionMismatch;

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
        const item = oats.item.unpack(stack_ptr + @sizeOf(u32), raw_item);

        // read it's contents
        const contents = try allocator.alloc(u8, item.size - item.contents_offset);
        defer allocator.free(contents);
        try file.seekTo(item.start_idx + item.contents_offset);
        _ = try file.readAll(contents);

        try oats.format.normalFeatures(allocator, std.io.getStdErr(), item.id, item.features);
        try std.fmt.format(std.io.getStdOut().writer(), "{s}\n", .{contents});
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
        if (std.fs.accessAbsolute(path, .{})) |_|
            if (args.len > 2 and std.mem.eql(u8, args[2], "--everything")) {}
            else {
                std.debug.print("warning: pre-existing oat database detected, include the flag '--everything' after the wipe command to confirm the wipe\n", .{});
                return error.PreexistingOatsDB;
            }
        else |_| {}

        var file = try std.fs.createFileAbsolute(path, .{});
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
        if (std.fs.accessAbsolute(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        // open the database file
        defer allocator.free(path);
        var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
        defer file.close();

        // double-check the magic sequence
        var magic: [oats.magic_seq.len]u8 = undefined;
        _ = try file.readAll(&magic);
        if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

        // make sure it's of the right major version
        const maj_ver = try file.reader().readInt(u8, .big);
        if (maj_ver != oats.maj_ver) return error.MajVersionMismatch;

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
        if (std.fs.accessAbsolute(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        // open the database file
        defer allocator.free(path);
        var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
        defer file.close();

        // double-check the magic sequence
        var magic: [oats.magic_seq.len]u8 = undefined;
        _ = try file.readAll(&magic);
        if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

        // make sure it's of the right major version
        const maj_ver = try file.reader().readInt(u8, .big);
        if (maj_ver != oats.maj_ver) return error.MajVersionMismatch;

        // get the stack ptr
        var stack_ptr = try file.reader().readInt(u64, .big);

        // get the time & construct the stack item
        const time = std.time.milliTimestamp();
        const features: oats.item.Features = .{ .timestamp = time, .session_id = null };
        const item = try oats.item.pack(allocator, @bitCast(time), features, args[2]);
        defer allocator.free(item);

        // push the item
        try oats.stack.push(file, &stack_ptr, item);

        // update the stack ptr
        try file.seekTo(oats.stack.stack_ptr_loc);
        try file.writer().writeInt(u64, stack_ptr, .big);
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
        if (std.fs.accessAbsolute(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        // open the database file
        defer allocator.free(path);
        var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
        defer file.close();

        // double-check the magic sequence
        var magic: [oats.magic_seq.len]u8 = undefined;
        _ = try file.readAll(&magic);
        if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

        // make sure it's of the right major version
        const maj_ver = try file.reader().readInt(u8, .big);
        if (maj_ver != oats.maj_ver) return error.MajVersionMismatch;

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
            const item = oats.item.unpack(start_idx, raw_item);

            // read the contents
            const contents = try allocator.alloc(u8, item.size - item.contents_offset);
            defer allocator.free(contents);
            try file.seekTo(item.start_idx + item.contents_offset);
            _ = try file.readAll(contents);

            try oats.format.normalFeatures(allocator, std.io.getStdErr(), item.id, item.features);
            try std.fmt.format(std.io.getStdOut().writer(), "{s}\n", .{contents});
        }

        return;
    }

    // checks for the 'sort' command
    if (std.mem.eql(u8, args[1], "sort")) {
        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.accessAbsolute(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        // open the database file
        defer allocator.free(path);
        var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
        defer file.close();

        // double-check the magic sequence
        var magic: [oats.magic_seq.len]u8 = undefined;
        _ = try file.readAll(&magic);
        if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

        // make sure it's of the right major version
        const maj_ver = try file.reader().readInt(u8, .big);
        if (maj_ver != oats.maj_ver) return error.MajVersionMismatch;

        // get the stack ptr
        try file.seekTo(oats.stack.stack_ptr_loc);
        var stack_ptr = try file.reader().readInt(u64, .big);

        // read ptr instead of stack ptr (read from start)
        var read_ptr: u64 = oats.stack.stack_start_loc;

        // store the metadata of all the stack items in an arraylist
        var items = std.ArrayList(oats.item.Metadata).init(allocator);
        defer items.deinit();
        while (read_ptr != stack_ptr) {
            // read the next item and decode it
            const start_idx = read_ptr + @sizeOf(u32);
            const raw_item = try oats.stack.readStackEntry(allocator, file, &read_ptr);
            defer allocator.free(raw_item);
            const item = oats.item.unpack(start_idx, raw_item);
            try items.append(item);
        }

        // sort the items
        std.mem.sortUnstable(std.meta.Elem(@TypeOf(items.items)), items.items, {}, oats.item.Metadata.idLessThan);

        // create a new temporary database file
        const tmp_path = try oats.getTmpHome(allocator);
        defer allocator.free(tmp_path);
        var tmp_file = try std.fs.createFileAbsolute(tmp_path, .{});
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
        try std.fs.deleteFileAbsolute(path);
        try std.fs.renameAbsolute(tmp_path, path);

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
        if (std.fs.accessAbsolute(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        // open the current database file
        defer allocator.free(path);
        var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
        defer file.close();

        // double-check the magic sequence
        var magic: [oats.magic_seq.len]u8 = undefined;
        _ = try file.readAll(&magic);
        if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

        // make sure it's of the right major version
        const maj_ver = try file.reader().readInt(u8, .big);
        if (maj_ver != oats.maj_ver) return error.MajVersionMismatch;

        // get the stack ptr
        try file.seekTo(oats.stack.stack_ptr_loc);
        var stack_ptr = try file.reader().readInt(u64, .big);

        // read ptr instead of stack ptr (read from start)
        var read_ptr: u64 = oats.stack.stack_start_loc;

        // store the ids of the items in the stack in an arraylist to check later (cache locality)
        var items = std.ArrayList(u64).init(allocator);
        defer items.deinit();
        while (read_ptr != stack_ptr) {
            // read the next item and decode it
            const start_idx = read_ptr + @sizeOf(u32);
            const raw_item = try oats.stack.readStackEntry(allocator, file, &read_ptr);
            defer allocator.free(raw_item);
            const id = oats.item.unpack(start_idx, raw_item).id;
            try items.append(id);
        }
        // sort the ids (for binaru search)
        std.mem.sortUnstable(u64, items.items, {}, basicLessThan(u64));

        // read the contents of the database to import

        // if database file doesn't exist throw error
        var ifile = std.fs.cwd().openFile(args[2], .{}) catch |err| {
            std.debug.print("info: error while importing database\n", .{});
            return err;
        };

        // double-check the magic sequence
        _ = try ifile.readAll(&magic);
        if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

        // make sure it's of the right major version
        const imaj_ver = try ifile.reader().readInt(u8, .big);
        if (imaj_ver != oats.maj_ver) return error.MajVersionMismatch;

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
            const id = oats.item.unpack(start_idx, raw_item).id;

            // make sure there are no duplicates

            // first check if the id is even within the already established 'bounds'
            if (items.items.len == 0 or id < items.items[0] or id > items.items[items.items.len-1]) {}
            
            // check if the id is present already
            else if (binarySearch(id, items.items) != null)
                continue;

            // write the item to the stack
            try oats.stack.push(file, &stack_ptr, raw_item);
            try items.append(id);
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
        if (std.fs.accessAbsolute(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        // open the database file
        defer allocator.free(path);
        var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
        defer file.close();

        // double-check the magic sequence
        var magic: [oats.magic_seq.len]u8 = undefined;
        _ = try file.readAll(&magic);
        if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

        // make sure it's of the right major version
        const maj_ver = try file.reader().readInt(u8, .big);
        if (maj_ver != oats.maj_ver) return error.MajVersionMismatch;

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
        if (std.fs.accessAbsolute(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        // open the read database file
        defer allocator.free(path);
        var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
        defer file.close();

        // double-check the magic sequence
        var magic: [oats.magic_seq.len]u8 = undefined;
        _ = try file.readAll(&magic);
        if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

        // make sure it's of the right major version
        const maj_ver = try file.reader().readInt(u8, .big);
        if (maj_ver != oats.maj_ver) return error.MajVersionMismatch;

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
        // if database file doesn't exist throw error
        const path = try oats.getHome(allocator);
        if (std.fs.accessAbsolute(path, .{})) {}
        else |err| {
            std.debug.print("info: no oats database found, try running 'oats wipe' to initialize a new one\n", .{});
            return err;
        }

        // open the read database file
        defer allocator.free(path);
        var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
        defer file.close();

        // double-check the magic sequence
        var magic: [oats.magic_seq.len]u8 = undefined;
        _ = try file.readAll(&magic);
        if (!std.mem.eql(u8, &magic, oats.magic_seq)) return error.MagicMismatch;

        // make sure it's of the right major version
        const maj_ver = try file.reader().readInt(u8, .big);
        if (maj_ver != oats.maj_ver) return error.MajVersionMismatch;

        // get the stack ptr and create the read ptr
        const stack_ptr = try file.reader().readInt(u64, .big);
        var read_ptr: u64 = oats.stack.stack_start_loc;

        // get the timezone, otherwise default to new-york
        const tz_offset = if (args.len > 2) try std.fmt.parseInt(i16, args[2], 10)*60 else oats.datetime.datetime.timezones.America.New_York.offset;

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
            const item = oats.item.unpack(start_idx, raw_item);

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

            // the minimum amount of thoughts/notes in a collection (otherwise combined with the previous collection)
            const min_collection_thres = 4;

            // if it's smaller than the collection threshold, it doesn't count as a new collection
            var new_col = collection.items.len >= min_collection_thres;

            // iterate through the items, format them and print them
            for (collection.items) |item| {
                // read contents
                const contents = try allocator.alloc(u8, item.size - item.contents_offset);
                defer allocator.free(contents);
                try file.seekTo(item.start_idx + item.contents_offset);
                _ = try file.readAll(contents);

                // write to stdout
                try oats.format.markdown(buffered.writer(), tz_offset, item.features, contents, prev_features, new_col);

                prev_features = item.features;
                new_col = false;
            }
        }

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
        \\    session       | starts an interactive session that pushes thoughts/notes to the stack from stdin
        \\    push <text>   | push a singular thought/note to the stack
        \\    pop  <n>      | pops <n> (defaults to 1) items off the stack (removes it)
        \\    tail <n>      | prints the last <n> (defaults to 1) stack items (thoughts/notes)
        \\    head <n>      | prints the first <n> (defaults to 1) stack items (thoughts/notes)
        \\    count         | counts the amount of items on the stack and prints it to stdout
        \\    sort          | sorts the contents of the oats database based on id
        \\    markdown <tz> | pretty-prints the items on the stack in the markdown format, provided with a timezone offset (defaults to new york)
        \\    raw           | writes the raw contents of the database to stdout (pipe to a file for backups)
    	\\    import <path> | reads the raw contents of a database (backup) from the path provided and combines it with the current database
        \\    wipe          | wipes all the contents of the stack and creates a new one
        \\Options:
        \\    -h, --help    | prints this help message
        \\    -V, --version | prints the version
        \\
    ;
    std.debug.print(help, .{});
}
