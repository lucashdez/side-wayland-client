const std = @import("std");
const wl = @cImport({
    @cInclude("wayland-client-protocol.h");
    @cInclude("wayland-protocols/xdg-shell-enum.h");
});
const assert = std.debug.assert;

const WlState = struct {
    display: ?*wl.wl_display,
    registry: ?*wl.wl_registry,
    compositor: ?*wl.wl_compositor,
    surface: ?*wl.wl_surface,
    shm: ?*wl.wl_shm,
};

fn registry_handle_global(data: ?*anyopaque, registry: ?*wl.wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
    if (data != null) {
        var state: *WlState = @alignCast(@ptrCast(data));
        if (std.mem.eql(u8, std.mem.span(interface), "wl_compositor")) {
            state.compositor = @ptrCast(wl.wl_registry_bind(registry, name, &wl.wl_compositor_interface, version));
            std.log.debug("[DONE] binded compositor", .{});
        }
        if (std.mem.eql(u8, std.mem.span(interface), "wl_shm")) {
            state.shm = @ptrCast(wl.wl_registry_bind(registry, name, &wl.wl_shm_interface, version));
            std.log.debug("[DONE] binded shm", .{});
        }

    }
    std.log.info("name: {d}, interface: {s}, version: {d}", .{ name, interface, version });
}

fn registry_handle_global_remove(data: ?*anyopaque, registry: ?*wl.wl_registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
}

fn create_shm_file() !std.posix.fd_t {
    const name = "wl_shmXXXXLHA256hb";
    const fd = try std.posix.open(name, .{.CREAT = true, .read= true, .write = true, .EXCL = true });
    return fd;
}

pub fn main() !void {
    var state: WlState = std.mem.zeroes(WlState);
    state.display = wl.wl_display_connect(null);
    if (state.display == null) std.log.err("Failed connecting", .{});
    defer wl.wl_display_disconnect(state.display);
    state.registry = wl.wl_display_get_registry(state.display);
    const registry_listener: wl.wl_registry_listener = .{
        .global = registry_handle_global,
        .global_remove = registry_handle_global_remove,
    };
    _ = wl.wl_registry_add_listener(state.registry, &registry_listener, &state);
    _ = wl.wl_display_roundtrip(state.display);
    state.surface = wl.wl_compositor_create_surface(state.compositor);
    assert(state.surface != null);
    const pool_size = (1920 * 4) * 1080 * 2; 
    _ = pool_size;

    std.log.warn("display {?}", .{state.display});
}
