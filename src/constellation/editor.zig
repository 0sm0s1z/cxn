const std = @import("std");

pub const EditorMode = enum { insert, normal, visual };
const undo_cap = 64;

fn isWordChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn lineStart(buf: []const u8, off: usize) usize {
    var i = off;
    while (i > 0 and buf[i - 1] != '\n') i -= 1;
    return i;
}

fn lineEnd(buf: []const u8, off: usize) usize {
    var i = off;
    while (i < buf.len and buf[i] != '\n') i += 1;
    return i;
}

fn firstNonBlank(buf: []const u8, off: usize) usize {
    const ls = lineStart(buf, off);
    const le = lineEnd(buf, off);
    var i = ls;
    while (i < le and (buf[i] == ' ' or buf[i] == '\t')) i += 1;
    return i;
}

fn moveDown(buf: []const u8, off: usize) usize {
    const col = off - lineStart(buf, off);
    const le = lineEnd(buf, off);
    if (le >= buf.len) return off;
    const nl = le + 1;
    const nlen = lineEnd(buf, nl) - nl;
    return nl + @min(col, nlen);
}

fn moveUp(buf: []const u8, off: usize) usize {
    const col = off - lineStart(buf, off);
    const ls = lineStart(buf, off);
    if (ls == 0) return off;
    const pls = lineStart(buf, ls - 1);
    const plen = (ls - 1) - pls;
    return pls + @min(col, plen);
}

fn wordForward(buf: []const u8, off: usize) usize {
    const n = buf.len;
    var i = off;
    if (i >= n) return n;
    if (isWordChar(buf[i])) {
        while (i < n and isWordChar(buf[i])) i += 1;
    }
    while (i < n and !isWordChar(buf[i])) i += 1;
    return i;
}

fn wordBackward(buf: []const u8, off: usize) usize {
    const n = buf.len;
    if (n == 0 or off == 0) return 0;
    var i: usize = if (off > n) n else off;
    i -= 1;
    while (i > 0 and !isWordChar(buf[i])) i -= 1;
    if (!isWordChar(buf[i])) return if (off > n) n else off;
    while (i > 0 and isWordChar(buf[i - 1])) i -= 1;
    return i;
}

fn wordEnd(buf: []const u8, off: usize) usize {
    const n = buf.len;
    if (n == 0) return 0;
    const i = if (off >= n) n - 1 else off;
    if (isWordChar(buf[i])) {
        var j = i;
        while (j + 1 < n and isWordChar(buf[j + 1])) j += 1;
        if (j != i) return j;
    }
    var k = i + 1;
    while (k < n and !isWordChar(buf[k])) k += 1;
    if (k >= n) return off;
    while (k + 1 < n and isWordChar(buf[k + 1])) k += 1;
    return k;
}

fn findOnLine(buf: []const u8, off: usize, target: u8, forward: bool, till: bool) ?usize {
    if (forward) {
        const le = lineEnd(buf, off);
        var i = off + 1;
        while (i < le) : (i += 1) {
            if (buf[i] == target) return if (till and i > off + 1) i - 1 else if (till) off else i;
        }
        return null;
    } else {
        const ls = lineStart(buf, off);
        var i = off;
        while (i > ls) {
            i -= 1;
            if (buf[i] == target) return if (till and i + 1 < off) i + 1 else if (till) off else i;
        }
        return null;
    }
}

fn matchBracket(buf: []const u8, off: usize) ?usize {
    if (off >= buf.len) return null;
    const opens = "(){}[]";
    const closes = ")}{][";
    const c = buf[off];
    const oi = std.mem.indexOfScalar(u8, opens, c);
    if (oi) |_| {
        const close = closes[oi.?];
        var depth: usize = 1;
        var i = off + 1;
        while (i < buf.len) : (i += 1) {
            if (buf[i] == c) depth += 1 else if (buf[i] == close) {
                depth -= 1;
                if (depth == 0) return i;
            }
        }
        return null;
    }
    const ci = std.mem.indexOfScalar(u8, closes, c);
    if (ci) |_| {
        const open = opens[ci.?];
        var depth: usize = 1;
        var i = off;
        while (i > 0) {
            i -= 1;
            if (buf[i] == c) depth += 1 else if (buf[i] == open) {
                depth -= 1;
                if (depth == 0) return i;
            }
        }
        return null;
    }
    return null;
}

