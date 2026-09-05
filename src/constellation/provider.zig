const std = @import("std");

pub const default_model = "auto";
pub const client_header_name = "x-constellation-client";
pub const client_header_value = "fx";
pub const slug = "constellation";
pub const slug_alias = "cxn";

pub fn isProfileSlug(value: []const u8) bool {
    return std.ascii.eqlIgnoreCase(value, slug) or std.ascii.eqlIgnoreCase(value, slug_alias);
}

pub fn isAutoModel(value: []const u8) bool {
    return std.ascii.eqlIgnoreCase(value, "auto");
}

pub fn normalizeBaseUrl(value: []const u8) []const u8 {
    var end = value.len;
    while (end > 0 and value[end - 1] == '/') end -= 1;
    return value[0..end];
}

pub fn isValidBaseUrl(value: []const u8) bool {
    const base = normalizeBaseUrl(value);
    return std.mem.startsWith(u8, base, "http://") or std.mem.startsWith(u8, base, "https://");
}

pub const Profile = struct {
    base_url: []const u8,
    model: []const u8 = default_model,
    has_api_key: bool = false,

    pub fn isRouterAuto(self: Profile) bool {
        return isAutoModel(self.model);
    }
};

pub const RoutingMetadata = struct {
    provider: ?[]const u8 = null,
    seat: ?[]const u8 = null,
    route: ?[]const u8 = null,
    subscription: ?[]const u8 = null,
    cached_tokens: ?u64 = null,
    reasoning_tier: ?[]const u8 = null,
    request_id: ?[]const u8 = null,
    latency_ms: ?u64 = null,

    pub fn hasAny(self: RoutingMetadata) bool {
        return self.provider != null or self.seat != null or self.route != null or
            self.subscription != null or self.cached_tokens != null or
            self.reasoning_tier != null or self.request_id != null or
            self.latency_ms != null;
    }
};

pub fn shouldIncludeDiscovered(model_id: []const u8) bool {
    if (model_id.len == 0) return false;
    return !isAutoModel(model_id);
}

/// Build the picker catalog: `auto` first, then discovered ids in order with
/// case-insensitive dedup. Caller owns the returned slice.
pub fn buildCatalog(allocator: std.mem.Allocator, discovered: []const []const u8) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(allocator);
    try out.append(allocator, default_model);
    for (discovered) |id| {
        if (!shouldIncludeDiscovered(id)) continue;
        var dup = false;
        for (out.items) |existing| {
            if (std.ascii.eqlIgnoreCase(existing, id)) {
                dup = true;
                break;
            }
        }
        if (!dup) try out.append(allocator, id);
    }
    return out.toOwnedSlice(allocator);
}

test "constellation slug matches with alias" {
    try std.testing.expect(isProfileSlug("constellation"));
    try std.testing.expect(isProfileSlug("CONSTELLATION"));
    try std.testing.expect(isProfileSlug("cxn"));
    try std.testing.expect(!isProfileSlug("vercel"));
    try std.testing.expect(!isProfileSlug("custom-openai"));
}

test "base url validation and normalization" {
    try std.testing.expect(isValidBaseUrl("http://router:8080"));
    try std.testing.expect(isValidBaseUrl("https://router.example.com/"));
    try std.testing.expect(!isValidBaseUrl("router.example.com"));
    try std.testing.expect(!isValidBaseUrl(""));
    try std.testing.expectEqualStrings("http://router:8080", normalizeBaseUrl("http://router:8080///"));
    try std.testing.expectEqualStrings("auto", (Profile{ .base_url = "http://r" }).model);
    try std.testing.expect((Profile{ .base_url = "http://r" }).isRouterAuto());
    try std.testing.expect(!(Profile{ .base_url = "http://r", .model = "grok-4" }).isRouterAuto());
}

test "routing metadata reports presence" {
    try std.testing.expect(!(RoutingMetadata{}).hasAny());
    try std.testing.expect((RoutingMetadata{ .route = "fast" }).hasAny());
    try std.testing.expect((RoutingMetadata{ .latency_ms = 12 }).hasAny());
}

test "catalog puts auto first with dedup" {
    const alloc = std.testing.allocator;
    const discovered: []const []const u8 = &.{ "grok-4", "AUTO", "", "grok-4", "gpt-5" };
    const catalog = try buildCatalog(alloc, discovered);
    defer alloc.free(catalog);
    try std.testing.expectEqual(@as(usize, 3), catalog.len);
    try std.testing.expectEqualStrings("auto", catalog[0]);
    try std.testing.expectEqualStrings("grok-4", catalog[1]);
    try std.testing.expectEqualStrings("gpt-5", catalog[2]);
}
