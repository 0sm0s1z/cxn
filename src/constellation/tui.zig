const std = @import("std");
const provider = @import("provider.zig");
const commands = @import("commands.zig");
const editor = @import("editor.zig");
const transcript = @import("transcript.zig");
const surfaces = @import("surfaces.zig");
const integration = @import("integration.zig");

/// Minimal runnable cxn TUI over the shipped Controller.
///
/// Pure logic + frame rendering only: no syscalls here so `zig test` covers
/// the loop. The interactive raw-mode driver lives as a thin hook in
/// `src/main.zig` (`fx cxn`) and feeds parsed keys into `App`.
pub const Key = union(enum) {
    char: u8,
    ctrl: u8,
    enter,
    backspace,
    esc,
    up,
    down,
    left,
    right,
    unknown,
};

/// Parse a single raw read (1 byte or a short escape sequence) into a Key.
pub fn parseKeySlice(buf: []const u8) Key {
    if (buf.len == 0) return .unknown;
    if (buf.len >= 3 and buf[0] == 0x1b and buf[1] == '[') {
        return switch (buf[2]) {
            'A' => .up,
            'B' => .down,
            'C' => .right,
            'D' => .left,
            else => .unknown,
        };
    }
    if (buf.len > 1) {
        if (buf[0] == 0x1b) return .esc;
        return .unknown;
    }
    const c = buf[0];
    return switch (c) {
        0x03 => .{ .ctrl = 'C' },
        0x04 => .{ .ctrl = 'D' },
        '\r', '\n' => .enter,
        0x1b => .esc,
        0x7f, 0x08 => .backspace,
        else => if (c >= 32 and c < 127) .{ .char = c } else .unknown,
    };
}

