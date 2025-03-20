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

    // checks for the 'wipe' command
    if (std.mem.eql(u8, args[1], "wipe")) {
        const path = try oats.getHome(allocator);
        defer allocator.free(path);
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
        var file = try std.fs.openFileAbsolute(path, .{ .lock = .exclusive, .mode = .read_write });
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
        const time = std.time.timestamp();
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
        \\    pop           | pops a thought/note off the stack (removes it)
        \\    tail <n>      | prints the last <n> stack items (thoughts/notes)
        \\    head <n>      | prints the first <n> stack items (thoughts/notes)
        \\    print         | prints all the contents of the items on the stack to stdout
        \\    markdown      | pretty-prints the items on the stack in the markdown format
        \\    raw           | writes the raw contents of the database to stdout (pipe to a file for backups)
        \\    import        | reads the raw contents of a database (backup) from stdin and combines it with the current database
        \\    wipe          | wipes all the contents of the stack and creates a new one
        \\Options:
        \\    -h, --help    | prints this help message
        \\    -V, --version | prints the version
        \\
    ;
    std.debug.print(help, .{});
}
