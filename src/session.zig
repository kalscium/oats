//! Deals with stdin for an interactive writing session
//! 
//! **note:** this is part of main as it's strictly only part of the CLI, and
//!           doesn't fit in the context of a static library.

const builtin = @import("builtin");
const std = @import("std");
const oats = @import("oats");
const main = @import("main.zig");

const help = "\x1b[35m<<< \x1b[0;1mOATS SESSION \x1b[35m>>>\x1b[0m\n\x1b[35m*\x1b[0m welcome to a space for random thughts or notes!\n\x1b[35m*\x1b[0m some quick controls:\n  \x1b[35m*\x1b[0m CTRL+D or \x1b[36m:\x1b[0mexit to exit the thought session\n  \x1b[35m*\x1b[0m CTRL+C to cancel the line\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mhelp` to print this help message\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mtail <?n>` to print the last <n> stack items\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mpop <?n>` to pop the last <n> stack items\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mclear` to clear the screen\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0msession <?sess_id>` to change the session id\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mimg <*images>` to push images to the oats stack\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mfile <*paths>` to push files at <paths> to the oats stack\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mvid <*paths>` to push vidoes at <paths> to the oats stack\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mamend` to hard-edit the latest stack item\n";

const TerminalFlags = switch (builtin.target.os.tag) {
    .linux => std.os.linux.termios,
    .windows => std.os.windows.DWORD,
    else => @compileError("unsupported system"),
};

/// Gets the console window width (platform independant)
pub fn windowWidth() !usize {
    // linux implementation
    if (comptime builtin.target.os.tag == .linux) {
        const ioctl = @cImport(@cInclude("sys/ioctl.h"));

        var winsize: ioctl.winsize = undefined;
        _ = ioctl.ioctl(std.os.linux.STDOUT_FILENO, ioctl.TIOCGWINSZ, &winsize);

        return winsize.ws_col;
    } else if (comptime builtin.target.os.tag == .windows) {
        var csbi: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        const handle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) orelse return error.ConsoleDevMissingHandle;
        _ = std.os.windows.kernel32.GetConsoleScreenBufferInfo(handle, &csbi);
        return @intCast(csbi.srWindow.Right - csbi.srWindow.Left + 1);
    } else @compileError("unsupported operating system");
}

/// Enables a console mode (platform independant)
pub fn setConMode(flags: *const TerminalFlags) !void {
    switch (comptime builtin.target.os.tag) {
        .linux => _ = std.os.linux.tcsetattr(std.os.linux.STDIN_FILENO, .FLUSH, flags),
        .windows => _ = std.os.windows.kernel32.SetConsoleMode(try std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE), flags.*),
        else => @compileError("unsupported system"),
    }
}

/// Enables the terminal raw mode (platform independant) and returns the original mode so you can switch back
pub fn enableRawMode() !TerminalFlags {
    // linux implementation
    if (comptime builtin.target.os.tag == .linux) {
        // get original flags
        var orig: std.os.linux.termios = undefined;
        _ = std.os.linux.tcgetattr(std.os.linux.STDIN_FILENO, &orig);

        // our custom 'raw' flags
        var raw = orig;
        // disable echo & line buffering
        raw.lflag.ECHO  = false;
        raw.lflag.ICANON = false;
        // disable Ctrl-C & Ctrl-Z signals
        raw.lflag.ISIG = false;
        // disable Ctrl-S & Ctrl-Q
        raw.iflag.IXON = false;
        // disable Ctrl-V & fix Ctrl-M
        raw.lflag.IEXTEN = false;
        // misc
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK = false;
        raw.iflag.ICRNL = false;
        raw.iflag.ISTRIP = false;
        raw.cflag.CSTOPB = true;

        // set the attrs and return original
        _ = std.os.linux.tcsetattr(std.os.linux.STDIN_FILENO, .FLUSH, &raw);
        return orig;
    } else if (comptime builtin.os.tag == .windows) {
        // flags
        var inorig: std.os.windows.DWORD = undefined;
        const inhandle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) orelse return error.ConsoleDevMissingHandle;
        _ = std.os.windows.kernel32.GetConsoleMode(inhandle, &inorig);
        var outorig: std.os.windows.DWORD = undefined;
        const outhandle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) orelse return error.ConsoleDevMissingHandle;
        _ = std.os.windows.kernel32.GetConsoleMode(outhandle, &outorig);
        const windows = @cImport(@cInclude("windows.h"));
        // const flags = orig & comptime ~@as(std.os.windows.DWORD, 0x0004 | 0x0010 | 0x0001 | 0x0040 | 0x0001 | 0x0002 | 0x0020 | 0x0008) | 0x0200 | 0x0004;

        const inflags = inorig | windows.ENABLE_VIRTUAL_TERMINAL_INPUT;
        const outflags = outorig | windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING | windows.DISABLE_NEWLINE_AUTO_RETURN;

        _ = std.os.windows.kernel32.SetConsoleMode(inhandle, inflags);
        _ = std.os.windows.kernel32.SetConsoleMode(outhandle, outflags);

        return inflags;
    } else @compileError("unsupported operating system");
}

