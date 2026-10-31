const std = @import("std");
const provider = @import("provider.zig");
const commands = @import("commands.zig");
const editor = @import("editor.zig");
const transcript = @import("transcript.zig");
const surfaces = @import("surfaces.zig");
const integration = @import("integration.zig");
const display_width = @import("../core/shared/display_width.zig");
const decoder_mod = @import("../ui/input/terminal_action_decoder.zig");
const input_action = @import("../core/input/input_action.zig");
const text_scalar = @import("../core/input/text_scalar.zig");
const paste_framing = @import("../core/input/paste_framing.zig");

/// Minimal runnable cxn TUI over the shipped Controller.
///
/// Product input state and frame rendering. console_runtime.zig owns the
/// full-transcript terminal lifecycle and feeds byte streams into App.
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
    decoder: decoder_mod.Decoder = .{},
    scalar: text_scalar.State = .{},
    paste: paste_framing.State = .{},

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
        app.setStatus("Local demo only: no agent or router connection");
        return app;
    }

    pub fn deinit(self: *App) void {
        self.paste.deinit(self.alloc);
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
        self.owned_texts.append(self.alloc, owned) catch |err| {
            self.alloc.free(owned);
            return err;
        };
        _ = try self.ctl.tr.append(.user_message, owned);
        _ = try self.ctl.tr.append(.assistant_message, "queued locally — router send lands per PRD-002.");
        _ = self.ctl.tr.moveLast();
        try self.ctl.rebuildHitMap();
        self.ctl.ed.buf.clearRetainingCapacity();
        self.ctl.ed.cursor = 0;
        self.ctl.ed.anchor = null;
        self.ctl.mode = .normal;
        self.ctl.ed.mode = .normal;
        self.setStatus("Saved locally only; no request sent");
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
            self.setStatusFmt("available (not executed): {s}", .{name});
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
                .left => self.moveComposerLeft(),
                .right => self.moveComposerRight(),
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
                    if (self.cmd.items.len > 0) {
                        var start = self.cmd.items.len - 1;
                        while (start > 0 and self.cmd.items[start] & 0xc0 == 0x80) start -= 1;
                        self.cmd.items.len = start;
                    }
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

    fn moveComposerLeft(self: *App) void {
        if (self.ctl.ed.cursor == 0) return;
        self.ctl.ed.cursor -= 1;
        while (self.ctl.ed.cursor > 0 and self.ctl.ed.text()[self.ctl.ed.cursor] & 0xc0 == 0x80) self.ctl.ed.cursor -= 1;
    }

    fn moveComposerRight(self: *App) void {
        if (self.ctl.ed.cursor >= self.ctl.ed.text().len) return;
        self.ctl.ed.cursor += 1;
        while (self.ctl.ed.cursor < self.ctl.ed.text().len and self.ctl.ed.text()[self.ctl.ed.cursor] & 0xc0 == 0x80) self.ctl.ed.cursor += 1;
    }

    /// Consume every byte, retaining escape and UTF-8 state across reads.
    pub fn feedInput(self: *App, bytes: []const u8, now_ms: i64) !void {
        for (bytes) |byte| {
            if (!self.running) break;
            try self.feedByte(byte, now_ms);
        }
        try self.settlePaste();
    }

    fn feedByte(self: *App, byte: u8, now_ms: i64) !void {
        const ingress = self.decoder.feed(byte, .{ .now_ms = now_ms, .paste_active = self.paste.active(), .cancel_pending = false });
        try self.routeIngress(ingress);
        if (ingress.replay_byte_after_routing) |replay| try self.feedByte(replay, now_ms);
    }

    fn settlePaste(self: *App) !void {
        const settlement = self.paste.settleDeliveryEpoch();
        if (settlement == .none) return;
        defer self.paste.resetWithTrace(.session_reset);
        if (settlement == .reject or self.paste.overflow_bytes > 0 or !std.unicode.utf8ValidateSlice(self.paste.buffer.items)) {
            self.setStatus("Paste rejected: unsafe suffix, size, or UTF-8");
        } else if (self.ctl.mode == .insert) {
            try self.ctl.ed.insertText(self.paste.buffer.items);
        } else if (self.ctl.mode == .command) {
            try self.cmd.appendSlice(self.alloc, self.paste.buffer.items);
        }
    }

    pub fn flushInput(self: *App, now_ms: i64) !void {
        try self.routeIngress(self.decoder.flush(now_ms, 40, self.paste.active()));
    }

    fn routeIngress(self: *App, ingress: input_action.TerminalInputIngress) !void {
        const event = ingress.event orelse return;
        switch (event) {
            .raw => |raw| try self.handleByte(raw.byte),
            .paste_byte => |byte| {
                try self.paste.consumeByte(self.alloc, byte);
            },
            .action => |decoded| switch (decoded.action) {
                .escape => try self.handleKey(.esc),
                .cursor_up => try self.handleKey(.up),
                .cursor_down => try self.handleKey(.down),
                .cursor_left => try self.handleKey(.left),
                .cursor_right => try self.handleKey(.right),
                .remapped_byte => |byte| try self.handleByte(byte),
                .paste_start => {
                    self.scalar = .{};
                    self.paste.begin(.composer, 1024 * 1024);
                },
                else => {},
            },
        }
    }

    fn handleByte(self: *App, byte: u8) !void {
        if (byte < 32 or byte == 127) {
            self.scalar = .{};
            return self.handleKey(parseKeySlice(&.{byte}));
        }
        if (self.ctl.mode != .insert and self.ctl.mode != .command) return self.handleKey(parseKeySlice(&.{byte}));
        const next = text_scalar.advance(self.scalar, .composer, byte);
        self.scalar = next.next;
        if (next.step.scalar) |scalar| {
            if (self.ctl.mode == .insert) try self.ctl.ed.insertText(scalar.slice()) else try self.cmd.appendSlice(self.alloc, scalar.slice());
        }
    }

    /// Caller owns the returned UTF-8 frame. No row uses the last column,
    /// so terminal auto-wrap cannot add rows or scroll the viewport.
    pub fn render(self: *const App, alloc: std.mem.Allocator, width: usize, height: usize) ![]u8 {
        const w = width -| 1;
        const h = height;
        var out: std.Io.Writer.Allocating = .init(alloc);
        defer out.deinit();
        const wr = &out.writer;
        if (h < 6) {
            if (h > 0) try writeLine(wr, "cxn: enlarge terminal", w);
            return out.toOwnedSlice();
        }
        try writeLine(wr, "cxn — constellation console (local demo, not connected)", w);
        try writeLine(wr, "Transcript | j/k navigate, g/G first/last", w);
        const reserved: usize = 6;
        const budget: usize = h -| reserved;
        const blocks = self.ctl.tr.blocks.items;
        var shown: usize = 0;
        const focus = self.ctl.tr.focus orelse 0;
        var i = @min(self.ctl.tr.viewport_top, blocks.len);
        if (focus < i) i = focus;
        if (budget > 0 and focus >= i + budget) i = focus + 1 - budget;
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
            try writeLine(wr, s, w);
            shown += 1;
        }
        while (shown < budget) : (shown += 1) try writeLine(wr, "", w);
        try writeLine(wr, "Composer | i insert, Enter saves locally, Esc normal", w);
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
            try cline.writer.print(":{s}▌", .{visibleSuffix(self.cmd.items, w -| 2)});
            const s = try cline.toOwnedSlice();
            defer alloc.free(s);
            try writeLine(wr, s, w);
        } else {
            var cline: std.Io.Writer.Allocating = .init(alloc);
            defer cline.deinit();
            const text = self.ctl.ed.text();
            const cursor = @min(self.ctl.ed.cursor, text.len);
            // Keep the insertion point visible when the draft exceeds one row.
            const prefix_width = mode_name.len + 3;
            const available = w -| (prefix_width + 1);
            try cline.writer.print("[{s}] {s}▌{s}", .{ mode_name, visibleSuffix(text[0..cursor], available), text[cursor..] });
            const s = try cline.toOwnedSlice();
            defer alloc.free(s);
            try writeLine(wr, s, w);
        }
        var sline: std.Io.Writer.Allocating = .init(alloc);
        defer sline.deinit();
        try sline.writer.print("{s} | {s}", .{
            mode_name,
            self.status(),
        });
        const s = try sline.toOwnedSlice();
        defer alloc.free(s);
        try writeLine(wr, s, w);
        try writeLine(wr, "q quit | i insert | : command (availability check only)", w);
        return out.toOwnedSlice();
    }

    /// Full-transcript screen repaint; absolute rows avoid newline mapping,
    /// and erase-to-end clears remnants from shorter previous frames.
    pub fn renderScreen(self: *const App, alloc: std.mem.Allocator, width: usize, height: usize) ![]u8 {
        const frame = try self.render(alloc, width, height);
        defer alloc.free(frame);
        var out: std.Io.Writer.Allocating = .init(alloc);
        defer out.deinit();
        try out.writer.writeAll("\x1b[H");
        var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, frame, "\n"), '\n');
        var row: usize = 1;
        while (lines.next()) |line| : (row += 1) {
            if (row > height) break;
            try out.writer.print("\x1b[{d};1H\x1b[2K{s}", .{ row, line });
        }
        try out.writer.writeAll("\x1b[J");
        return out.toOwnedSlice();
    }
};

