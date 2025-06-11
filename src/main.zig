const std = @import("std");
const linux = std.os.linux;
const log = std.log;
const fs = std.fs;
const errno = std.posix.errno;
const MS = std.os.linux.MS;

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

    log.info("uname: {s} {s} {s} {s} {s} {s}", std.posix.uname());

    const root = try fs.openDirAbsolute("/", .{});

    log.info("Mounting /proc, /sys, /dev and /run", .{});
    try fs.cwd().makePath("/proc");
    try mount("proc", "/proc", "proc", MS.NOSUID | MS.NODEV | MS.NOEXEC, 0);

    try fs.cwd().makePath("/sys");
    try mount("sysfs", "/sys", "sysfs", MS.NOSUID | MS.NODEV | MS.NOEXEC | MS.RELATIME, 0);
    // try mount("securityfs", "/sys/kernel/security", "securityfs", MS.NOSUID | MS.NODEV | MS.NOEXEC | MS.RELATIME, 0);
    // try mount("debugfs", "/sys/kernel/debug", "debugfs", MS.NOSUID | MS.NODEV | MS.NOEXEC | MS.RELATIME, 0);

    try fs.cwd().makePath("/dev");
    try mount("devtmpfs", "/dev", "devtmpfs", MS.SILENT | MS.NOSUID | MS.NOEXEC, 0);

    try fs.cwd().makePath("/run");
    try mount("tmpfs", "/run", "tmpfs", MS.NOSUID | MS.NODEV, 0);

    const data: [*:0]const u8 = "trans=virtio,version=9p2000.L";
    log.info("Making Path {s}", .{args[1]});
    try root.makePath(args[1][1..]);
    try mount("host0", args[1], "9p", 0, @intFromPtr(data));

    log.info("Making Path {s}", .{args[2]});
    try root.makePath(args[2][1..]);
    try mount("host1", args[2], "9p", 0, @intFromPtr(data));

    if (args[3][0] != 'n') {
        log.info("Making Path {s}", .{args[3]});
        try root.makePath(args[3][1..]);
        try mount("host2", args[3], "9p", 0, @intFromPtr(data));
    }

    log.info("Calling: {s}", .{try std.mem.join(std.heap.page_allocator, " ", args[4..])});

    try (try fs.openDirAbsolute(args[1], .{})).setAsCwd();

    var child = std.process.Child.init(args[4..], std.heap.page_allocator);
    const term = try child.spawnAndWait();

    log.info("Calling reault : {any}", .{term});
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
