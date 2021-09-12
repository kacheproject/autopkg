# Autopkg
Autopkg is a library works with zig build system to simplify package management.

Featured:
- Declarative experience
- Programable package
- Nested directory structure support
- Working with C headers and sources

Zig build system lack of these important QoL features. This library is intented to provide them.

## Basic Usage

This library is zero-dependency. Just copy the `autopkg.zig` or refer by git submodule.

In the `build.zig` of the package `./package` you need to work with:
````zig
const autopkg = @import("autopkg/autopkg.zig");

/// `name` is the name you name.
/// `path` is relative path to this library directory.
pub fn package(name: []const u8, path: []const u8) autopkg.AutoPkgI {
    return autopkg.genExport(.{
        .name = name,
        .path = path,
        .rootSrc = "src/main.zig", // Use empty string if you don't have zig source file.
        // You can specify more options about libraries and C sources, see source code autopkg.zig (don't worry, the code is short). All options works locally.
    });
}
````

In the `build.zig` in your main package `.`:
````zig
const std = @import("std");
const autopkg = @import("autopkg/autopkg.zig");

pub fn package(name: []const u8, path: []const u8) autopkg.AutoPkgI {
    const thePackageYouNeed = @import("./package/build.zig");
    return autopkg.genExport(.{
        .name = name,
        .path = path,
        .rootSrc = "src/main.zig",
        .dependencies = &.{
            autopkg.accept(thePackageYouNeed.package("package", "./package")),
        },
    });
}

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const mainPackage = autopkg.accept(package("main", "."));
    var resolvedPackage = mainPackage.resolve(".", b.allocator) catch unreachable;
    const lib = resolvedPackage.addBuild(b);
    lib.setBuildMode(mode);
    lib.install();
}
````

The `package()` function is not limited to the two parameters specified here. You can return alternative version of `AutoPkgI` depends on the arguments or even the environment.

If you don't want to specify an auto package and just want to depend on one using that, you could use `AutoPkg.dependedBy()`:

````zig
const thePackageYouWorkWith = @import("./package/build.zig");
const autopkg = @import("autopkg/autopkg.zig");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const resolvedThePackage = autopkg.accept(thePackageYouWorkWith.package("package", "./package")).resolve(".", b.allocator) catch unreachable; // You need to resolve the package first
    const lib = b.addStaticLibrary("mypackage", "src/main.zig");
    resolvedThePackage.dependedBy(lib);
    lib.setBuildMode(mode);
    lib.install();
}
````

## Contributing

Suggestion/Pull Request welcome!

### Maintainer

`Rubicon Rowe <l1589002388 & gmail.com>`

## License
`Apache-2.0`.
