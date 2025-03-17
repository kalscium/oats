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
        defer file.close();

        // write the major version and stack ptr
        try oats.stack.writeInt(u8, oats.maj_ver, &file);
        try oats.stack.writeInt(u64, oats.stack.stack_start_loc, &file);
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
