const std = @import("std");
const linux = std.os.linux;
const log = std.log;
const fs = std.fs;
const errno = std.posix.errno;

pub fn main() !void {
    // const allo = std.heap.page_allocator;
    const is_init = linux.getpid() == 1;

    if (is_init) {
        log.info("Zig is running as init!", .{});
    } else {
        log.info("Zig isn't running as init.", .{});
        log.info("Quiting..", .{});
        return;
    }

    log.info("uname: {s} {s} {s} {s} {s} {s}", std.posix.uname());

    const root = try fs.openDirAbsolute("/", .{});

    log.info("Mounting /proc and /sys", .{});
    try root.makeDir("proc");
    try root.makeDir("sys");
    try mount("none", "/proc", "proc", 0, 0);
    try mount("none", "/sys", "sysfs", 0, 0);
}

fn mount(
    special: [*:0]const u8,
    dir: [*:0]const u8,
    fstype: [*:0]const u8,
    flags: u32,
    data: usize,
) !void {
    const ret =
        errno(linux.mount(special, dir, fstype, flags, data));

    if (ret == std.posix.E.SUCCESS)
        return;

    log.err("mount({s}, {s}, {s}, {}, {}) = {}", .{ special, dir, fstype, flags, data, ret });

    return error.mountFailed;
}
