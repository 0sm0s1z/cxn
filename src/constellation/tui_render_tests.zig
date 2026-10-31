const std = @import("std");
const tui = @import("tui.zig");
const integration = @import("integration.zig");
const display_width = @import("../core/shared/display_width.zig");
const terminal = @import("../core/terminal/engine.zig");

test "console frame stays inside narrow and tiny terminal bounds" {
    const alloc = std.testing.allocator;
    var app = try tui.App.init(alloc, integration.resolveEndpoint("http://router.local:8080", null), &.{"auto"});
    defer app.deinit();
    for ([_][2]usize{ .{ 60, 16 }, .{ 20, 10 }, .{ 8, 3 }, .{ 1, 1 } }) |size| {
        const frame = try app.render(alloc, size[0], size[1]);
        defer alloc.free(frame);
        var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, frame, "\n"), '\n');
        var count: usize = 0;
        while (lines.next()) |line| {
            count += 1;
            try std.testing.expect(std.unicode.utf8ValidateSlice(line));
            try std.testing.expect(display_width.visibleWidth(line) < size[0]);
        }
        try std.testing.expect(count <= size[1]);
    }
}

test "console repaint clears shorter rows without scrolling the grid" {
    const alloc = std.testing.allocator;
    var app = try tui.App.init(alloc, integration.resolveEndpoint(null, null), &.{"auto"});
    defer app.deinit();
    var grid = try terminal.Grid.init(alloc, 60, 16);
    defer grid.deinit();
    app.setStatus("a long status that must disappear after a shorter repaint");
    const first = try app.renderScreen(alloc, 60, 16);
    defer alloc.free(first);
    try grid.feed(first);
    app.setStatus("short");
    const second = try app.renderScreen(alloc, 60, 16);
    defer alloc.free(second);
    var stats: terminal.FeedStats = .{};
    try grid.feedWithStats(second, &stats);
    try std.testing.expect(!stats.scrolled);
    var snapshot: std.ArrayList(u8) = .empty;
    defer snapshot.deinit(alloc);
    try grid.snapshot(&snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot.items, "must disappear") == null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot.items, "short") != null);
}

test "focused newest block remains visible past transcript viewport" {
    const alloc = std.testing.allocator;
    var app = try tui.App.init(alloc, integration.resolveEndpoint(null, null), &.{"auto"});
    defer app.deinit();
    for (0..30) |_| _ = try app.ctl.tr.append(.user_message, "old message");
    _ = try app.ctl.tr.append(.user_message, "newest visible message");
    _ = app.ctl.tr.moveLast();
    const frame = try app.render(alloc, 60, 16);
    defer alloc.free(frame);
    try std.testing.expect(std.mem.indexOf(u8, frame, "▶ [you] newest visible message") != null);
}

test "unicode clipping and pasted controls cannot corrupt screen rows" {
    const alloc = std.testing.allocator;
    var app = try tui.App.init(alloc, integration.resolveEndpoint(null, null), &.{"auto"});
    defer app.deinit();
    _ = try app.ctl.tr.append(.user_message, "界界界\n\x1b[2Jcafé");
    _ = app.ctl.tr.moveLast();
    for (1..40) |width| {
        const frame = try app.render(alloc, width, 10);
        defer alloc.free(frame);
        try std.testing.expect(std.unicode.utf8ValidateSlice(frame));
        try std.testing.expect(std.mem.indexOfScalar(u8, frame, 0x1b) == null);
        var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, frame, "\n"), '\n');
        while (lines.next()) |line| try std.testing.expect(display_width.visibleWidth(line) < width);
    }
}
