//! Standalone full-transcript demo driver. Terminal ownership and raw input
//! reuse the host lifecycle rather than introducing a second terminal owner.
const std = @import("std");
const tui = @import("tui.zig");
const shell_runtime = @import("../ui/shell_runtime.zig");
const transcript_runtime = @import("../ui/transcript/runtime.zig");
const lifecycle = @import("../core/app/app_lifecycle.zig");
const io_mod = @import("../core/shared/io.zig");
const types = @import("../core/shared/types.zig");

pub fn run(alloc: std.mem.Allocator, app: *tui.App) !void {
    var terminal: shell_runtime.TerminalState = .{};
    try terminal.ensureInteractive();
    try terminal.captureOriginalTermios();
    try terminal.enableRawMode();
    defer terminal.disableRawMode();
    var shell: transcript_runtime.TranscriptRuntime = .{ .layout = try terminal.queryLayout(0) };
    defer shell.deinit(alloc);
    var metrics: types.Metrics = .{};
    try lifecycle.openFullTranscript(alloc, &terminal, &shell, &metrics);
    defer lifecycle.closeFullTranscript(alloc, &terminal, &shell, &metrics) catch {};
    var stdout = std.Io.File.stdout();
    try stdout.writeStreamingAll(io_mod.getIo(), "\x1b[?25l\x1b[?2004h");
    defer stdout.writeStreamingAll(io_mod.getIo(), "\x1b[?2004l\x1b[?25h") catch {};

    var cols: u16 = 0;
    var rows: u16 = 0;
    var dirty = true;
    var input: [4096]u8 = undefined;
    while (app.running) {
        const layout = try terminal.queryLayout(0);
        if (layout.cols != cols or layout.rows != rows) {
            cols = layout.cols;
            rows = layout.rows;
            app.ctl.onResize();
            dirty = true;
        }
        if (dirty) {
            const frame = try app.renderScreen(alloc, cols, rows);
            defer alloc.free(frame);
            try stdout.writeStreamingAll(io_mod.getIo(), frame);
            dirty = false;
        }
        const poll = try terminal.pollInput(40);
        if (poll.readable) {
            const n = try terminal.read(&input);
            if (n == 0) break;
            try app.feedInput(input[0..n], io_mod.milliTimestamp());
            dirty = true;
        } else if (app.decoder.hasPending()) {
            try app.flushInput(io_mod.milliTimestamp());
            dirty = true;
        }
        if (poll.closed()) break;
    }
}
