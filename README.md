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

    var mainPackage = autopkg.accept(package("main", "."));
    defer mainPackage.deinit();
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

### Inside Memory Management
Autopkg will do multiple copy in heap to make sure the infomation alive:

- `genExport`
- `AutoPkg.resolve`

and `AutoPkg.deinit` will call `AutoPkg.deinit` of every `AutoPkg` it refered.

As the fact of `std.build.Builder.allocator` is an ArenaAllocator, you don't need to deinitilise the structure if you use with that (Just like above exmaple).

Internally autopkg uses a `std.heap.GeneralPurposeAllocator` to allocate memory when calling `genExport()`.

Remember: unrefered packages will cause memory leak!

### Tests

Autopkg can automatically handle tests dependencies for you, and you can test the packages you work with if they set `doNotTest` to false (which is the default) or their autopkg is older versions does not support tests.

If you will publish the package, it's recommended to set `doNotTest` as `true`.

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
        .doNotTest = false, // though it's by default.
    });
}

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    var mainPackage = autopkg.accept(package("main", "."));
    defer mainPackage.deinit();
    var resolvedPackage = mainPackage.resolve(".", b.allocator) catch unreachable;
    const lib = resolvedPackage.addBuild(b);
    lib.setBuildMode(mode);
    lib.install();
    
    var testStep = b.addStep("test" , "Run all tests");
    testStep.dependOn(resolvedPackage.addTest(b, mode, target));
}
````

## Contributing

Suggestion/Pull Request welcome!

### Maintainer

`Rubicon Rowe <l1589002388 & gmail.com>`

## License
`Apache-2.0`.
