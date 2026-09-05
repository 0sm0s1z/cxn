const std = @import("std");

pub const branch_confirm_text = "Editing historical prompt will branch the session from this point.";

pub const BlockType = enum {
    user_message,
    assistant_message,
    reasoning_summary,
    tool_call,
    tool_result,
    code,
    markdown,
    image,
    diagram,
    browser,
    system_notice,
};

pub const Block = struct {
    id: u64,
    kind: BlockType,
    text: []const u8 = "",
    folded: bool = false,

    pub fn sourceEditable(self: Block) bool {
        return switch (self.kind) {
            .user_message, .assistant_message, .markdown, .code, .diagram, .tool_call, .image => true,
            .reasoning_summary, .tool_result, .browser, .system_notice => false,
        };
    }
};

pub const Transcript = struct {
    alloc: std.mem.Allocator,
    blocks: std.ArrayList(Block) = .empty,
    focus: ?usize = null,
    viewport_top: usize = 0,
    next_id: u64 = 1,

    pub fn init(alloc: std.mem.Allocator) Transcript {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Transcript) void {
        self.blocks.deinit(self.alloc);
    }

    pub fn append(self: *Transcript, kind: BlockType, text: []const u8) !u64 {
        const id = self.next_id;
        self.next_id += 1;
        try self.blocks.append(self.alloc, .{ .id = id, .kind = kind, .text = text });
        if (self.focus == null) self.focus = 0;
        return id;
    }

    pub fn focused(self: *const Transcript) ?Block {
        const i = self.focus orelse return null;
        if (i >= self.blocks.items.len) return null;
        return self.blocks.items[i];
    }

    pub fn moveNext(self: *Transcript) bool {
        if (self.blocks.items.len == 0) return false;
        const cur = self.focus orelse 0;
        if (cur + 1 >= self.blocks.items.len) return false;
        self.focus = cur + 1;
        return true;
    }

    pub fn movePrev(self: *Transcript) bool {
        const cur = self.focus orelse return false;
        if (cur == 0) return false;
        self.focus = cur - 1;
        return true;
    }

    pub fn moveFirst(self: *Transcript) bool {
        if (self.blocks.items.len == 0) return false;
        self.focus = 0;
        return true;
    }

    pub fn moveLast(self: *Transcript) bool {
        if (self.blocks.items.len == 0) return false;
        self.focus = self.blocks.items.len - 1;
        return true;
    }

    pub fn searchForward(self: *const Transcript, needle: []const u8, from: usize) ?usize {
        if (needle.len == 0) return null;
        var i = from;
        while (i < self.blocks.items.len) : (i += 1) {
            if (std.mem.indexOf(u8, self.blocks.items[i].text, needle) != null) return i;
        }
        return null;
    }

    pub fn toggleFold(self: *Transcript, index: usize) bool {
        if (index >= self.blocks.items.len) return false;
        self.blocks.items[index].folded = !self.blocks.items[index].folded;
        return self.blocks.items[index].folded;
    }

    pub const ViewportPlacement = enum { top, center, bottom };

    pub fn placeViewport(self: *Transcript, placement: ViewportPlacement, height: usize) void {
        const f = self.focus orelse return;
        switch (placement) {
            .top => self.viewport_top = f,
            .center => self.viewport_top = f - @min(f, height / 2),
            .bottom => self.viewport_top = f - @min(f, height -| 1),
        }
    }
};

pub const BranchDecision = struct {
    branch: bool,
    preserves_original: bool = true,
};

/// Editing a block at or before the last executed index forks the session;
/// editing anything after it (an unexecuted draft) edits in place.
pub fn decideBranch(edited_index: usize, last_executed_index: ?usize) BranchDecision {
    const last = last_executed_index orelse return .{ .branch = false };
    return .{ .branch = edited_index <= last };
}

test "transcript navigation moves by block" {
    var tr = Transcript.init(std.testing.allocator);
    defer tr.deinit();
    _ = try tr.append(.user_message, "fix auth");
    _ = try tr.append(.assistant_message, "done");
    _ = try tr.append(.tool_call, "read file");
    try std.testing.expectEqual(@as(usize, 0), tr.focus.?);
    try std.testing.expect(tr.moveNext());
    try std.testing.expect(tr.moveNext());
    try std.testing.expect(!tr.moveNext());
    try std.testing.expect(tr.movePrev());
    try std.testing.expect(tr.moveFirst());
    try std.testing.expectEqual(@as(usize, 0), tr.focus.?);
    try std.testing.expect(tr.moveLast());
    try std.testing.expectEqual(@as(usize, 2), tr.focus.?);
    try std.testing.expectEqualStrings("read file", tr.focused().?.text);
}

test "search finds blocks and fold toggles" {
    var tr = Transcript.init(std.testing.allocator);
    defer tr.deinit();
    _ = try tr.append(.user_message, "fix the auth handler");
    _ = try tr.append(.assistant_message, "fixed");
    try std.testing.expectEqual(@as(usize, 0), tr.searchForward("auth", 0).?);
    try std.testing.expectEqual(@as(usize, 0), tr.searchForward("auth", 0).?);
    try std.testing.expect(tr.searchForward("missing", 0) == null);
    try std.testing.expect(tr.searchForward("", 0) == null);
    try std.testing.expect(tr.toggleFold(0));
    try std.testing.expect(!tr.toggleFold(0));
    try std.testing.expect(!tr.toggleFold(99));
}

test "branch policy forks executed history only" {
    try std.testing.expect((decideBranch(1, 2)).branch);
    try std.testing.expect((decideBranch(2, 2)).branch);
    try std.testing.expect(!(decideBranch(3, 2)).branch);
    try std.testing.expect(!(decideBranch(0, null)).branch);
    try std.testing.expect((decideBranch(0, 0)).preserves_original);
    try std.testing.expectEqualStrings(
        "Editing historical prompt will branch the session from this point.",
        branch_confirm_text,
    );
}

test "viewport placement centers focus" {
    var tr = Transcript.init(std.testing.allocator);
    defer tr.deinit();
    _ = try tr.append(.user_message, "a");
    _ = try tr.append(.user_message, "b");
    _ = try tr.append(.user_message, "c");
    _ = try tr.append(.user_message, "d");
    _ = try tr.append(.user_message, "e");
    tr.focus = 3;
    tr.placeViewport(.top, 3);
    try std.testing.expectEqual(@as(usize, 3), tr.viewport_top);
    tr.placeViewport(.center, 4);
    try std.testing.expectEqual(@as(usize, 1), tr.viewport_top);
    tr.placeViewport(.bottom, 2);
    try std.testing.expectEqual(@as(usize, 2), tr.viewport_top);
}

test "source editability covers block types" {
    try std.testing.expect((Block{ .id = 1, .kind = .user_message }).sourceEditable());
    try std.testing.expect((Block{ .id = 1, .kind = .markdown }).sourceEditable());
    try std.testing.expect((Block{ .id = 1, .kind = .diagram }).sourceEditable());
    try std.testing.expect(!(Block{ .id = 1, .kind = .reasoning_summary }).sourceEditable());
    try std.testing.expect(!(Block{ .id = 1, .kind = .system_notice }).sourceEditable());
}
