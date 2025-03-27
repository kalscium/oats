pub const session = @import("session.zig");

const std = @import("std");
const oats = @import("oats");

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

        // start the stack session
        try session.session(allocator, file);

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
        const features: oats.item.Features = .{ .timestamp = time };
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

        // parse the arg as int
        const to_pop = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 1;

        // print it
        std.debug.print("<<< POPPED OATS (LATEST FIRST) >>>\n", .{});
        for (0..to_pop) |_| {
            // double check there are items to pop
            if (stack_ptr == oats.stack.stack_start_loc)
                return error.EmptyStack;

            // pop the last item and decode it
            const raw_item = try oats.stack.pop(allocator, file, &stack_ptr);
            defer allocator.free(raw_item);
            const item = oats.item.unpack(raw_item);

            try oats.format.normalFeatures(allocator, std.io.getStdErr(), item.id, item.features);
            try std.fmt.format(std.io.getStdOut().writer(), "{s}\n", .{item.contents});
        }

        // update the stack ptr
        try file.seekTo(oats.stack.stack_ptr_loc);
        try file.writer().writeInt(u64, stack_ptr, .big);
        return;
    }

    // checks for the 'tail' command
    if (std.mem.eql(u8, args[1], "tail")) {
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

        // parse the arg as int
        const to_pop = if (args.len > 2) try std.fmt.parseInt(usize, args[2], 10) else 1;

        // print it
        std.debug.print("<<< OATS (LATEST FIRST) >>>\n", .{});
        for (0..to_pop) |_| {
            // double check there are items to pop
            if (stack_ptr == oats.stack.stack_start_loc)
                return error.EmptyStack;

            // pop the last item and decode it
            const raw_item = try oats.stack.pop(allocator, file, &stack_ptr);
            defer allocator.free(raw_item);
            const item = oats.item.unpack(raw_item);

            try oats.format.normalFeatures(allocator, std.io.getStdErr(), item.id, item.features);
            try std.fmt.format(std.io.getStdOut().writer(), "{s}\n", .{item.contents});
        }

        // note how the stack pointer isn't written, so the 'pops' are
        // temporary and the same as reads

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
            const raw_item = try oats.stack.readStackEntry(allocator, file, &read_ptr);
            defer allocator.free(raw_item);
            const item = oats.item.unpack(raw_item);

            try oats.format.normalFeatures(allocator, std.io.getStdErr(), item.id, item.features);
            try std.fmt.format(std.io.getStdOut().writer(), "{s}\n", .{item.contents});
        }

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

        // iterate through the items, format them and print them
        var prev_features = oats.item.Features{ .timestamp = null };
        var buffered = std.io.bufferedWriter(std.io.getStdOut().writer());
        defer buffered.flush() catch {};
        while (read_ptr != stack_ptr) {
            // read the next item and decode it
            const raw_item = try oats.stack.readStackEntry(allocator, file, &read_ptr);
            defer allocator.free(raw_item);
            const item = oats.item.unpack(raw_item);

            // write to stdout
            try oats.format.markdown(buffered.writer(), tz_offset, item.features, item.contents, prev_features);

            prev_features = item.features;
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
        // \\    sort          | sorts the contents of the oats database based on id
        \\    markdown <tz> | pretty-prints the items on the stack in the markdown format, provided with a timezone offset (defaults to new york)
        \\    raw           | writes the raw contents of the database to stdout (pipe to a file for backups)
        // \\    import        | reads the raw contents of a database (backup) from stdin and combines it with the current database
        \\    wipe          | wipes all the contents of the stack and creates a new one
        \\Options:
        \\    -h, --help    | prints this help message
        \\    -V, --version | prints the version
        \\
    ;
    std.debug.print(help, .{});
}