/// Prints a line starting from a cursor wrapping at line ends
/// 
/// Does it work?
/// Yes.
/// Do I know why it works?
/// No.
/// Is it efficient in any way?
/// No.
/// But does it work?
/// Yes.
/// So am I going to touch it?
/// No.
pub fn wrapLine(
    line: []const u8,
    cursor: usize,
    coloumns: usize,
    free_lines: *usize,
    wrap_prompt: []const u8,
    stdout: anytype,
) !void {
    if (line.len == 0) return; // nothing to print

    // calculate the lines already printed and the total lines
    const offset_ln = (cursor-|1) / coloumns;
    const total_ln = line.len / coloumns;

    try stdout.writeAll("\x1B[?25l\x1B[0K");

    // write the first line the cursor is on
    const first_line = line[cursor-|1..@min(line.len, (offset_ln + 1) * coloumns)];
    try stdout.writeAll(first_line);

    // write the rest of the whole lines
    var current_ln = offset_ln + 1;
    while (current_ln <= total_ln) : (current_ln += 1) {
        // either move down if there is a free line or write a newline if there isn't
        if (free_lines.* == 0) {
            try stdout.writeByte('\n');
        } else {
            try stdout.writeAll("\x1B[1B\x1B[0G");
            free_lines.* -= 1;
        }

        // wipe & prompt
        try stdout.writeAll("\x1B[2K");
        try stdout.writeAll(wrap_prompt);

        // write the line
        const wrapped_line = line[@min(line.len, current_ln*coloumns)..@min(line.len, current_ln*coloumns + coloumns)];
        try stdout.writeAll(wrapped_line);
    }

    // set the free_lines state to the position of the cursor
    free_lines.* = total_ln - offset_ln;

    // move the cursor back to it's starting position
    if (free_lines.* > 0)
        try std.fmt.format(stdout, "\x1B[{}A", .{free_lines.*});
    const moved: isize = @as(isize, @intCast(line.len % coloumns)) - @as(isize, @intCast((cursor -| 1) % coloumns));
    if (moved > 0)
        try std.fmt.format(stdout, "\x1B[{}D", .{moved})
    else if (moved < 0)
        try std.fmt.format(stdout, "\x1B[{}C", .{-moved});

    // unhide it
    try stdout.writeAll("\x1B[?25h");
}

