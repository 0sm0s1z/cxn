const std = @import("std");

pub const Id = enum {
    block_next,
    block_prev,
    block_first,
    block_last,
    block_edit,
    block_copy,
    block_fork,
    block_search,
    block_fold,
    viewport_top,
    viewport_center,
    viewport_bottom,
    provider_select,
    model_select,
    surface_activate,
    surface_raw,
    cursor_doc_start,
};

pub const Mode = enum {
    insert,
    normal,
    visual,
    transcript,
    command,
    surface,
};

pub const Context = struct {
    mode: Mode,
    has_focused_block: bool = false,
    surface_focused: bool = false,
};

pub const known_names = [_]struct { name: []const u8, id: Id }{
    .{ .name = "conversation.block.next", .id = .block_next },
    .{ .name = "conversation.block.prev", .id = .block_prev },
    .{ .name = "conversation.block.first", .id = .block_first },
    .{ .name = "conversation.block.last", .id = .block_last },
    .{ .name = "conversation.block.edit", .id = .block_edit },
    .{ .name = "conversation.block.copy", .id = .block_copy },
    .{ .name = "conversation.block.fork", .id = .block_fork },
    .{ .name = "conversation.block.search", .id = .block_search },
    .{ .name = "conversation.block.fold", .id = .block_fold },
    .{ .name = "viewport.top", .id = .viewport_top },
    .{ .name = "viewport.center", .id = .viewport_center },
    .{ .name = "viewport.bottom", .id = .viewport_bottom },
    .{ .name = "provider.select", .id = .provider_select },
    .{ .name = "model.select", .id = .model_select },
    .{ .name = "surface.activate", .id = .surface_activate },
    .{ .name = "surface.raw", .id = .surface_raw },
    .{ .name = "cursor.document_start", .id = .cursor_doc_start },
};

pub fn idFromString(name: []const u8) ?Id {
    for (known_names) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return entry.id;
    }
    return null;
}

pub fn idToString(id: Id) []const u8 {
    for (known_names) |entry| {
        if (entry.id == id) return entry.name;
    }
    unreachable;
}

/// Whether a command can run in the given context. Block navigation needs
/// transcript mode; block actions additionally need a focused block; surface
/// actions need a focused surface; pickers work from text modes.
pub fn available(id: Id, ctx: Context) bool {
    switch (id) {
        .block_next, .block_prev, .block_first, .block_last, .block_search => {
            return ctx.mode == .transcript;
        },
        .block_edit, .block_copy, .block_fork, .block_fold => {
            return ctx.mode == .transcript and ctx.has_focused_block;
        },
        .viewport_top, .viewport_center, .viewport_bottom => {
            return ctx.mode == .transcript and ctx.has_focused_block;
        },
        .surface_activate, .surface_raw => {
            return ctx.surface_focused or
                (ctx.mode == .transcript and ctx.has_focused_block) or
                ctx.mode == .surface;
        },
        .provider_select, .model_select => {
            return switch (ctx.mode) {
                .insert, .normal, .transcript, .command => true,
                .visual, .surface => false,
            };
        },
        .cursor_doc_start => {
            return ctx.mode == .normal or ctx.mode == .transcript;
        },
    }
}

pub const DispatchResult = struct {
    ok: bool,
    unavailable_reason: ?[]const u8 = null,
};

pub fn dispatch(id: Id, ctx: Context) DispatchResult {
    if (!available(id, ctx)) {
        return .{ .ok = false, .unavailable_reason = "command unavailable in this mode or without focus" };
    }
    return .{ .ok = true };
}

test "command names round-trip through stable strings" {
    for (known_names) |entry| {
        try std.testing.expectEqual(entry.id, idFromString(entry.name).?);
        try std.testing.expectEqualStrings(entry.name, idToString(entry.id));
    }
    try std.testing.expect(idFromString("nope.missing") == null);
    try std.testing.expectEqualStrings("conversation.block.edit", idToString(.block_edit));
    try std.testing.expectEqualStrings("cursor.document_start", idToString(.cursor_doc_start));
}

test "block actions need transcript mode and focus" {
    const unfocused = Context{ .mode = .transcript };
    const focused = Context{ .mode = .transcript, .has_focused_block = true };
    try std.testing.expect(!available(.block_edit, unfocused));
    try std.testing.expect(!available(.block_copy, unfocused));
    try std.testing.expect(!available(.block_fork, unfocused));
    try std.testing.expect(available(.block_edit, focused));
    try std.testing.expect(available(.block_next, unfocused));
    try std.testing.expect(!available(.block_next, Context{ .mode = .insert }));
    try std.testing.expect(!available(.block_search, Context{ .mode = .normal }));
}

test "pickers and surface actions follow focus rules" {
    try std.testing.expect(available(.provider_select, Context{ .mode = .insert }));
    try std.testing.expect(available(.model_select, Context{ .mode = .transcript }));
    try std.testing.expect(!available(.provider_select, Context{ .mode = .visual }));
    try std.testing.expect(available(.surface_activate, Context{ .mode = .surface, .surface_focused = true }));
    try std.testing.expect(!available(.surface_raw, Context{ .mode = .insert }));
}

test "dispatch reports structured unavailability" {
    const ok = dispatch(.block_copy, Context{ .mode = .transcript, .has_focused_block = true });
    try std.testing.expect(ok.ok);
    const bad = dispatch(.block_copy, Context{ .mode = .insert });
    try std.testing.expect(!bad.ok);
    try std.testing.expect(bad.unavailable_reason != null);
}
