//compile with zig build

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Resolve OS tag
    const is_windows = target.result.os.tag == .windows;

    // ==========================================
    // 1. Setup Configuration & Macros
    // ==========================================

    // Dynamically get the version via git, falling back to "0.1.0"
    const git_version: []const u8 = version: {
        var exit_code: u8 = 0;

        // runAllowFail returns stdout on success, or error if exit code != 0
        const output = b.runAllowFail(
            &[_][]const u8{ "git", "describe", "--tags", "--always", "--dirty" },
            &exit_code,
            .ignore, // or .inherit to see stderr during build
        ) catch break :version "0.1.0";

        // Trim whitespace/newlines from git output
        break :version std.mem.trim(u8, output, " \r\n\t");
    };
    // const git_version:[]const u8 = version: {
    //     const result = std.process.Child.run(.{
    //         .allocator = b.allocator,
    //         .argv = &[_][]const u8{ "git", "describe", "--tags", "--always", "--dirty" },
    //     }) catch break :version "0.1.0";

    //     if (result.term == .Exited and result.term.Exited == 0) {
    //         break :version std.mem.trim(u8, result.stdout, " \r\n");
    //     }
    //     break :version "0.1.0";
    // };

    // Installation prefix (defaults to /usr/local)
    const prefix = b.option([]const u8, "prefix", "Installation prefix") orelse "/usr/local";

    // As per build.bat, Windows uses ".", whereas Unix uses the share folder
    const share_dir = if (is_windows) "." else b.fmt("{s}/share/zenc", .{prefix});

    // C Flags
    var cflags: std.ArrayList([]const u8) = .empty;
    defer cflags.deinit(b.allocator);
    cflags.appendSlice(b.allocator, &[_][]const u8{
        "-Wall",
        "-Wextra",
        "-Wshadow",
        "-g",
        b.fmt("-DZEN_VERSION=\"{s}\"", .{git_version}),
        b.fmt("-DZEN_SHARE_DIR=\"{s}\"", .{share_dir}),
    }) catch @panic("OOM");

    const include_dirs = &[_][]const u8{
        "src",
        "src/ast",
        "src/parser",
        "src/codegen",
        "plugins",
        "src/zen",
        "src/utils",
        "src/lexer",
        "src/analysis",
        "src/lsp",
        "src/diagnostics",
        "std/third-party/tre/include",
    };

    // ==========================================
    // 2. Main Executable Target (zc / zc.exe)
    // ==========================================
    const exe = b.addExecutable(.{
        .name = "zc",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    for (include_dirs) |dir| {
        exe.root_module.addIncludePath(b.path(dir));
    }

    const srcs = &[_][]const u8{
        "src/main.c",
        "src/parser/parser_core.c",
        "src/parser/parser_expr.c",
        "src/parser/parser_stmt.c",
        "src/parser/parser_type.c",
        "src/parser/parser_utils.c",
        "src/parser/parser_decl.c",
        "src/parser/parser_struct.c",
        "src/ast/ast.c",
        "src/codegen/codegen.c",
        "src/codegen/codegen_stmt.c",
        "src/codegen/codegen_decl.c",
        "src/codegen/codegen_main.c",
        "src/codegen/codegen_utils.c",
        "src/utils/utils.c",
        "src/utils/colors.c",
        "src/utils/cmd.c",
        "src/platform/os.c",
        "src/platform/console.c",
        "src/platform/dylib.c",
        "src/utils/config.c",
        "src/diagnostics/diagnostics.c",
        "src/lexer/token.c",
        "src/analysis/typecheck.c",
        "src/analysis/move_check.c",
        "src/analysis/const_fold.c",
        "src/lsp/json_rpc.c",
        "src/lsp/lsp_main.c",
        "src/lsp/lsp_analysis.c",
        "src/lsp/lsp_semantic.c",
        "src/lsp/lsp_index.c",
        "src/lsp/lsp_project.c",
        "src/lsp/cJSON.c",
        "src/zen/zen_facts.c",
        "src/repl/repl.c",
        "src/plugins/plugin_manager.c",
        "std/third-party/tre/lib/regcomp.c",
        "std/third-party/tre/lib/regerror.c",
        "std/third-party/tre/lib/regexec.c",
        "std/third-party/tre/lib/tre-ast.c",
        "std/third-party/tre/lib/tre-compile.c",
        "std/third-party/tre/lib/tre-filter.c",
        "std/third-party/tre/lib/tre-match-approx.c",
        "std/third-party/tre/lib/tre-match-backtrack.c",
        "std/third-party/tre/lib/tre-match-parallel.c",
        "std/third-party/tre/lib/tre-mem.c",
        "std/third-party/tre/lib/tre-parse.c",
        "std/third-party/tre/lib/tre-stack.c",
        "std/third-party/tre/lib/xmalloc.c",
    };

    exe.root_module.addCSourceFiles(.{
        .files = srcs,
        .flags = cflags.items,
    });

    // Automatically pulls in system standard headers
    exe.root_module.link_libc = true;

    // OS-specific library linking natively mapped from both Makefile and build.bat
    if (is_windows) {
        exe.root_module.linkSystemLibrary("ws2_32", .{});
    } else {
        exe.root_module.linkSystemLibrary("m", .{});
        exe.root_module.linkSystemLibrary("pthread", .{});
        if (target.result.os.tag == .linux) {
            exe.root_module.linkSystemLibrary("dl", .{});
        }
    }

    // Installs `zc.exe` into zig-out/bin/
    b.installArtifact(exe);
}

// ==========================================
// 3. Plugins (Shared Libraries)
// ==========================================
// These compile to .dll on Windows, and .so on Linux/Mac
//const plugins = &[_];