pub const Range = struct { start: usize, end: usize };

fn innerWord(buf: []const u8, off: usize) ?Range {
    if (off >= buf.len or !isWordChar(buf[off])) return null;
    var s = off;
    while (s > 0 and isWordChar(buf[s - 1])) s -= 1;
    var e = off;
    while (e < buf.len and isWordChar(buf[e])) e += 1;
    return .{ .start = s, .end = e };
}

fn aroundWord(buf: []const u8, off: usize) ?Range {
    const inner = innerWord(buf, off) orelse return null;
    var e = inner.end;
    if (e < buf.len and (buf[e] == ' ' or buf[e] == '\t')) {
        while (e < buf.len and (buf[e] == ' ' or buf[e] == '\t')) e += 1;
        return .{ .start = inner.start, .end = e };
    }
    var s = inner.start;
    while (s > 0 and (buf[s - 1] == ' ' or buf[s - 1] == '\t')) s -= 1;
    return .{ .start = s, .end = inner.end };
}

fn delimPair(kind: u8) ?struct { open: u8, close: u8 } {
    return switch (kind) {
        '(', ')' => .{ .open = '(', .close = ')' },
        '{', '}' => .{ .open = '{', .close = '}' },
        '[', ']' => .{ .open = '[', .close = ']' },
        '"', '\'', '`' => .{ .open = kind, .close = kind },
        else => null,
    };
}

fn insideDelim(buf: []const u8, off: usize, kind: u8) ?Range {
    const pair = delimPair(kind) orelse return null;
    if (pair.open == pair.close) {
        var s: ?usize = null;
        var i = off;
        while (i > 0) {
            i -= 1;
            if (buf[i] == pair.open) {
                s = i;
                break;
            }
            if (buf[i] == '\n' and off - i > 4096) break;
        }
        const st = s orelse return null;
        var e: ?usize = null;
        var j = @max(off, st + 1);
        if (j < st + 1) j = st + 1;
        while (j < buf.len) : (j += 1) {
            if (buf[j] == pair.close) {
                e = j;
                break;
            }
        }
        const en = e orelse return null;
        if (st + 1 > en) return null;
        return .{ .start = st + 1, .end = en };
    }
    var depth: usize = 0;
    var s: ?usize = null;
    var i = off + 1;
    while (i > 0) {
        i -= 1;
        if (buf[i] == pair.close) {
            if (i < off) depth += 1;
        } else if (buf[i] == pair.open) {
            if (depth == 0) {
                s = i;
                break;
            }
            depth -= 1;
        }
        if (i == 0) break;
    }
    const st = s orelse return null;
    depth = 1;
    var j = st + 1;
    while (j < buf.len) : (j += 1) {
        if (buf[j] == pair.open) depth += 1 else if (buf[j] == pair.close) {
            depth -= 1;
            if (depth == 0) return .{ .start = st + 1, .end = j };
        }
    }
    return null;
}

fn aroundDelim(buf: []const u8, off: usize, kind: u8) ?Range {
    const inner = insideDelim(buf, off, kind) orelse return null;
    return .{ .start = inner.start - 1, .end = inner.end + 1 };
}

fn isBlankLine(buf: []const u8, line_start: usize) bool {
    const le = lineEnd(buf, line_start);
    for (buf[line_start..le]) |c| {
        if (c != ' ' and c != '\t') return false;
    }
    return true;
}