pub const App = struct {
    alloc: std.mem.Allocator,
    ctl: integration.Controller,
    endpoint: integration.Endpoint,
    catalog: []const []const u8,
    running: bool = true,
    status_len: usize = 0,
    status_buf: [256]u8 = undefined,
    cmd: std.ArrayList(u8) = .empty,
    owned_texts: std.ArrayList([]u8) = .empty,

    pub fn init(
        alloc: std.mem.Allocator,
        endpoint: integration.Endpoint,
        catalog: []const []const u8,
    ) !App {
        var app = App{
            .alloc = alloc,
            .ctl = integration.Controller.init(alloc),
            .endpoint = endpoint,
            .catalog = catalog,
        };
        errdefer app.deinit();
        _ = try app.ctl.tr.append(.user_message, "Fix the auth handler.");
        _ = try app.ctl.tr.append(.assistant_message, "Done.");
        app.ctl.enterTranscript();
        _ = app.ctl.tr.moveNext();
        try app.ctl.rebuildHitMap();
        app.setStatus("ready — i insert · : cmd · j/k nav · q quit");
        return app;
    }

    pub fn deinit(self: *App) void {
        for (self.owned_texts.items) |s| self.alloc.free(s);
        self.owned_texts.deinit(self.alloc);
        self.cmd.deinit(self.alloc);
        self.ctl.deinit();
    }

    pub fn status(self: *const App) []const u8 {
        return self.status_buf[0..self.status_len];
    }

    pub fn setStatus(self: *App, msg: []const u8) void {
        const n = @min(msg.len, self.status_buf.len);
        @memcpy(self.status_buf[0..n], msg[0..n]);
        self.status_len = n;
    }

    pub fn setStatusFmt(self: *App, comptime fmt: []const u8, args: anytype) void {
        const n = std.fmt.bufPrint(self.status_buf[0..], fmt, args) catch {
            self.status_len = 0;
            return;
        };
        self.status_len = n.len;
    }

    fn submitComposer(self: *App) !void {
        const text = self.ctl.ed.text();
        if (text.len == 0) {
            self.setStatus("composer empty — type first, Enter submits, Esc cancels");
            return;
        }
        const owned = try self.alloc.dupe(u8, text);
        errdefer self.alloc.free(owned);
        try self.owned_texts.append(self.alloc, owned);
        _ = try self.ctl.tr.append(.user_message, owned);
        _ = try self.ctl.tr.append(.assistant_message, "queued locally — router send lands per PRD-002.");
        _ = self.ctl.tr.moveLast();
        try self.ctl.rebuildHitMap();
        self.ctl.ed.buf.clearRetainingCapacity();
        self.ctl.ed.cursor = 0;
        self.ctl.ed.anchor = null;
        self.ctl.mode = .normal;
        self.ctl.ed.mode = .normal;
        self.setStatus("submitted — j/k to review, i to compose again");
    }

    fn runCommandBuf(self: *App) void {
        const name = self.cmd.items;
        if (name.len == 0) {
            self.setStatus("empty command — try conversation.block.copy");
            self.ctl.mode = .normal;
            return;
        }
        // The command palette is modal: dispatch against the transcript
        // context the command operates on, not the transient .command mode.
        if (self.ctl.mode == .command) self.ctl.mode = .transcript;
        const res = self.ctl.runCommand(name);
        if (res.ok) {
            self.setStatusFmt("ok: {s}", .{name});
        } else {
            self.setStatusFmt("unavailable: {s}", .{res.unavailable_reason orelse "unknown"});
        }
        self.cmd.clearRetainingCapacity();
        self.ctl.mode = .transcript;
    }

    pub fn handleKey(self: *App, key: Key) !void {
        if (key == .ctrl) {
            self.running = false;
            return;
        }
        switch (self.ctl.mode) {
            .insert => switch (key) {
                .esc => {
                    self.ctl.mode = .normal;
                    self.ctl.ed.mode = .normal;
                    self.setStatus("normal — i insert · : cmd · j/k nav · q quit");
                },
                .enter => try self.submitComposer(),
                .backspace => try self.ctl.ed.backspace(),
                .char => |c| try self.ctl.ed.insertText(&.{c}),
                else => {},
            },
            .command => switch (key) {
                .esc => {
                    self.cmd.clearRetainingCapacity();
                    self.ctl.mode = .normal;
                    self.setStatus("normal — command cancelled");
                },
                .enter => self.runCommandBuf(),
                .backspace => {
                    if (self.cmd.items.len > 0) _ = self.cmd.pop();
                },
                .char => |c| try self.cmd.append(self.alloc, c),
                else => {},
            },
            else => switch (key) {
                .esc => {
                    self.ctl.mode = .normal;
                    self.setStatus("normal — i insert · : cmd · j/k nav · q quit");
                },
                .enter => {
                    if (self.ctl.ed.text().len > 0) try self.submitComposer();
                },
                .char => |c| switch (c) {
                    'q' => {
                        self.running = false;
                        return;
                    },
                    'i' => {
                        self.ctl.mode = .insert;
                        self.ctl.ed.mode = .insert;
                        self.setStatus("insert — type, Enter submits, Esc back");
                    },
                    ':' => {
                        self.ctl.mode = .command;
                        self.cmd.clearRetainingCapacity();
                        self.setStatus("command — type id, Enter runs, Esc cancels");
                    },
                    'j' => {
                        self.ctl.mode = .transcript;
                        if (!self.ctl.tr.moveNext()) self.setStatus("bottom of transcript") else self.setStatus("transcript — j/k nav · Esc back");
                    },
                    'k' => {
                        self.ctl.mode = .transcript;
                        if (!self.ctl.tr.movePrev()) self.setStatus("top of transcript") else self.setStatus("transcript — j/k nav · Esc back");
                    },
                    'g' => {
                        self.ctl.mode = .transcript;
                        _ = self.ctl.tr.moveFirst();
                    },
                    'G' => {
                        self.ctl.mode = .transcript;
                        _ = self.ctl.tr.moveLast();
                    },
                    else => {},
                },
                .up => {
                    self.ctl.mode = .transcript;
                    _ = self.ctl.tr.movePrev();
                },
                .down => {
                    self.ctl.mode = .transcript;
                    _ = self.ctl.tr.moveNext();
                },
                else => {},
            },
        }
    }

    pub fn render(self: *const App, alloc: std.mem.Allocator, width: usize, height: usize) ![]u8 {
        const w = @max(width, 20);
        const h = @max(height, 10);
        var out: std.Io.Writer.Allocating = .init(alloc);
        defer out.deinit();
        const wr = &out.writer;
        try wr.print("cxn — constellation console  router: {s} valid={} has_key={} catalog:", .{
            self.endpoint.base_url,
            self.endpoint.valid,
            self.endpoint.has_api_key,
        });
        for (self.catalog) |id| try wr.print(" {s}", .{id});
        try wr.print("\n", .{});
        try wr.writeAll(truncate("-- transcript (j/k navigate, e branches on edit per PRD-005) --\n", w));
        const reserved: usize = 6;
        const budget: usize = h -| reserved;
        const blocks = self.ctl.tr.blocks.items;
        var shown: usize = 0;
        var i: usize = 0;
        while (i < blocks.len and shown < budget) : (i += 1) {
            const b = blocks[i];
            const focused = if (self.ctl.tr.focus) |f| f == i else false;
            const marker: []const u8 = if (focused) "▶ " else "  ";
            const kind: []const u8 = switch (b.kind) {
                .user_message => "you",
                .assistant_message => "asst",
                else => @tagName(b.kind),
            };
            var line: std.Io.Writer.Allocating = .init(alloc);
            defer line.deinit();
            try line.writer.print("{s}[{s}] {s}", .{ marker, kind, b.text });
            const s = try line.toOwnedSlice();
            defer alloc.free(s);
            try wr.writeAll(truncate(s, w));
            try wr.print("\n", .{});
            shown += 1;
        }
        try wr.writeAll(truncate("-- composer --\n", w));
        const mode_name: []const u8 = switch (self.ctl.mode) {
            .insert => "INSERT",
            .normal => "NORMAL",
            .visual => "VISUAL",
            .transcript => "TRANSCRIPT",
            .command => "COMMAND",
            .surface => "SURFACE",
        };
        if (self.ctl.mode == .command) {
            var cline: std.Io.Writer.Allocating = .init(alloc);
            defer cline.deinit();
            try cline.writer.print(":{s}▌", .{self.cmd.items});
            const s = try cline.toOwnedSlice();
            defer alloc.free(s);
            try wr.writeAll(truncate(s, w));
        } else {
            var cline: std.Io.Writer.Allocating = .init(alloc);
            defer cline.deinit();
            try cline.writer.print("[{s}] {s}▌", .{ mode_name, self.ctl.ed.text() });
            const s = try cline.toOwnedSlice();
            defer alloc.free(s);
            try wr.writeAll(truncate(s, w));
        }
        try wr.print("\n", .{});
        var sline: std.Io.Writer.Allocating = .init(alloc);
        defer sline.deinit();
        try sline.writer.print("mode:{s} | {s} | q quit · i insert · : cmd", .{
            mode_name,
            self.status(),
        });
        const s = try sline.toOwnedSlice();
        defer alloc.free(s);
        try wr.writeAll(truncate(s, w));
        try wr.print("\n", .{});
        return out.toOwnedSlice();
    }
};

