const std = @import("std");

pub const Capability = enum { kitty_native, kitty_placeholder, sixel, symbols, text };

pub fn detect(has_kitty_graphics: bool, has_sixel: bool) Capability {
    if (has_kitty_graphics) return .kitty_native;
    if (has_sixel) return .sixel;
    return .text;
}

pub fn supportsPixels(cap: Capability) bool {
    return cap == .kitty_native or cap == .kitty_placeholder or cap == .sixel;
}

pub const DiagramPresentation = enum { source, unicode_diagram, kitty_raster };
pub const ImagePresentation = enum { metadata, thumbnail, kitty_image };
pub const BrowserPresentation = enum { url_only, screenshot, interactive_surface };

pub fn pickDiagram(cap: Capability) DiagramPresentation {
    if (cap == .kitty_native or cap == .kitty_placeholder) return .kitty_raster;
    if (cap == .sixel or cap == .symbols) return .unicode_diagram;
    return .source;
}

pub fn pickImage(cap: Capability) ImagePresentation {
    if (cap == .kitty_native or cap == .kitty_placeholder) return .kitty_image;
    if (cap == .sixel or cap == .symbols) return .thumbnail;
    return .metadata;
}

pub fn pickBrowser(cap: Capability, surface_focused: bool) BrowserPresentation {
    if (surface_focused and (cap == .kitty_native or cap == .kitty_placeholder)) return .interactive_surface;
    if (supportsPixels(cap)) return .screenshot;
    return .url_only;
}

pub const Rect = struct { x: u16, y: u16, w: u16, h: u16 };

pub fn rectContains(r: Rect, x: u16, y: u16) bool {
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h;
}

pub const HitAction = enum {
    focus_block,
    activate_block,
    edit_block,
    copy_block,
    select_provider,
    select_model,
    show_context,
    show_mode,
    code_copy,
    code_apply,
    code_run,
    code_open,
};

pub const HitRegion = struct {
    rect: Rect,
    object_id: u64,
    action: HitAction,
};

pub const HitMap = struct {
    alloc: std.mem.Allocator,
    regions: std.ArrayList(HitRegion) = .empty,

    pub fn init(alloc: std.mem.Allocator) HitMap {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *HitMap) void {
        self.regions.deinit(self.alloc);
    }

    pub fn clear(self: *HitMap) void {
        self.regions.clearRetainingCapacity();
    }

    pub fn add(self: *HitMap, region: HitRegion) !void {
        try self.regions.append(self.alloc, region);
    }

    /// Topmost region wins: later regions overlap earlier ones.
    pub fn hitTest(self: *const HitMap, x: u16, y: u16) ?HitRegion {
        var i = self.regions.items.len;
        while (i > 0) {
            i -= 1;
            const r = self.regions.items[i];
            if (rectContains(r.rect, x, y)) return r;
        }
        return null;
    }
};

/// Resize generation: placements carry the generation they were built under.
/// A resize bumps the generation; anything older is stale and re-placed.
pub const PlacementGen = struct {
    current: u64 = 0,

    pub fn invalidateOnResize(self: *PlacementGen) void {
        self.current += 1;
    }

    pub fn isStale(self: PlacementGen, placement_gen: u64) bool {
        return placement_gen != self.current;
    }
};

pub const FooterSegment = enum { provider, model, context, mode };

pub fn footerAction(segment: FooterSegment) HitAction {
    return switch (segment) {
        .provider => .select_provider,
        .model => .select_model,
        .context => .show_context,
        .mode => .show_mode,
    };
}

test "capability detection prefers kitty then sixel then text" {
    try std.testing.expectEqual(Capability.kitty_native, detect(true, true));
    try std.testing.expectEqual(Capability.sixel, detect(false, true));
    try std.testing.expectEqual(Capability.text, detect(false, false));
    try std.testing.expect(supportsPixels(.kitty_native));
    try std.testing.expect(supportsPixels(.sixel));
    try std.testing.expect(!supportsPixels(.text));
    try std.testing.expect(!supportsPixels(.symbols));
}

test "presentation selection keeps prose native and pixels for rich blocks" {
    try std.testing.expectEqual(DiagramPresentation.kitty_raster, pickDiagram(.kitty_native));
    try std.testing.expectEqual(DiagramPresentation.unicode_diagram, pickDiagram(.symbols));
    try std.testing.expectEqual(DiagramPresentation.source, pickDiagram(.text));
    try std.testing.expectEqual(ImagePresentation.kitty_image, pickImage(.kitty_placeholder));
    try std.testing.expectEqual(ImagePresentation.thumbnail, pickImage(.sixel));
    try std.testing.expectEqual(ImagePresentation.metadata, pickImage(.text));
    try std.testing.expectEqual(BrowserPresentation.interactive_surface, pickBrowser(.kitty_native, true));
    try std.testing.expectEqual(BrowserPresentation.screenshot, pickBrowser(.kitty_native, false));
    try std.testing.expectEqual(BrowserPresentation.url_only, pickBrowser(.text, true));
}

test "hit test routes coordinates to the topmost region" {
    var map = HitMap.init(std.testing.allocator);
    defer map.deinit();
    try map.add(.{ .rect = .{ .x = 0, .y = 0, .w = 80, .h = 5 }, .object_id = 1, .action = .focus_block });
    try map.add(.{ .rect = .{ .x = 2, .y = 1, .w = 8, .h = 1 }, .object_id = 2, .action = .code_copy });
    const hit = map.hitTest(3, 1).?;
    try std.testing.expectEqual(@as(u64, 2), hit.object_id);
    try std.testing.expectEqual(HitAction.code_copy, hit.action);
    try std.testing.expectEqual(@as(u64, 1), map.hitTest(70, 2).?.object_id);
    try std.testing.expect(map.hitTest(0, 9) == null);
    map.clear();
    try std.testing.expect(map.hitTest(3, 1) == null);
}

test "resize invalidates stale placements" {
    var gen = PlacementGen{};
    try std.testing.expect(!gen.isStale(0));
    gen.invalidateOnResize();
    try std.testing.expect(gen.isStale(0));
    try std.testing.expect(!gen.isStale(1));
}

test "footer segments map to picker actions" {
    try std.testing.expectEqual(HitAction.select_provider, footerAction(.provider));
    try std.testing.expectEqual(HitAction.select_model, footerAction(.model));
    try std.testing.expectEqual(HitAction.show_context, footerAction(.context));
    try std.testing.expectEqual(HitAction.show_mode, footerAction(.mode));
}