fn innerPara(buf: []const u8, off: usize) Range {
    var top = lineStart(buf, off);
    while (top > 0 and !isBlankLine(buf, lineStart(buf, top - 1))) {
        top = lineStart(buf, top - 1);
    }
    var bot = lineEnd(buf, off);
    while (bot < buf.len and !isBlankLine(buf, bot + 1)) {
        bot = lineEnd(buf, bot + 1);
    }
    return .{ .start = top, .end = bot };
}

fn aroundPara(buf: []const u8, off: usize) Range {
    const inner = innerPara(buf, off);
    var end = inner.end;
    if (end < buf.len and buf[end] == '\n') end += 1;
    if (end < buf.len and isBlankLine(buf, lineStart(buf, end))) {
        end = lineEnd(buf, end);
        if (end < buf.len and buf[end] == '\n') end += 1;
    }
    return .{ .start = inner.start, .end = end };
}

pub const Editor = struct {
    alloc: std.mem.Allocator,
    buf: std.ArrayList(u8) = .empty,
    cursor: usize = 0,
    mode: EditorMode = .normal,
    anchor: ?usize = null,
    undo: std.ArrayList([]u8) = .empty,
    redo: std.ArrayList([]u8) = .empty,
    yank: std.ArrayList(u8) = .empty,

    pub fn init(alloc: std.mem.Allocator) Editor {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Editor) void {
        self.buf.deinit(self.alloc);
        for (self.undo.items) |s| self.alloc.free(s);
        self.undo.deinit(self.alloc);
        for (self.redo.items) |s| self.alloc.free(s);
        self.redo.deinit(self.alloc);
        self.yank.deinit(self.alloc);
    }

    pub fn text(self: *const Editor) []const u8 {
        return self.buf.items;
    }

    pub fn setText(self: *Editor, content: []const u8) !void {
        try self.pushUndo();
        self.buf.clearRetainingCapacity();
        try self.buf.appendSlice(self.alloc, content);
        self.cursor = 0;
        self.anchor = null;
    }

    fn pushUndo(self: *Editor) !void {
        for (self.redo.items) |s| self.alloc.free(s);
        self.redo.clearRetainingCapacity();
        if (self.undo.items.len >= undo_cap) {
            const old = self.undo.orderedRemove(0);
            self.alloc.free(old);
        }
        try self.undo.append(self.alloc, try self.alloc.dupe(u8, self.buf.items));
    }

    pub fn undoOp(self: *Editor) bool {
        const prev = self.undo.pop() orelse return false;
        defer self.alloc.free(prev);
        self.redo.append(self.alloc, self.alloc.dupe(u8, self.buf.items) catch return false) catch return false;
        self.buf.clearRetainingCapacity();
        self.buf.appendSlice(self.alloc, prev) catch return false;
        self.cursor = @min(self.cursor, self.buf.items.len);
        self.anchor = null;
        return true;
    }

    pub fn redoOp(self: *Editor) bool {
        const next = self.redo.pop() orelse return false;
        defer self.alloc.free(next);
        if (self.undo.items.len >= undo_cap) {
            const old = self.undo.orderedRemove(0);
            self.alloc.free(old);
        }
        self.undo.append(self.alloc, self.alloc.dupe(u8, self.buf.items) catch return false) catch return false;
        self.buf.clearRetainingCapacity();
        self.buf.appendSlice(self.alloc, next) catch return false;
        self.cursor = @min(self.cursor, self.buf.items.len);
        self.anchor = null;
        return true;
    }

    pub fn insertText(self: *Editor, s: []const u8) !void {
        try self.pushUndo();
        try self.buf.insertSlice(self.alloc, self.cursor, s);
        self.cursor += s.len;
    }

    pub fn backspace(self: *Editor) !void {
        if (self.cursor == 0) return;
        try self.pushUndo();
        self.buf.replaceRange(self.alloc, self.cursor - 1, 1, &.{"".*}) catch return;
        self.cursor -= 1;
    }

    fn deleteRange(self: *Editor, r: Range) !void {
        std.debug.assert(r.start <= r.end and r.end <= self.buf.items.len);
        try self.pushUndo();
        self.yank.clearRetainingCapacity();
        try self.yank.appendSlice(self.alloc, self.buf.items[r.start..r.end]);
        try self.buf.replaceRange(self.alloc, r.start, r.end - r.start, &.{});
        self.cursor = r.start;
        self.anchor = null;
    }

    fn yankRange(self: *Editor, r: Range) !void {
        std.debug.assert(r.start <= r.end and r.end <= self.buf.items.len);
        self.yank.clearRetainingCapacity();
        try self.yank.appendSlice(self.alloc, self.buf.items[r.start..r.end]);
        self.cursor = r.start;
    }

    pub fn yanked(self: *const Editor) []const u8 {
        return self.yank.items;
    }

    pub fn selectedRange(self: *const Editor) ?Range {
        const a = self.anchor orelse return null;
        if (a < self.cursor) return .{ .start = a, .end = self.cursor };
        return .{ .start = self.cursor, .end = a };
    }

    fn motionRange(self: *Editor, m: u8, arg: ?u8) ?Range {
        const buf = self.buf.items;
        const c = self.cursor;
        switch (m) {
            'w' => {
                const e = wordForward(buf, c);
                if (e == c) return null;
                return .{ .start = c, .end = e };
            },
            'b' => {
                const s = wordBackward(buf, c);
                if (s == c) return null;
                return .{ .start = s, .end = c };
            },
            'e' => {
                const e = wordEnd(buf, c);
                if (e == c) return null;
                const s: usize = if (e > c) c else e;
                const ee: usize = if (e > c) e + 1 else c + 1;
                return .{ .start = s, .end = @min(ee, buf.len) };
            },
            '$' => {
                const le = lineEnd(buf, c);
                if (le == c) return null;
                return .{ .start = c, .end = le };
            },
            '0' => {
                const ls = lineStart(buf, c);
                if (ls == c) return null;
                return .{ .start = ls, .end = c };
            },
            '%' => {
                const t = matchBracket(buf, c) orelse return null;
                if (t > c) return .{ .start = c, .end = t + 1 };
                return .{ .start = t, .end = c + 1 };
            },
            'f', 't' => {
                const target = arg orelse return null;
                const t = findOnLine(buf, c, target, true, m == 't') orelse return null;
                if (t == c) return null;
                return .{ .start = c, .end = t + (if (m == 'f') @as(usize, 1) else @as(usize, 0)) };
            },
            'F', 'T' => {
                const target = arg orelse return null;
                const t = findOnLine(buf, c, target, false, m == 'T') orelse return null;
                if (t == c) return null;
                return .{ .start = t, .end = c };
            },
            'g' => {
                if (c == 0) return null;
                return .{ .start = 0, .end = c };
            },
            'G' => {
                if (c == buf.len) return null;
                return .{ .start = c, .end = buf.len };
            },
            else => return null,
        }
    }

    fn objectRange(self: *Editor, inside: bool, kind: u8) ?Range {
        const buf = self.buf.items;
        const c = self.cursor;
        switch (kind) {
            'w' => return if (inside) innerWord(buf, c) else aroundWord(buf, c),
            '"', '\'', '`', '(', ')', '{', '}', '[', ']' => {
                const k = if (kind == ')') @as(u8, '(') else if (kind == '}') @as(u8, '{') else if (kind == ']') @as(u8, '[') else kind;
                return if (inside) insideDelim(buf, c, k) else aroundDelim(buf, c, k);
            },
            'p' => return if (inside) innerPara(buf, c) else aroundPara(buf, c),
            else => return null,
        }
    }

    const PendingOp = enum { delete, change, yank };

    /// Apply a Normal/Visual key string. `ci"`, `di(`, `yiw`, `dap`, `gg`,
    /// `G`, `w`, `f<char>` and friends compose; unknown keys cancel pending
    /// state without mutating.
    pub fn applyNormalKeys(self: *Editor, keys: []const u8) !void {
        if (self.mode == .insert) {
            for (keys) |ch| {
                if (ch == 27) {
                    self.mode = .normal;
                    if (self.cursor > 0) self.cursor -= 1;
                }
            }
            return;
        }
        if (self.mode == .visual) {
            try self.applyVisualKeys(keys);
            return;
        }
        var op: ?PendingOp = null;
        var g_pending = false;
        var obj_pending: ?struct { op: PendingOp, inside: bool } = null;
        var find_pending: ?struct { op: ?PendingOp, kind: u8 } = null;
        var i: usize = 0;
        while (i < keys.len) : (i += 1) {
            const ch = keys[i];
            if (ch == 27) {
                op = null;
                g_pending = false;
                obj_pending = null;
                find_pending = null;
                continue;
            }
            if (find_pending) |fp| {
                if (fp.op) |o| {
                    if (self.motionRange(fp.kind, ch)) |rr| {
                        try self.applyOp(o, rr);
                        if (self.mode != .normal) return;
                    }
                } else if (findOnLine(
                    self.buf.items,
                    self.cursor,
                    ch,
                    fp.kind == 'f' or fp.kind == 't',
                    fp.kind == 't' or fp.kind == 'T',
                )) |t| {
                    self.cursor = t;
                }
                find_pending = null;
                op = null;
                continue;
            }
            if (obj_pending) |ob| {
                const r = self.objectRange(ob.inside, ch);
                obj_pending = null;
                if (r) |rr| {
                    try self.applyOp(ob.op, rr);
                }
                op = null;
                continue;
            }
            if (g_pending) {
                g_pending = false;
                if (ch == 'g') {
                    if (op) |o| {
                        const c = self.cursor;
                        if (c > 0) {
                            try self.applyOp(o, .{ .start = 0, .end = c });
                            if (self.mode != .normal) return;
                        }
                        op = null;
                    } else {
                        self.cursor = 0;
                    }
                } else {
                    op = null;
                }
                continue;
            }
            if (op) |o| {
                switch (ch) {
                    'd', 'y' => {
                        if ((ch == 'd' and o == .delete) or (ch == 'y' and o == .yank)) {
                            const ls = lineStart(self.buf.items, self.cursor);
                            var le = lineEnd(self.buf.items, self.cursor);
                            if (le < self.buf.items.len) le += 1;
                            if (o == .yank) {
                                try self.yankRange(.{ .start = ls, .end = le });
                            } else {
                                try self.deleteRange(.{ .start = ls, .end = le });
                            }
                            if (o == .change) {
                                self.mode = .insert;
                            }
                            op = null;
                        } else {
                            op = null;
                        }
                        continue;
                    },
                    'c' => {
                        if (o == .change) {
                            const ls = lineStart(self.buf.items, self.cursor);
                            const le = lineEnd(self.buf.items, self.cursor);
                            try self.deleteRange(.{ .start = ls, .end = le });
                            self.mode = .insert;
                            op = null;
                            return;
                        }
                        op = null;
                        continue;
                    },
                    'i' => {
                        obj_pending = .{ .op = o, .inside = true };
                        continue;
                    },
                    'a' => {
                        obj_pending = .{ .op = o, .inside = false };
                        continue;
                    },
                    'g' => {
                        g_pending = true;
                        continue;
                    },
                    'f', 'F', 't', 'T' => {
                        find_pending = .{ .op = o, .kind = ch };
                        continue;
                    },
                    'w', 'b', 'e', '$', '0', '%', 'G' => {
                        if (self.motionRange(ch, null)) |r| {
                            try self.applyOp(o, r);
                            if (self.mode != .normal) return;
                        }
                        op = null;
                        continue;
                    },
                    else => {
                        op = null;
                        continue;
                    },
                }
            }
            switch (ch) {
                'h' => {
                    if (self.cursor > 0) self.cursor -= 1;
                },
                'j' => {
                    self.cursor = moveDown(self.buf.items, self.cursor);
                },
                'k' => {
                    self.cursor = moveUp(self.buf.items, self.cursor);
                },
                'l' => {
                    if (self.cursor < self.buf.items.len) self.cursor += 1;
                },
                'w' => {
                    self.cursor = wordForward(self.buf.items, self.cursor);
                },
                'b' => {
                    self.cursor = wordBackward(self.buf.items, self.cursor);
                },
                'e' => {
                    self.cursor = wordEnd(self.buf.items, self.cursor);
                },
                '0' => {
                    self.cursor = lineStart(self.buf.items, self.cursor);
                },
                '$' => {
                    self.cursor = lineEnd(self.buf.items, self.cursor);
                },
                '^' => {
                    self.cursor = firstNonBlank(self.buf.items, self.cursor);
                },
                'G' => {
                    self.cursor = self.buf.items.len;
                },
                'g' => {
                    g_pending = true;
                },
                '%' => {
                    if (matchBracket(self.buf.items, self.cursor)) |t| self.cursor = t;
                },
                'f', 'F', 't', 'T' => {
                    find_pending = .{ .op = null, .kind = ch };
                },
                'x' => {
                    if (self.cursor < self.buf.items.len) {
                        try self.deleteRange(.{ .start = self.cursor, .end = self.cursor + 1 });
                    }
                },
                'd', 'y' => {
                    op = if (ch == 'd') .delete else .yank;
                },
                'c' => {
                    op = .change;
                },
                'i' => {
                    self.mode = .insert;
                    return;
                },
                'a' => {
                    const le = lineEnd(self.buf.items, self.cursor);
                    if (self.cursor < le) self.cursor += 1;
                    self.mode = .insert;
                    return;
                },
                'v' => {
                    self.mode = .visual;
                    self.anchor = self.cursor;
                    try self.applyVisualKeys(keys[i + 1 ..]);
                    return;
                },
                'u' => {
                    _ = self.undoOp();
                },
                'p' => {
                    if (self.yank.items.len > 0) {
                        try self.pushUndo();
                        const pos = @min(self.cursor + 1, self.buf.items.len);
                        try self.buf.insertSlice(self.alloc, pos, self.yank.items);
                        self.cursor = pos + self.yank.items.len - 1;
                    }
                },
                else => {},
            }
        }
    }

    fn applyOp(self: *Editor, op: ?PendingOp, r: Range) !void {
        const o = op orelse {
            self.cursor = r.end;
            return;
        };
        switch (o) {
            .delete => try self.deleteRange(r),
            .yank => try self.yankRange(r),
            .change => {
                try self.deleteRange(r);
                self.mode = .insert;
            },
        }
    }

    fn applyVisualKeys(self: *Editor, keys: []const u8) !void {
        var i: usize = 0;
        while (i < keys.len) : (i += 1) {
            const ch = keys[i];
            if (ch == 27) {
                self.mode = .normal;
                self.anchor = null;
                return;
            }
            switch (ch) {
                'y' => {
                    if (self.selectedRange()) |r| try self.yankRange(r);
                    self.mode = .normal;
                    self.anchor = null;
                    return;
                },
                'd' => {
                    if (self.selectedRange()) |r| try self.deleteRange(r);
                    self.mode = .normal;
                    return;
                },
                'c' => {
                    if (self.selectedRange()) |r| try self.deleteRange(r);
                    self.mode = .insert;
                    return;
                },
                'h' => {
                    if (self.cursor > 0) self.cursor -= 1;
                },
                'l' => {
                    if (self.cursor < self.buf.items.len) self.cursor += 1;
                },
                'j' => {
                    self.cursor = moveDown(self.buf.items, self.cursor);
                },
                'k' => {
                    self.cursor = moveUp(self.buf.items, self.cursor);
                },
                'w' => {
                    self.cursor = wordForward(self.buf.items, self.cursor);
                },
                'b' => {
                    self.cursor = wordBackward(self.buf.items, self.cursor);
                },
                'e' => {
                    self.cursor = wordEnd(self.buf.items, self.cursor);
                },
                '0' => {
                    self.cursor = lineStart(self.buf.items, self.cursor);
                },
                '$' => {
                    self.cursor = lineEnd(self.buf.items, self.cursor);
                },
                else => {},
            }
        }
    }
};

