const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;
const log = std.log;
const fs = std.fs;
const errno = std.posix.errno;
const Console = @import("console.zig");
const system = @import("system.zig");

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

    var console_event = linux.epoll_event{
        .data = .{ .fd = Console.IN },
        .events = std.os.linux.EPOLL.IN,
    };
    const epoll = try posix.epoll_create1(std.os.linux.EPOLL.CLOEXEC);

    try posix.epoll_ctl(
        epoll,
        std.os.linux.EPOLL.CTL_ADD,
        Console.IN,
        &console_event,
    );

    var console = try Console.init();

    var terminal_resize_signal = linux.epoll_event{
        .data = .{ .fd = console.resize_signal },
        .events = linux.EPOLL.IN,
    };

    try posix.epoll_ctl(
        epoll,
        linux.EPOLL.CTL_ADD,
        console.resize_signal,
        &terminal_resize_signal,
    );

    var state: enum { init, autobooting, user_input } = .init;
    while (true) {
        var events = [_]posix.system.epoll_event{undefined} ** (2 << 4);

        const n_events = posix.epoll_wait(epoll, &events, -1);

        var i_event: usize = 0;
        while (i_event < n_events) : (i_event += 1) {
            const event = events[i_event];

            if (event.data.fd == Console.IN) {
                if (state != .user_input) {
                    // Transition into user input mode if we aren't
                    // already there.
                    // try posix.epoll_ctl(epoll, std.os.linux.EPOLL.CTL_DEL, timer, null);
                    try console.tty.setMode(.user_input);
                    state = .user_input;

                    // Going into user input mode also means that we need to turn off the
                    // console so that it doesn't visually clobber what the user is trying to type.
                    try system.setConsole(.off);
                    console.prompt();
                }

                const outcome = try console.handleStdin() orelse continue;

                switch (outcome) {
                    .reboot => std.debug.panic("reboot is not imp", .{}),
                    .poweroff => break,
                }
            } else if (event.data.fd == console.resize_signal) {
                console.handleResize();
            } else {
                std.debug.panic("unknown event: {}", .{event});
            }
        }
    }

    console.prompt();
    while (true) {
        _ = try console.handleStdin();
    }
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