/// Reads a line from stdin with the specified prompt and initial text in raw mode and returns it, owned by caller
pub fn readLine(allocator: std.mem.Allocator, comptime prompt_len: usize, prompt: []const u8, comptime wrap_prompt: []const u8, initial_text: []const u8, sess_id: *i64) !?std.ArrayList(u8) {
    // can you imagine if I added line scrolling? that would be painful.

    var line = std.ArrayList(u8).init(allocator);

    var cursor: usize = line.items.len; // index into the line
    var escape = false; // if parsing escape code
    var escape_arrow = false; // if parsing arrow escape code
    var stdout = std.io.getStdOut().writer();

    try stdout.writeAll(prompt);

    // get window size
    const ws_col = try windowWidth();
    const coloumns = ws_col - prompt_len;

    // keep track of free lines to write to
    var free_lines: usize = 0;

    // if the line is to be cancelled / cleared
    var cancel_line = false;

    // write the initial text and jump to the end of the line
    try line.appendSlice(initial_text);
    try wrapLine(line.items, cursor, coloumns, &free_lines, wrap_prompt, stdout);
    try std.fmt.format(stdout, "\x1B[{}G", .{prompt_len + 1 + line.items.len % coloumns});
    if (line.items.len / coloumns > 0)
        try std.fmt.format(stdout, "\x1B[{}B", .{line.items.len / coloumns});
    cursor = line.items.len;

    // keep reading until EOF or new-line
    while (std.io.getStdIn().reader().readByte()) |char| {
        // check for CTRL+D (exit)
        if (char == 4) return error.UserInterrupt;

        // check for CTRL+C (clear)
        if (char == 3) {
            cancel_line = true;
            break;
        }

        // check for escape codes (linux & windows)
        if (char == 27 or char == 0 or char == 224) {
            escape = true;
            continue;
        }

        // check for arrow escape codes
        if (escape and char == 91) {
            escape_arrow = true;
            continue;
        }

        // check for tabs
        if (char == '\t') {
            try line.insertSlice(cursor, "  ");
            cursor += 2;

            // print changes to terminal
            try wrapLine(line.items, cursor, coloumns, &free_lines, wrap_prompt, stdout);
            try std.fmt.format(stdout, "\x1B[{}G", .{prompt_len+1+cursor % coloumns}); // skip the prompt
            if ((cursor-1) / coloumns > 0 and cursor % coloumns <= 2) {
                try stdout.writeAll("\x1B[1B"); // go one down
                std.debug.print("\nthis will crash, and I don't know why\nwait until the oats session rewrite...\n", .{});
                free_lines -= 1;
            }

            continue;
        }

        // check for `:` (commands)
        if (char == ':' and cursor == 0) {
            cancel_line = true;
            readCommand(allocator, sess_id) catch |err| {
                // don't crash on errors
                // except for user interrupts
                if (err == error.UserInterrupt) return err;
                std.debug.print("error: {!}\n", .{err});
            };
            break;
        }

        // check for left arrow
        if (escape_arrow and char == 68 and cursor > 0) {
            // update state
            escape = false;
            escape_arrow = false;

            // print changes to terminal
            // 
            // if you've already reached the start of the console line, then go
            // to the above one (line wrapping)
            if (cursor % coloumns == 0) {
                try stdout.writeAll("\x1B[1A"); // go one up
                try std.fmt.format(stdout, "\x1B[{}G", .{ws_col}); // go to end of line
                free_lines += 1;
            } else {
                try stdout.writeAll(&.{ 27, 91, 68 }); // otherwise just go left
            } 

            cursor -= 1;
            continue;
        }

        // check for right arrow
        if (escape_arrow and char == 67 and cursor < line.items.len) {
            escape = false;
            escape_arrow = false;

            // print changes to terminal
            // 
            // if you reach the end of the line then go to the next one (line wrapping)
            if (cursor % coloumns == coloumns-1) {
                try stdout.writeAll("\x1B[1B"); // go one down
                try std.fmt.format(stdout, "\x1B[{}G", .{prompt_len+1}); // skip the prompt
                free_lines -= 1;
            } else {
                try stdout.writeAll(&.{ 27, 91, 67 });
            }

            cursor += 1;
            continue;
        }

        // check for up arrow (make sure it's not the first line)
        if (escape_arrow and char == 65 and cursor / coloumns > 0) {
            escape = false;
            escape_arrow = false;

            // go to the above line at the same point (remainder)
            cursor = cursor - coloumns;
            try stdout.writeAll("\x1B[1A");
            continue;
        }

        // check for down arrow (make sure there's lines below it)
        if (escape_arrow and char == 66 and line.items.len / coloumns - cursor / coloumns > 0) {
            escape = false;
            escape_arrow = false;

            // go to the below line, at the cursor coloumn or end of the line, whichever is closer
            const estimated = cursor + coloumns;
            if (line.items.len < estimated) {
                try std.fmt.format(stdout, "\x1B[1B\x1B[{}D", .{estimated-line.items.len}); // move to the end of the line
                cursor = line.items.len;
            } else {
                try stdout.writeAll("\x1B[1B");
                cursor = estimated;
            }

            continue;
        }

        // check for the vim-like ESC+I (to go to the start of the line)
        if (escape and char == 'I') {
            escape = false;

            try std.fmt.format(stdout, "\x1B[{}G", .{prompt_len+1});
            if (cursor / coloumns > 0)
                try std.fmt.format(stdout, "\x1B[{}A", .{cursor / coloumns});

            cursor = 0;

            continue;
        }

        // check for the vim-like ESC+A (to go to the end of the line)
        if (escape and char == 'A') {
            escape = false;

            try std.fmt.format(stdout, "\x1B[{}G", .{line.items.len % coloumns + prompt_len + 1});
            const diff = line.items.len / coloumns - cursor / coloumns;
            if (diff > 0)
                try std.fmt.format(stdout, "\x1B[{}B", .{diff});

            cursor = line.items.len;

            continue;
        }

        // if there is an invalid escape code, forget about it
        if (escape) {
            // note how this isn't reached when there is an arrow
            escape = false;
            escape_arrow = false;
            continue;
        }

        // check for backspace
        if (char == 127) {
            // only remove if there is stuff to remove
            if (cursor == 0) continue;

            // print changes to terminal

            // if you've already reached the start of the console line, then go
            // to the above one (line wrapping)
            if (cursor % coloumns == 0) {
                try std.fmt.format(stdout, "\x1B[1A\x1B[{}G", .{ws_col}); // go to end of line
                free_lines += 1;
            } else {
                try stdout.writeAll(&.{ 27, 91, 68 }); // otherwise just go left
            }
            cursor -= 1;
            // write a space to overwrite the deleted character if the cursor is at zero
            if (cursor == 0)
                try stdout.writeAll(" \x1B[1D");
            _ = line.orderedRemove(cursor);
            // you want to print the state of the lines *after* deletion, not before
            try wrapLine(line.items, cursor+1, coloumns, &free_lines, wrap_prompt, stdout);

            continue;
        }

        // check for enter (newline)
        if (char == '\n' or char == '\r') break;

        // otherwise treat it like a normal character

        try line.insert(cursor, char);

        // print changes to terminal
        cursor += 1;

        try wrapLine(line.items, cursor, coloumns, &free_lines, wrap_prompt, stdout);
        // if you reach the end of the line then go to the next one (line wrapping)
        if ((cursor-1) % coloumns == coloumns-1) {
            try stdout.writeAll("\x1B[1B"); // go one down
            try std.fmt.format(stdout, "\x1B[{}G", .{prompt_len+1}); // skip the prompt
            free_lines -= 1;
        } else {
            try stdout.writeAll(&.{ 27, 91, 67 });
        }
    } else |_| {}

    // cleanup (jump to either the first or last line to move onto the next note)

    const lines = line.items.len / coloumns;

    // if the line is canceled, jump to the first line after clearing all of it's contents
    if (cancel_line) {
        if ((cursor -| 1) / coloumns > 0) { // only jump if the cursor is not already on the first line
            const cleanup_jump = (cursor - 1) / coloumns;
            try std.fmt.format(stdout, "\x1B[?25l\x1B[{}A", .{cleanup_jump}); // hide the line and jump
        }

        // only if there's more than one line
        if (lines > 0) {
            // wipe all the lines after it and go back to the first line
            try stdout.writeBytesNTimes("\x1B[1B\x1B[2K", lines);
            try std.fmt.format(stdout, "\x1B[{}A", .{lines});
        }

        // clear the line and go to the start of it before unhiding the cursor
        try stdout.writeAll("\x1B[?25h\x1B[2K\x1B[0G");

        // free the line and return that it's been cancelled
        line.deinit();
        return null;
    }

    // this is when the line isn't cleared and needs to be jumped after it

    // only jump if the line spans more than one console line
    if (lines > 0) {
        const cleanup_jump = lines - cursor / coloumns;
        if (cleanup_jump != 0) // only jump if the cursor isn't already on the last line
            try std.fmt.format(stdout, "\x1B[{}B", .{cleanup_jump});
    }
    if (line.items.len % coloumns != 0) try stdout.writeByte('\n');
    try std.fmt.format(stdout, "\x1B[{}G", .{prompt_len * 0});

    return line;
}