test "ci-quote composes change inside quote" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.setText("say \"hello world\" ok");
    ed.cursor = 6;
    try ed.applyNormalKeys("ci\"");
    try std.testing.expectEqual(EditorMode.insert, ed.mode);
    try std.testing.expectEqualStrings("say \"\" ok", ed.text());
    try ed.insertText("bye");
    try std.testing.expectEqualStrings("say \"bye\" ok", ed.text());
}

test "di-paren deletes inside parens" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.setText("f(a, (b, c))");
    ed.cursor = 2;
    try ed.applyNormalKeys("di(");
    try std.testing.expectEqualStrings("f()", ed.text());
    ed.cursor = 2;
    try ed.applyNormalKeys("da(");
    try std.testing.expectEqualStrings("f", ed.text());
}

test "yiw yanks inner word and p pastes" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.setText("foo bar");
    ed.cursor = 4;
    try ed.applyNormalKeys("yiw");
    try std.testing.expectEqualStrings("bar", ed.yanked());
    ed.cursor = 0;
    try ed.applyNormalKeys("p");
    try std.testing.expectEqualStrings("fbaroo bar", ed.text());
}

test "word motions w b e cross lines" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.setText("foo bar\nbaz qux");
    ed.cursor = 0;
    try ed.applyNormalKeys("w");
    try std.testing.expectEqual(@as(usize, 4), ed.cursor);
    try ed.applyNormalKeys("e");
    try std.testing.expectEqual(@as(usize, 6), ed.cursor);
    try ed.applyNormalKeys("b");
    try std.testing.expectEqual(@as(usize, 4), ed.cursor);
    try ed.applyNormalKeys("G");
    try std.testing.expectEqual(ed.text().len, ed.cursor);
    try ed.applyNormalKeys("gg");
    try std.testing.expectEqual(@as(usize, 0), ed.cursor);
}

