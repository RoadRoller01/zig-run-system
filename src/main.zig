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

    var args = try std.process.argsAlloc(std.heap.page_allocator);
    const host0Dir = args[1];
    const host1Dir = args[2];
    const host2Dir = args[3];
    const argv = args[4..];

    log.info("uname: {s} {s} {s} {s} {s} {s}", std.posix.uname());

    const root = try fs.openDirAbsolute("/", .{});

    log.info("Mounting /proc and /sys", .{});
    try root.makeDir("proc");
    try root.makeDir("sys");
    try mount("none", "/proc", "proc", 0, 0);
    try mount("none", "/sys", "sysfs", 0, 0);

    const data: [*:0]const u8 = "trans=virtio,version=9p2000.L";
    log.info("Making Path {s}", .{host0Dir});
    try root.makePath(host0Dir[1..]);
    try mount("host0", host0Dir, "9p", 0, @intFromPtr(data));

    log.info("Making Path {s}", .{host1Dir});
    try root.makePath(host1Dir[1..]);
    try mount("host1", host1Dir, "9p", 0, @intFromPtr(data));

    if (host2Dir[0] != 'n') {
        log.info("Making Path {s}", .{host2Dir});
        try root.makePath(host2Dir[1..]);
        try mount("host2", host2Dir, "9p", 0, @intFromPtr(data));
    }

    log.info("Calling: {s}", .{try std.mem.join(std.heap.page_allocator, " ", argv)});
    const child = try std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = argv,
        .cwd = host0Dir,
    });

    log.info("Calling reault: {any}", .{child.term});
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

    log.err("mount({s}, {s}, {s}, {}, {x}) = {}", .{ special, dir, fstype, flags, data, ret });

    return error.mountFailed;
}

fn ls(path: []const u8) !void {
    var dir = try fs.openDirAbsolute(path, .{});
    var idir = try dir.openDir(path, .{ .iterate = true });
    defer idir.close();
    var itr = idir.iterate();

    log.info("ls {s}", .{path});

    while (try itr.next()) |entry| {
        const t = switch (entry.kind) {
            .directory => "dir",
            .file => "file",
            .block_device, .character_device => "dev",
            else => "other",
        };

        log.info("{s:5}: {s}", .{ t, entry.name });
    }
}
