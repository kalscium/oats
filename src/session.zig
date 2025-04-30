//! Deals with stdin for an interactive writing session
//! 
//! **note:** this is part of main as it's strictly only part of the CLI, and
//!           doesn't fit in the context of a static library.

const std = @import("std");
const oats = @import("oats");
const termios = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
});
const ioctl = @cImport(@cInclude("sys/ioctl.h"));
const main = @import("main.zig");

const help = "\x1b[35m<<< \x1b[0;1mOATS SESSION \x1b[35m>>>\x1b[0m\n\x1b[35m*\x1b[0m welcome to a space for random thughts or notes!\n\x1b[35m*\x1b[0m some quick controls:\n  \x1b[35m*\x1b[0m CTRL+D or \x1b[36m:\x1b[0mexit to exit the thought session\n  \x1b[35m*\x1b[0m CTRL+C to cancel the line\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mhelp` to print this help message\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mtail <n>` to print the last <n> stack items\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mpop <n>` to pop the last <n> stack items\n  \x1b[35m*\x1b[0m `\x1b[36m:\x1b[0mclear` to clear the screen\n";

/// Enables the terminal raw mode and also returns the original mode so you can switch back
pub fn enableRawMode() termios.struct_termios {
    // get original flags
    var orig: termios.struct_termios = undefined;
    _ = termios.tcgetattr(termios.STDIN_FILENO, &orig);

    // our custom 'raw' flags
    var raw = orig;
    // disable echo & line buffering
    raw.c_lflag &= @bitCast(~(termios.ECHO | termios.ICANON));
    // disable Ctrl-C & Ctrl-Z signals
    raw.c_lflag &= @bitCast(~termios.ISIG);
    // disable Ctrl-S & Ctrl-Q
    raw.c_lflag &= @bitCast(~termios.IXON);
    // disable Ctrl-V & fix Ctrl-M
    raw.c_lflag &= @bitCast(~(termios.IEXTEN | termios.ICRNL));
    // misc
    raw.c_lflag &= @bitCast(~(termios.BRKINT | termios.INPCK | termios.ISTRIP));
    raw.c_cflag |= @bitCast(termios.CS8);

    // set the attrs and return original
    _ = termios.tcsetattr(termios.STDIN_FILENO, termios.TCSAFLUSH, &raw);
    return orig;
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
    const offset_ln = (cursor-1) / coloumns;
    const total_ln = line.len / coloumns;

    try stdout.writeAll("\x1B[?25l\x1B[0K");

    // write the first line the cursor is on
    const first_line = line[cursor-1..@min(line.len, (offset_ln + 1) * coloumns)];
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
    const moved: isize = @as(isize, @intCast(line.len % coloumns)) - @as(isize, @intCast((cursor - 1) % coloumns));
    if (moved > 0)
        try std.fmt.format(stdout, "\x1B[{}D", .{moved})
    else if (moved < 0)
        try std.fmt.format(stdout, "\x1B[{}C", .{-moved});

    // unhide it
    try stdout.writeAll("\x1B[?25h");
}