test "f t and match bracket move" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.setText("(a(b)c)");
    ed.cursor = 0;
    try ed.applyNormalKeys("%");
    try std.testing.expectEqual(@as(usize, 6), ed.cursor);
    try ed.setText("foo:bar:baz");
    ed.cursor = 0;
    try ed.applyNormalKeys("f:");
    try std.testing.expectEqual(@as(usize, 3), ed.cursor);
    try ed.applyNormalKeys("t:");
    try std.testing.expectEqual(@as(usize, 6), ed.cursor);
}

test "dap deletes a paragraph" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.setText("one\n\ntwo\nthree\n\nfour");
    ed.cursor = 6;
    try ed.applyNormalKeys("dap");
    try std.testing.expectEqualStrings("one\n\nfour", ed.text());
}

test "undo and redo restore snapshots" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.setText("hello");
    ed.cursor = 4;
    try ed.applyNormalKeys("x");
    try std.testing.expectEqual(@as(usize, 4), ed.cursor);
    try std.testing.expect(ed.undoOp());
    try std.testing.expectEqualStrings("hello", ed.text());
    try std.testing.expect(ed.redoOp());
    try std.testing.expectEqual(@as(usize, 4), ed.text().len);
}

test "visual yank and delete use selection" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.setText("hello world");
    ed.cursor = 0;
    try ed.applyNormalKeys("vwwy");
    try std.testing.expectEqualStrings("hello world", ed.yanked());
    try std.testing.expectEqual(EditorMode.normal, ed.mode);
    try ed.setText("hello world");
    ed.cursor = 0;
    try ed.applyNormalKeys("vw");
    try ed.applyNormalKeys("d");
    try std.testing.expectEqualStrings("world", ed.text());
}
