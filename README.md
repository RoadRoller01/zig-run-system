Like `addRunArtifact` but use qemu-system-_instead of qemu-_ or qemu-user,
the result of that better support most syscalls unlike qemu-user
Note: not all syscalls are supported. You can request one by editing `images/.config.arch`
and compile it(:, or I might create CI action to do it idk. Feel free to add one(:

Example usage:

```zig
    if (cli.rootModuleTarget().cpu.arch == b.graph.host.result.cpu.arch and
        cli.rootModuleTarget().os.tag == b.graph.host.result.os.tag)
    {
        const run_cmd = b.addRunArtifact(cli);

        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    } else {
        var argv = std.ArrayList([]const u8).init(b.allocator);
        argv.append("./zig-out/bin/theNameOfCli") catch unreachable;
        if (b.args) |args| {
            argv.appendSlice(args) catch unreachable;
        }
        const run_cmd = @import("zig_run_system").addRunSystem(b, target, argv.items);

        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }
```