/// Reads a line from stdin with the specified prompt in raw mode and returns it, owned by caller
pub fn readLine(allocator: std.mem.Allocator, comptime prompt_len: usize, prompt: []const u8, comptime wrap_prompt: []const u8) !std.ArrayList(u8) {
    // can you imagine if I added line scrolling? that would be painful.

    var line = std.ArrayList(u8).init(allocator);

    var cursor: usize = line.items.len; // index into the line
    var escape = false; // if parsing escape code
    var escape_arrow = false; // if parsing arrow escape code
    var stdout = std.io.getStdOut().writer();

    try stdout.writeAll(prompt);

    // get window size
    var winsize: ioctl.winsize = undefined;
    _ = ioctl.ioctl(termios.STDOUT_FILENO, ioctl.TIOCGWINSZ, &winsize);

    const coloumns = @as(usize, winsize.ws_col) - prompt_len;

    // keep track of free lines to write to
    var free_lines: usize = 0;

    // if a command was run
    var command_run = false;

    // if the line is to be cleared
    var clear_line = false;

    // keep reading until EOF or new-line
    while (std.io.getStdIn().reader().readByte()) |char| {
        // check for CTRL+D (exit)
        if (char == 4) return error.UserInterrupt;

        // check for CTRL+C (clear)
        if (char == 3) {
            clear_line = true;
            break;
        }

        // check for escape codes
        if (char == 27) {
            escape = true;
            continue;
        }

        // check for arrow escape codes
        if (escape and char == 91) {
            escape_arrow = true;
            continue;
        }

        // check for `:` (commands)
        if (char == ':' and cursor == 0) {
            command_run = true;
            line.deinit();
            line = @TypeOf(line).init(allocator);
            try readCommand(allocator);
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
                try std.fmt.format(stdout, "\x1B[{}G", .{winsize.ws_col}); // go to end of line
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
                try std.fmt.format(stdout, "\x1B[1A\x1B[{}G", .{winsize.ws_col}); // go to end of line
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
        if (char == '\n') break;

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

    // if the line is cleared, jump to the first line
    if (clear_line) {
        if (lines > 0) { // only jump if the cursor is not already on the first line
            const cleanup_jump = (cursor - 1) / coloumns;
            try std.fmt.format(stdout, "\x1B[?25l\x1B[{}A", .{cleanup_jump}); // hide the line and jump

            // wipe all the lines after it and go back to the first line
            try stdout.writeBytesNTimes("\x1B[1B\x1B[2K", lines);
            try std.fmt.format(stdout, "\x1B[{}A", .{lines});
        }

        // clear the line and go to the start of it before unhiding the cursor
        try stdout.writeAll("\x1B[?25h\x1B[2K\x1B[0G");

        // free the line
        line.deinit();
        line = @TypeOf(line).init(allocator);
    } else // ugly, but comment needed: this is when the line isn't cleared and needs to be jumped after it
    if (!command_run) { // only jump if the line spans more than one console line
        if (lines > 0) {
            const cleanup_jump = lines - (cursor - 1) / coloumns;
            if (cleanup_jump != 0) // only jump if the cursor isn't already on the last line
                try std.fmt.format(stdout, "\x1B[{}B", .{cleanup_jump});
        }
        try std.fmt.format(stdout, "\x1B[{}G\n", .{prompt_len});
    }

    return line;
}

/// Reads a line as a command from stdin with the specified prompt in raw mode and executes it
pub fn readCommand(allocator: std.mem.Allocator) !void {
    const prompt_len = 6;
    const prompt = "\x1b[2K\x1b[0G    \x1b[36;1m: \x1b[0m";
    const wrap_prompt = "\x1b[30;1m  ... \x1b[0m";

    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();

    var cursor: usize = line.items.len; // index into the line
    var stdout = std.io.getStdOut().writer();

    try stdout.writeAll(prompt);

    // get window size
    var winsize: ioctl.winsize = undefined;
    _ = ioctl.ioctl(termios.STDOUT_FILENO, ioctl.TIOCGWINSZ, &winsize);

    const coloumns = @as(usize, winsize.ws_col) - prompt_len;

    // keep track of free lines to write to
    var free_lines: usize = 0;

    // keep reading until EOF or new-line
    while (std.io.getStdIn().reader().readByte()) |char| {
        // check for CTRL+D (exit)
        if (char == 4) return error.UserInterrupt;

        // check for CTRL+C (clear)
        if (char == 3) {
            line.deinit();
            line = @TypeOf(line).init(allocator);
            break;
        }

        // check for ESC
        if (char == 27) {
            line.deinit();
            line = @TypeOf(line).init(allocator);
            break;
        }

        // check for backspace
        if (char == 127) {
            // if cursor is zero, then break
            if (cursor == 0) break;

            // print changes to terminal
             
            // if you've already reached the start of the console line, then go
            // to the above one (line wrapping)
            if (cursor % coloumns == 0) {
                try std.fmt.format(stdout, "\x1B[1A\x1B[{}G", .{winsize.ws_col}); // go to end of line
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
        if (char == '\n') break;

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
    try stdout.writeAll("\x1B[0G\x1B[2K"); // wipe line and go to start of line

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

    // check for the 'tail' command
    if (std.mem.eql(u8, split_first, "tail")) {
        const to_pop = if (split.next()) |raw_to_pop|
            try std.fmt.parseInt(usize, raw_to_pop, 10)
        else 1;
        try main.tail(allocator, to_pop);
        return;
    }

    // otherwise the command is invalid
    std.debug.print("error: unknown command '{s}'\n", .{split_first});
    return;
}

/// Starts the interactive oats session
pub fn session(allocator: std.mem.Allocator, file: std.fs.File) !void {
    std.debug.print(help, .{});

    // enter raw mode, & enter cooked mode again upon exit
    const orig_termios = enableRawMode();
    defer _ = termios.tcsetattr(termios.STDIN_FILENO, termios.TCSAFLUSH, &orig_termios);

    // session loop
    while (true) {
        // read the line
        const line = try readLine(allocator, 4, "\x1b[35m=>> \x1b[0m", "\x1b[30;1m... \x1b[0m");
        defer line.deinit();

        // skip empty lines
        if (line.items.len == 0) continue;

        // pack the read line
        const timestamp = std.time.milliTimestamp();
        const item = try oats.item.pack(allocator, @bitCast(timestamp), .{ .timestamp = timestamp }, line.items);
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