fn truncate(s: []const u8, width: usize) []const u8 {
    if (s.len <= width) return s;
    return s[0..width];
}

test "keys parse single bytes and arrows" {
    try std.testing.expect(parseKeySlice(&.{'j'}) == .char);
    try std.testing.expectEqual(parseKeySlice(&.{'j'}).char, 'j');
    try std.testing.expect(parseKeySlice(&.{0x1b}) == .esc);
    try std.testing.expect(parseKeySlice(&.{'\r'}) == .enter);
    try std.testing.expect(parseKeySlice(&.{0x7f}) == .backspace);
    try std.testing.expect(parseKeySlice(&.{ 0x1b, '[', 'A' }) == .up);
    try std.testing.expect(parseKeySlice(&.{ 0x1b, '[', 'B' }) == .down);
    try std.testing.expect(parseKeySlice(&.{0x03}).ctrl == 'C');
}

test "app navigates, composes, submits, and runs commands" {
    const alloc = std.testing.allocator;
    const endpoint = integration.resolveEndpoint("http://router.local:8080", null);
    const catalog = try provider.buildCatalog(alloc, &.{"grok-4"});
    defer alloc.free(catalog);
    var app = try App.init(alloc, endpoint, catalog);
    defer app.deinit();

    try app.handleKey(.{ .char = 'j' });
    try std.testing.expect(app.ctl.mode == .transcript);
    try app.handleKey(.{ .char = 'k' });
    try std.testing.expect(app.ctl.tr.focus.? == 0);

    try app.handleKey(.{ .char = 'i' });
    try std.testing.expect(app.ctl.mode == .insert);
    for ("hello") |c| try app.handleKey(.{ .char = c });
    try std.testing.expectEqualStrings("hello", app.ctl.ed.text());
    try app.handleKey(.enter);
    try std.testing.expect(app.ctl.tr.blocks.items.len == 4);
    try std.testing.expect(app.ctl.mode == .normal);

    try app.handleKey(.{ .char = ':' });
    for ("conversation.block.copy") |c| try app.handleKey(.{ .char = c });
    try app.handleKey(.enter);
    try std.testing.expect(std.mem.indexOf(u8, app.status(), "ok:") != null);

    try app.handleKey(.{ .char = 'q' });
    try std.testing.expect(!app.running);
}

test "frame renders header transcript composer status" {
    const alloc = std.testing.allocator;
    const endpoint = integration.resolveEndpoint("http://router.local:8080", null);
    const catalog = try provider.buildCatalog(alloc, &.{"grok-4"});
    defer alloc.free(catalog);
    var app = try App.init(alloc, endpoint, catalog);
    defer app.deinit();
    const frame = try app.render(alloc, 80, 24);
    defer alloc.free(frame);
    try std.testing.expect(std.mem.indexOf(u8, frame, "cxn — constellation console") != null);
    try std.testing.expect(std.mem.indexOf(u8, frame, "Fix the auth handler.") != null);
    try std.testing.expect(std.mem.indexOf(u8, frame, "composer") != null);
    try std.testing.expect(std.mem.indexOf(u8, frame, "q quit") != null);
}

test "ctrl-c quits from any mode" {
    const alloc = std.testing.allocator;
    const endpoint = integration.resolveEndpoint("http://router.local:8080", null);
    const catalog = try provider.buildCatalog(alloc, &.{});
    defer alloc.free(catalog);
    var app = try App.init(alloc, endpoint, catalog);
    defer app.deinit();
    try app.handleKey(.{ .char = 'i' });
    try app.handleKey(.{ .ctrl = 'C' });
    try std.testing.expect(!app.running);
}
