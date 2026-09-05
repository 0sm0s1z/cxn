const std = @import("std");
const provider = @import("provider.zig");
const commands = @import("commands.zig");
const editor = @import("editor.zig");
const transcript = @import("transcript.zig");
const surfaces = @import("surfaces.zig");

pub const endpoint_env_base = "FX_CONSTELLATION_BASE_URL";
pub const endpoint_env_key = "FX_CONSTELLATION_API_KEY";
pub const default_base_url = "http://router.local:8080";

pub const Endpoint = struct {
    base_url: []const u8,
    has_api_key: bool,
    valid: bool,
};

pub fn resolveEndpoint(base_url: ?[]const u8, api_key: ?[]const u8) Endpoint {
    const base = base_url orelse default_base_url;
    const valid = provider.isValidBaseUrl(base);
    return .{
        .base_url = provider.normalizeBaseUrl(base),
        .has_api_key = if (api_key) |k| k.len > 0 else false,
        .valid = valid,
    };
}

pub const AppMode = enum { insert, normal, visual, transcript, command, surface };

pub fn commandContext(mode: AppMode, has_focused_block: bool, surface_focused: bool) commands.Context {
    const m: commands.Mode = switch (mode) {
        .insert => .insert,
        .normal => .normal,
        .visual => .visual,
        .transcript => .transcript,
        .command => .command,
        .surface => .surface,
    };
    return .{ .mode = m, .has_focused_block = has_focused_block, .surface_focused = surface_focused };
}

pub const Controller = struct {
    alloc: std.mem.Allocator,
    ed: editor.Editor,
    tr: transcript.Transcript,
    hits: surfaces.HitMap,
    placements: surfaces.PlacementGen = .{},
    mode: AppMode = .normal,
    capability: surfaces.Capability = .text,

    pub fn init(alloc: std.mem.Allocator) Controller {
        return .{
            .alloc = alloc,
            .ed = editor.Editor.init(alloc),
            .tr = transcript.Transcript.init(alloc),
            .hits = surfaces.HitMap.init(alloc),
        };
    }

    pub fn deinit(self: *Controller) void {
        self.ed.deinit();
        self.tr.deinit();
        self.hits.deinit();
    }

    pub fn context(self: *const Controller) commands.Context {
        const focused = self.tr.focused() != null;
        return commandContext(self.mode, focused, self.mode == .surface);
    }

    pub fn runCommand(self: *const Controller, name: []const u8) commands.DispatchResult {
        const id = commands.idFromString(name) orelse return .{ .ok = false, .unavailable_reason = "unknown command" };
        return commands.dispatch(id, self.context());
    }

    pub fn enterTranscript(self: *Controller) void {
        self.mode = .transcript;
    }

    pub fn focusedText(self: *const Controller) ?[]const u8 {
        const b = self.tr.focused() orelse return null;
        return b.text;
    }

    pub fn editFocused(self: *Controller, replacement: []const u8) transcript.BranchDecision {
        const focus = self.tr.focus orelse return .{ .branch = false };
        const decision = transcript.decideBranch(focus, self.tr.blocks.items.len -| 1);
        if (decision.branch) {
            self.tr.blocks.items[focus].text = replacement;
        } else if (focus < self.tr.blocks.items.len) {
            self.tr.blocks.items[focus].text = replacement;
        }
        return decision;
    }

    pub fn rebuildHitMap(self: *Controller) !void {
        self.hits.clear();
        var y: u16 = 0;
        for (self.tr.blocks.items) |b| {
            try self.hits.add(.{
                .rect = .{ .x = 0, .y = y, .w = 80, .h = 1 },
                .object_id = b.id,
                .action = .focus_block,
            });
            y += 1;
        }
    }

    pub fn onResize(self: *Controller) void {
        self.placements.invalidateOnResize();
    }
};

pub const Snapshot = struct {
    endpoint_valid: bool,
    base_url: []const u8,
    has_api_key: bool,
    catalog: []const []const u8,
    mode: []const u8,
    focused_text: ?[]const u8,
    branch_on_edit: bool,
    diagram: surfaces.DiagramPresentation,
    image: surfaces.ImagePresentation,
    hit_object: ?u64,
    placement_gen: u64,
};

pub fn renderText(alloc: std.mem.Allocator, snap: Snapshot) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    try out.writer.print("constellation status\n", .{});
    try out.writer.print("router: {s} valid={} has_key={}\n", .{ snap.base_url, snap.endpoint_valid, snap.has_api_key });
    try out.writer.print("catalog:", .{});
    for (snap.catalog) |id| try out.writer.print(" {s}", .{id});
    try out.writer.print("\nmode: {s}\n", .{snap.mode});
    if (snap.focused_text) |t| try out.writer.print("focused: {s}\n", .{t});
    try out.writer.print("branch_on_edit={} diagram={t} image={t} hit={?d} gen={d}\n", .{
        snap.branch_on_edit,
        snap.diagram,
        snap.image,
        snap.hit_object,
        snap.placement_gen,
    });
    return out.toOwnedSlice();
}

