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

    try stdout.writeAll("\x1B[s\x1B[?25l\x1B[0K");

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
    free_lines.* += total_ln - offset_ln;

    // move it back to it's starting position and then unhide it
    try stdout.writeAll("\x1B[u\x1B[?25h");
}

/// Reads a line from stdin with the specified prompt in raw mode and returns it, owned by caller
pub fn readLine(allocator: std.mem.Allocator, comptime prompt_len: usize, prompt: []const u8, comptime wrap_prompt: []const u8) !std.ArrayList(u8) {
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

    // keep reading until EOF or new-line
    while (std.io.getStdIn().reader().readByte()) |char| {
        // check for CTRL+D (exit)
        if (char == 4) return error.UserInterrupt;

        // check for CTRL+C (clear)
        if (char == 3) {
            line.deinit();
            return @TypeOf(line).init(allocator);
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

    return line;
}

/// Starts the interactive oats session
pub fn session(allocator: std.mem.Allocator) !void {
    // open the database
    const path = try oats.getHome(allocator);
    defer allocator.free(path);
    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
    defer file.close();

    std.debug.print(
        \\<<< OATS SESSION >>>
        \\* welcome to a space for random thughts or notes!
        \\* some quick controls:
        \\  * CTRL+D, CTRL+C or :exit to exit the thought session
        \\  * :pop to pop the last stack item
        \\  * :clear to clear the screen
        \\
        , .{}
    );

    // enter raw mode, & enter cooked mode again upon exit
    const orig_termios = enableRawMode();
    defer _ = termios.tcsetattr(termios.STDIN_FILENO, termios.TCSAFLUSH, &orig_termios);

    while (true) {
        // read the line
        const line = try readLine(allocator, 4, "\x1b[35m=>> \x1b[0m", "\x1b[30;1m... \x1b[0m");
        defer line.deinit();

        // print the results
        std.debug.print("\nresult: {s}\n", .{line.items});
    }
}