/// Reads a line as a command from stdin with the specified prompt in raw mode and executes it
pub fn readCommand(allocator: std.mem.Allocator, sess_id: *i64) anyerror!void {
    const prompt_len = 6;
    const prompt = "\x1b[2K\x1b[0G    \x1b[36;1m: \x1b[0m";
    const wrap_prompt = "\x1b[30;1m  ... \x1b[0m";

    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();

    var cursor: usize = line.items.len; // index into the line
    var stdout = std.io.getStdOut().writer();

    try stdout.writeAll(prompt);

    const ws_col = try windowWidth();
    const coloumns = ws_col - prompt_len;

    // keep track of free lines to write to
    var free_lines: usize = 0;

    // keep reading until EOF or new-line
    while (std.io.getStdIn().reader().readByte()) |char| {
        // check for CTRL+D (exit)
        if (char == 4) return error.UserInterrupt;

        // check for CTRL+C (cancel)
        if (char == 3) return;

        // check for ESC
        if (char == 27) return;

        // check for backspace
        if (char == 127) {
            // if cursor is zero, then break
            if (cursor == 0) break;

            // print changes to terminal
             
            // if you've already reached the start of the console line, then go
            // to the above one (line wrapping)
            if (cursor % coloumns == 0) {
                try std.fmt.format(stdout, "\x1B[1A\x1B[{}G", .{ws_col}); // go to end of line
                free_lines += 1;
            } else {
                try stdout.writeAll(&.{ 27, 91, 68 }); // otherwise just go left
            }
            cursor -= 1;
            // write a space to overwrite the deleted character if the cursor is at zero
            if (cursor == 0)
                try stdout.writeAll(" \x1B[1D");
            _ = line.orderedRemove(cursor);
            // you want to print the state of the lines *after* deletion, not before
            try wrapLine(line.items, cursor+1, coloumns, &free_lines, wrap_prompt, stdout);

            continue;
        }

        // check for enter (newline)
        if (char == '\r' or char == '\r') break;

        // otherwise treat it like a normal character

        try line.insert(cursor, char);

        // print changes to terminal
        cursor += 1;

        try wrapLine(line.items, cursor, coloumns, &free_lines, wrap_prompt, stdout);
        // if you reach the end of the line then go to the next one (line wrapping)
        if ((cursor-1) % coloumns == coloumns-1) {
            try stdout.writeAll("\x1B[1B"); // go one down
            try std.fmt.format(stdout, "\x1B[{}G", .{prompt_len+1}); // skip the prompt
            free_lines -= 1;
        } else {
            try stdout.writeAll(&.{ 27, 91, 67 });
        }
    } else |_| {}

    // slight cleanup beforehand

    const lines = line.items.len / coloumns;
    if ((cursor -| 1) / coloumns > 0) { // only jump if the cursor is not already on the first line
        const cleanup_jump = (cursor - 1) / coloumns;
        try std.fmt.format(stdout, "\x1B[?25l\x1B[{}A", .{cleanup_jump}); // hide the line and jump
    }

    // only if there's more than one line
    if (lines > 0) {
        // wipe all the lines after it and go back to the first line
        try stdout.writeBytesNTimes("\x1B[1B\x1B[2K", lines);
        try std.fmt.format(stdout, "\x1B[{}A", .{lines});
    }

    // clear the line and go to the start of it before unhiding the cursor
    try stdout.writeAll("\x1B[?25h\x1B[2K\x1B[0G");

    // check for no command
    if (line.items.len == 0) return;

    var split = std.mem.splitScalar(u8, line.items, ' ');
    const split_first = split.first();

    // check for the 'exit' command
    if (std.mem.eql(u8, split_first, "exit"))
        return error.UserInterrupt;

    // check for the 'help' command
    if (std.mem.eql(u8, split_first, "help"))
        return std.debug.print(help, .{});

    // check for the 'clear' command
    if (std.mem.eql(u8, split_first, "clear")) {
        try stdout.writeAll("\x1B[H\x1B[2J");
        return;
    }

    // check for the 'pop' command
    if (std.mem.eql(u8, split_first, "pop")) {
        const to_pop = if (split.next()) |raw_to_pop|
            try std.fmt.parseInt(usize, raw_to_pop, 10)
        else 1;
        try main.pop(allocator, to_pop);
        return;
    }

    // check for the 'img' command
    if (std.mem.eql(u8, split_first, "img")) {
        // collect the arguments
        const args_len = std.mem.count(u8, line.items, " ");
        const args = try allocator.alloc([]const u8, args_len);
        defer allocator.free(args);
        var i: usize = 0;
        while (split.next()) |arg| : (i += 1) args[i] = arg;

        // check for args
        if (args.len < 1) return error.ExpectedArgument;

        try main.pushImg(allocator, sess_id.*, args);

        return;
   }

    // check for the 'file' command
    if (std.mem.eql(u8, split_first, "file")) {
        // collect the arguments
        const args_len = std.mem.count(u8, line.items, " ");
        const args = try allocator.alloc([]const u8, args_len);
        defer allocator.free(args);
        var i: usize = 0;
        while (split.next()) |arg| : (i += 1) args[i] = arg;

        // check for args
        if (args.len < 1) return error.ExpectedArgument;

        try main.pushFile(allocator, sess_id.*, args);

        return;
   }

    // check for the 'vid' command
    if (std.mem.eql(u8, split_first, "vid")) {
        // collect the arguments
        const args_len = std.mem.count(u8, line.items, " ");
        const args = try allocator.alloc([]const u8, args_len);
        defer allocator.free(args);
        var i: usize = 0;
        while (split.next()) |arg| : (i += 1) args[i] = arg;

        // check for args
        if (args.len < 1) return error.ExpectedArgument;

        try main.pushVid(allocator, sess_id.*, args);

        return;
   }

    // check for the 'tail' command
    if (std.mem.eql(u8, split_first, "tail")) {
        const to_pop = if (split.next()) |raw_to_pop|
            try std.fmt.parseInt(usize, raw_to_pop, 10)
        else 1;
        try main.tail(allocator, to_pop);
        return;
    }

    // check for the 'session' command
    if (std.mem.eql(u8, split_first, "session")) {
        sess_id.* = if (split.next()) |raw_sess_id|
            try std.fmt.parseInt(i64, raw_sess_id, 10)
        else std.time.milliTimestamp();
        std.debug.print("updated session id to '{}'\n", .{sess_id.*});
        return;
    }

    // check for the 'amend' command
    if (std.mem.eql(u8, split_first, "amend")) {
        // if database file doesn't exist throw error
        const path = try main.databaseExists(allocator);
        defer allocator.free(path);

        const file = try main.openOatsDB(path);
        defer file.close();

        // get the stack ptr
        var stack_ptr = try file.reader().readInt(u64, .big);

        // pop the last item
        const raw_last = try oats.stack.pop(allocator, file, &stack_ptr);
        defer allocator.free(raw_last);
        const last = try oats.item.unpack(allocator, @intCast(stack_ptr + @sizeOf(u32)), raw_last);

        // throw error on images, files or void
        if (last.features.image_filename) |_|
            return error.CannotAmendImage;
        if (last.features.filename) |_|
            return error.CannotAmmendFile;
        if (last.features.is_void) |_|
            return error.CannotAmendVoidItem;

        // get the conents of the last item
        try file.seekTo(last.start_idx+last.contents_offset);
        const last_contents = try allocator.alloc(u8, last.size-last.contents_offset);
        defer allocator.free(last_contents);
        _ = try file.readAll(last_contents);
        
        // read the line
        const contentso = try readLine(allocator, 4, "\x1b[36m=>> \x1b[0m", "\x1b[30;1m... \x1b[0m", last_contents, sess_id);
        const contents = contentso orelse return; // return without writing stack_ptr (no changes made)
        defer contents.deinit();

        // construct the item
        const item = try oats.item.pack(allocator, @intCast(std.time.milliTimestamp()), .{ // should have a different id
            .timestamp = last.features.timestamp, // might change this cuz it's modifying history
            .session_id = last.features.session_id,
            .is_mobile = last.features.is_mobile,
        }, contents.items);
        defer allocator.free(item);

        // only push if the amended version is larger than zero
        // (zero-sized amends count as pops)
        if (contents.items.len > 0)
            try oats.stack.push(file, &stack_ptr, item);

        // update the stack ptr
        try file.seekTo(oats.stack.stack_ptr_loc);
        try file.writer().writeInt(u64, stack_ptr, .big);

        return;
    }

    // otherwise the command is invalid
    std.debug.print("error: unknown command '{s}'\n", .{split_first});
    return;
}

