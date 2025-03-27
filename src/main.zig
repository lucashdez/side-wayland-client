const std = @import("std");
const wl = @cImport({
    @cInclude("wayland-client-protocol.h");
    @cInclude("xdg-shell-client.h");
});
const assert = std.debug.assert;

const WlState = struct {
    display: ?*wl.wl_display,
    registry: ?*wl.wl_registry,
    compositor: ?*wl.wl_compositor,
    surface: ?*wl.wl_surface,
    shm: ?*wl.wl_shm,
    shm_pool: ?*wl.wl_shm_pool,
    xdg_wm_base: ?*wl.xdg_wm_base,
    xdg_surface: ?*wl.xdg_surface,
    xdg_toplevel: ?*wl.xdg_toplevel,
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
        if (std.mem.eql(u8, std.mem.span(interface), "xdg_wm_base")) {
            state.xdg_wm_base = @ptrCast(wl.wl_registry_bind(registry, name, &wl.xdg_wm_base_interface, version));
            const xdg_wm_base_listener = wl.xdg_wm_base_listener {.ping = xdg_wm_base_ping};
            _ = wl.xdg_wm_base_add_listener(state.xdg_wm_base, &xdg_wm_base_listener, state);
            std.log.debug("[DONE] binded xdg_wm_base", .{});
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
    const fd = try std.posix.open(name, .{ .CREAT = true, .EXCL = true, .APPEND = true }, 600);
    return fd;
}

fn xdg_wm_base_ping(data: ?*anyopaque, base: ?*wl.xdg_wm_base, serial: u32) callconv(.c) void {
    _ = data;
    wl.xdg_wm_base_pong(base, serial);
}

fn draw_frame(state: *WlState) !?*wl.wl_buffer {

    const pool_size = ((1920 * 4) * 1080 * 2) * 4;

    state.shm_pool = wl.wl_shm_create_pool(state.shm, 0, pool_size);
    const pool_data = try std.posix.mmap(null, pool_size, std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .ANONYMOUS = true, .TYPE = .SHARED }, 0, 0);

    const buffer: ?*wl.wl_buffer = wl.wl_shm_pool_create_buffer(state.shm_pool, 0, 1920, 1080, 4, wl.WL_SHM_FORMAT_XRGB8888);

    const pixels: []u32 = @as([*]u32, @ptrCast(pool_data.ptr))[0..pool_data.len];

    for (0..1080) |i| {
        for (0..1920) |j| {
            if ((i + j / 8 * 8) % 16 < 8) {
                pixels[i * 1920 + j] = 0xFF666666;
            } else {
                pixels[i * 1920 + j] = 0xFFEEEEEE;
            }
        }
    }

    return buffer;
}

fn xdg_surface_configure(data: ?*anyopaque, xdg_surface: ?*wl.xdg_surface, serial: u32) callconv(.c) void {
    if (data) |data_ptr| {
        const state: *WlState = @alignCast(@ptrCast(data_ptr));
        _ = wl.xdg_surface_ack_configure(xdg_surface, serial);

        const buffer = draw_frame(state) catch null;
        wl.wl_surface_attach(state.surface, buffer, 0, 0);
        wl.wl_surface_commit(state.surface);
    }
}


pub fn main() !void {
    var state: WlState = std.mem.zeroes(WlState);
    state.display = wl.wl_display_connect(null);
    if (state.display == null) std.log.err("Failed connecting", .{});
    std.log.warn("display {?}", .{state.display});
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

    state.xdg_surface = wl.xdg_wm_base_get_xdg_surface(state.xdg_wm_base, state.surface);
    assert(state.xdg_surface != null);

    //TODO: this
    const xdg_surface_listener = wl.xdg_surface_listener {
        .configure = xdg_surface_configure,
    };
    _ = wl.xdg_surface_add_listener(state.xdg_surface, &xdg_surface_listener, &state);

    state.xdg_toplevel = wl.xdg_surface_get_toplevel(state.xdg_surface);
    wl.xdg_toplevel_set_title(state.xdg_toplevel, "something");
    wl.wl_surface_commit(state.surface);


    while (wl.wl_display_dispatch(state.display) != 0) {
        wl.wl_surface_damage(state.surface, 0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
    }
}
