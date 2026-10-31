//! Focused downstream tests, with src/ as the module root for shared helpers.
test {
    _ = @import("constellation/root.zig");
    _ = @import("constellation/tui_render_tests.zig");
}
