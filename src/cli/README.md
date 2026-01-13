# cli

A lightweight, Commander-inspired CLI parsing library for Zig.

## Features

- **Commands & Subcommands** - Hierarchical command structure with actions
- **Flags** - Short (`-v`) and long (`--verbose`) forms, with optional values
- **Arguments** - Named arguments with required/optional support
- **Aliases** - First-class alias support (e.g., `ls` for `list`)
- **Automatic Help** - Generated at every level (`--help`, `-h`, `help`)
- **Version Handling** - Special case: `-v`, `--version`, and `version` all work
- **Fluent Builder API** - Chain `.addFlag()`, `.addArgument()`, `.addSubcommand()`
- **Flexible Parsing** - Combined flags (`-abc`), equals syntax (`--out=file`), `--` separator

## Usage

```zig
const std = @import("std");
const cli = @import("cli/cli.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var app = cli.Cli.init(allocator, .{
        .name = "myapp",
        .description = "My application",
        .version = "1.0.0",
    });
    defer app.deinit();

    // Add commands with fluent API
    _ = app.addCommand(.{
        .name = "install",
        .description = "Install a package",
        .action = installAction,
    }).addArgument(.{
        .name = "package",
        .description = "Package to install",
        .required = true,
    }).addFlag(.{
        .long = "force",
        .short = 'f',
        .description = "Force reinstall",
    });

    _ = app.addCommand(.{
        .name = "list",
        .aliases = &.{"ls"},
        .description = "List installed packages",
        .action = listAction,
    });

    // Parse and run
    app.run() catch |err| switch (err) {
        error.UserError => std.process.exit(1),
        else => return err,
    };
}

fn installAction(ctx: cli.Context) !void {
    const package = ctx.arg("package").?;
    const force = ctx.flag("force");
    // ...
}

fn listAction(ctx: cli.Context) !void {
    // ...
}
```

## API Reference

### Cli

```zig
const app = cli.Cli.init(allocator, .{
    .name = "myapp",           // Required: app name
    .description = "...",      // Optional: shown in help
    .version = "1.0.0",        // Optional: enables -v/--version
});
defer app.deinit();

_ = app.addCommand(opts);      // Returns *Command for chaining
app.run();                     // Parse args and dispatch
app.runWithArgs(args);         // Parse explicit args (for testing)
```

### Command

```zig
const cmd = app.addCommand(.{
    .name = "install",
    .aliases = &.{"i"},        // Optional
    .description = "...",
    .action = myAction,        // fn(Context) !void
});

// Fluent API - all return *Command
cmd.addFlag(.{ ... });
cmd.addArgument(.{ ... });
cmd.addSubcommand(.{ ... });   // Returns the new subcommand
```

### Flag

```zig
cmd.addFlag(.{
    .long = "output",          // Required: --output
    .short = 'o',              // Optional: -o
    .description = "...",
    .takes_value = true,       // --output=file or --output file
    .default = "out.txt",      // Default if not provided
});
```

### Argument

```zig
cmd.addArgument(.{
    .name = "file",
    .description = "...",
    .required = true,          // Default: true
});
```

### Context

Passed to action functions:

```zig
fn myAction(ctx: cli.Context) !void {
    ctx.flag("verbose")              // bool: is flag present?
    ctx.flagValue("output")          // ?[]const u8: flag's value
    ctx.arg("file")                  // ?[]const u8: argument by name
    ctx.args()                       // []const []const u8: all arguments
    ctx.allocator                    // std.mem.Allocator
}
```

## Parser Behavior

| Input | Behavior |
|-------|----------|
| `--verbose` | Boolean flag |
| `--output file` | Flag with value (space) |
| `--output=file` | Flag with value (equals) |
| `-v` | Short boolean flag |
| `-o file` | Short flag with value |
| `-o=file` | Short flag with value (equals) |
| `-abc` | Combined: `-a -b -c` |
| `--` | Stop flag parsing (rest are arguments) |

## Help Output

```
$ myapp --help
myapp v1.0.0 - My application

Usage: myapp <command> [options]

Commands:
  install       Install a package
  list, ls      List installed packages

Flags:
  -h, --help        Show this help
  -v, --version     Print version

$ myapp install --help
Install a package

Usage: myapp install <package> [options]

Arguments:
  package       Package to install

Flags:
  -f, --force       Force reinstall
  -h, --help        Show this help
```

## File Structure

```
cli/
  cli.zig       # Main Cli struct, public entry point
  command.zig   # Command struct and builder
  flag.zig      # Flag and Argument definitions
  parser.zig    # Argument parsing logic
  help.zig      # Help text generation
  tests.zig     # Test suite
  README.md     # This file
```