fn renderedUnit(text: []const u8, i: usize) display_width.DisplayUnit {
    if (text[i] < 32 or text[i] == 127) return .{ .byte_len = 1, .cell_width = 1 };
    return display_width.displayUnitAt(text, i);
}

/// Two linear passes, sharing exactly the emission rules in writeLine.
fn visibleSuffix(text: []const u8, width: usize) []const u8 {
    var cells: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        const unit = renderedUnit(text, i);
        cells += unit.cell_width;
        i += unit.byte_len;
    }
    i = 0;
    while (i < text.len and cells > width) {
        const unit = renderedUnit(text, i);
        cells -= unit.cell_width;
        i += unit.byte_len;
    }
    return text[i..];
}

fn writeLine(wr: *std.Io.Writer, text: []const u8, width: usize) !void {
    var cells: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        const unit = renderedUnit(text, i);
        const bytes = text[i..][0..unit.byte_len];
        // Never emit transcript/paste controls as terminal commands or rows.
        if (text[i] < 32 or text[i] == 127) {
            if (cells >= width) break;
            try wr.writeByte(' ');
            cells += 1;
        } else {
            if (unit.cell_width > width -| cells) break;
            try wr.writeAll(bytes);
            cells += unit.cell_width;
        }
        i += unit.byte_len;
    }
    try wr.writeByte('\n');
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
    try std.testing.expect(std.mem.indexOf(u8, app.status(), "not executed") != null);

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
    try std.testing.expect(std.mem.indexOf(u8, frame, "Composer") != null);
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

