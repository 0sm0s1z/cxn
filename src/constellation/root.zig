const std = @import("std");

pub const provider = @import("provider.zig");
pub const commands = @import("commands.zig");
pub const editor = @import("editor.zig");
pub const transcript = @import("transcript.zig");
pub const surfaces = @import("surfaces.zig");
pub const integration = @import("integration.zig");

pub const product_name = "constellation";
pub const mvp_scope = "FX upstream + router + vim composer + transcript mode + forkable prompts + clickable blocks";

test {
    std.testing.refAllDecls(provider);
    std.testing.refAllDecls(commands);
    std.testing.refAllDecls(editor);
    std.testing.refAllDecls(transcript);
    std.testing.refAllDecls(surfaces);
    std.testing.refAllDecls(integration);
}

test "constellation root exposes the mvp scope" {
    try std.testing.expectEqualStrings("constellation", product_name);
    try std.testing.expect(mvp_scope.len > 0);
}