/// Starts the interactive oats session
pub fn session(allocator: std.mem.Allocator, file: std.fs.File, isession_id: i64) !void {
    std.debug.print(help, .{});

    // enter raw mode, & enter cooked mode again upon exit
    const orig_con_flags = try enableRawMode();
    defer setConMode(&orig_con_flags) catch {};

    var session_id = isession_id;

    // session loop
    while (true) {
        // read the line
        const lineo = try readLine(allocator, 4, "\x1b[35m=>> \x1b[0m", "\x1b[30;1m... \x1b[0m", "", &session_id);

        // skip cleared & empty lines
        const line = lineo orelse continue;
        defer line.deinit();
        if (line.items.len == 0) continue;

        // wait for a millisecond to avoid id/timestamp cobbling
        std.time.sleep(1000000);

        // pack the read line
        const timestamp = std.time.milliTimestamp();
        const item = try oats.item.pack(allocator, @bitCast(timestamp), .{
            .timestamp = timestamp,
            .session_id = session_id,
            .is_mobile = if (@import("options").is_mobile) {} else null,
        }, line.items);
        defer allocator.free(item);

        // read the stack ptr
        try file.seekTo(oats.stack.stack_ptr_loc);
        var stack_ptr = try file.reader().readInt(u64, .big);

        // push and also write the stack ptr
        try oats.stack.push(file, &stack_ptr, item);
        try file.seekTo(oats.stack.stack_ptr_loc);
        try file.writer().writeInt(u64, stack_ptr, .big);
    }
}