pub fn renderJson(alloc: std.mem.Allocator, snap: Snapshot) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    try out.writer.print("{{\"router\":{{\"base_url\":\"{s}\",\"valid\":{},\"has_key\":{}}},\"catalog\":[", .{
        snap.base_url,
        snap.endpoint_valid,
        snap.has_api_key,
    });
    for (snap.catalog, 0..) |id, i| {
        if (i > 0) try out.writer.print(",", .{});
        try out.writer.print("\"{s}\"", .{id});
    }
    try out.writer.print("],\"mode\":\"{s}\",\"branch_on_edit\":{},\"placement_gen\":{d}}}", .{
        snap.mode,
        snap.branch_on_edit,
        snap.placement_gen,
    });
    return out.toOwnedSlice();
}

test "endpoint resolution validates base url" {
    const good = resolveEndpoint("https://router.example.com/", "key");
    try std.testing.expect(good.valid);
    try std.testing.expect(good.has_api_key);
    try std.testing.expectEqualStrings("https://router.example.com", good.base_url);
    const bad = resolveEndpoint("router.example.com", null);
    try std.testing.expect(!bad.valid);
    try std.testing.expect(!bad.has_api_key);
}

test "controller runs the shipped command path" {
    var c = Controller.init(std.testing.allocator);
    defer c.deinit();
    _ = try c.tr.append(.user_message, "Fix the auth handler.");
    _ = try c.tr.append(.assistant_message, "Done.");
    c.enterTranscript();
    const ok = c.runCommand("conversation.block.copy");
    try std.testing.expect(ok.ok);
    const surface_ok = c.runCommand("surface.raw");
    try std.testing.expect(surface_ok.ok);
    c.mode = .insert;
    const bad = c.runCommand("surface.raw");
    try std.testing.expect(!bad.ok);
    try std.testing.expect(c.runCommand("nope.missing").unavailable_reason != null);
}

test "scripted exercise covers pick vim nav fork mouse" {
    var c = Controller.init(std.testing.allocator);
    defer c.deinit();
    const alloc = std.testing.allocator;
    const catalog = try provider.buildCatalog(alloc, &.{ "grok-4", "gpt-5" });
    defer alloc.free(catalog);
    try std.testing.expectEqualStrings("auto", catalog[0]);

    try c.ed.setText("say \"hello world\" ok");
    c.ed.cursor = 6;
    c.ed.mode = .normal;
    try c.ed.applyNormalKeys("ci\"");
    try std.testing.expectEqual(editor.EditorMode.insert, c.ed.mode);

    _ = try c.tr.append(.user_message, "Fix the auth handler.");
    _ = try c.tr.append(.assistant_message, "Done.");
    c.enterTranscript();
    try std.testing.expect(c.tr.moveNext());
    try std.testing.expectEqualStrings("Done.", c.focusedText().?);
    const decision = c.editFocused("Fix the auth handler without changing the public API.");
    try std.testing.expect(decision.branch);
    try std.testing.expect(decision.preserves_original);

    c.capability = .kitty_native;
    try std.testing.expectEqual(surfaces.DiagramPresentation.kitty_raster, surfaces.pickDiagram(c.capability));
    try c.rebuildHitMap();
    const hit = c.hits.hitTest(3, 1).?;
    try std.testing.expectEqual(@as(u64, 2), hit.object_id);
    const gen_before = c.placements.current;
    c.onResize();
    try std.testing.expect(c.placements.isStale(gen_before));
}

test "snapshot renders text and json from the same data" {
    const alloc = std.testing.allocator;
    const catalog: []const []const u8 = &.{ "auto", "grok-4" };
    const snap = Snapshot{
        .endpoint_valid = true,
        .base_url = "http://router.local:8080",
        .has_api_key = false,
        .catalog = catalog,
        .mode = "transcript",
        .focused_text = "hello",
        .branch_on_edit = true,
        .diagram = .kitty_raster,
        .image = .kitty_image,
        .hit_object = 2,
        .placement_gen = 1,
    };
    const text = try renderText(alloc, snap);
    defer alloc.free(text);
    const json = try renderJson(alloc, snap);
    defer alloc.free(json);
    try std.testing.expect(std.mem.indexOf(u8, text, "constellation status") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"catalog\":[\"auto\",\"grok-4\"]") != null);
}