test "batched text and split arrow sequences preserve all input" {
    const alloc = std.testing.allocator;
    var app = try App.init(alloc, integration.resolveEndpoint(null, null), &.{"auto"});
    defer app.deinit();
    try app.feedInput("ihello world", 0);
    try std.testing.expectEqualStrings("hello world", app.ctl.ed.text());
    try app.feedInput("\x1b[", 10);
    try app.feedInput("D", 20);
    try app.feedInput("!", 30);
    try std.testing.expectEqualStrings("hello worl!d", app.ctl.ed.text());
    try app.feedInput("\r", 40);
    try std.testing.expectEqualStrings("hello worl!d", app.ctl.tr.blocks.items[2].text);
}

test "split utf8 input and backspace keep valid text" {
    const alloc = std.testing.allocator;
    var app = try App.init(alloc, integration.resolveEndpoint(null, null), &.{"auto"});
    defer app.deinit();
    try app.feedInput("icaf\xc3", 0);
    try app.feedInput("\xa9", 10);
    try std.testing.expectEqualStrings("café", app.ctl.ed.text());
    try app.feedInput("\x7f", 20);
    try std.testing.expectEqualStrings("caf", app.ctl.ed.text());
    try app.feedInput("\x1b", 30);
    try app.flushInput(100);
    try std.testing.expectEqual(integration.AppMode.normal, app.ctl.mode);
}

test "bracketed paste stays text and never submits embedded newlines" {
    const alloc = std.testing.allocator;
    var app = try App.init(alloc, integration.resolveEndpoint(null, null), &.{"auto"});
    defer app.deinit();
    try app.feedInput("i\x1b[200~hello\nworld café\x1b[20", 0);
    try app.feedInput("1~", 10);
    try std.testing.expectEqualStrings("hello\nworld café", app.ctl.ed.text());
    try std.testing.expectEqual(@as(usize, 2), app.ctl.tr.blocks.items.len);
    try std.testing.expect(!app.paste.active());
}

test "paste end candidate cannot turn a same-delivery suffix into commands" {
    const alloc = std.testing.allocator;
    var app = try App.init(alloc, integration.resolveEndpoint(null, null), &.{"auto"});
    defer app.deinit();
    try app.feedInput("i\x1b[200~hello\x1b[201~\rMORE\x1b[201~", 0);
    try std.testing.expectEqualStrings("", app.ctl.ed.text());
    try std.testing.expectEqual(@as(usize, 2), app.ctl.tr.blocks.items.len);
    try std.testing.expectEqual(integration.AppMode.insert, app.ctl.mode);
    try std.testing.expect(std.mem.startsWith(u8, app.status(), "Paste rejected"));
}

test "large drafts and multiline pastes retain visible tail and cursor" {
    const alloc = std.testing.allocator;
    var app = try App.init(alloc, integration.resolveEndpoint(null, null), &.{"auto"});
    defer app.deinit();
    try app.handleKey(.{ .char = 'i' });
    const large = try alloc.alloc(u8, 1024 * 1024);
    defer alloc.free(large);
    for ([_]u8{ 'x', '\n', '\t', '\r' }) |fill| {
        @memset(large, fill);
        try app.ctl.ed.setText(large);
        app.ctl.ed.cursor = large.len;
        try app.ctl.ed.insertText("TAIL_SENTINEL");
        const frame = try app.render(alloc, 60, 16);
        defer alloc.free(frame);
        try std.testing.expect(std.mem.indexOf(u8, frame, "TAIL_SENTINEL▌") != null);
    }
}
