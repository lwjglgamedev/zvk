# Chapter 02 - Vulkan Instance

In this chapter, we will be having our first taste of Vulkan, we will start by creating a Vulkan instance. This is the very first thing
that will be created when dealing with Vulkan. Basically, a Vulkan instance is where all the application state is glued together. In Vulkan,
there is no global state--all that information is organized around a Vulkan instance.

You can find the complete source code for this chapter [here](../../booksamples/chapter-02).

## Instance first steps

Usually you will have a single Vulkan instance for each application, but the spec allows you to have more. A potential use case for having
more than one is if you are using a legacy library that already uses Vulkan (maybe even different version) and do you not want that to
interfere with your code. You could then set up a separate instance just for your code. We will start from scratch in this book and,
therefore, we will use just a single instance.

Most of the Vulkan-related code will be placed under the module `vk` (in the `src/eng/vk` folder). In this case, we will create a new
struct named `VkInstance` to wrap all the initialization code. So let's start by coding the `create` function, which starts like this:

```zig
const builtin = @import("builtin");
const std = @import("std");
const vulkan = @import("vulkan");
const sdl3 = @import("sdl3");
const log = std.log.scoped(.vk);

pub const VkInstance = struct {
    vkb: vulkan.BaseWrapper,
    instanceProxy: vulkan.InstanceProxy,

    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        const rawProc = sdl3.vulkan.getVkGetInstanceProcAddr() catch |err| {
            std.debug.print("SDL Vulkan not available: {}\n", .{err});
            return err;
        };

        const loader: vulkan.PfnGetInstanceProcAddr = @ptrCast(rawProc);
        const vkb = vulkan.BaseWrapper.load(loader);
        ...
    }
    ...
};
```

First we get the address of the function pointer required by Vulkan to bootstrap all other Vulkan functions. It is like the entry point
that will allow us to access all the functions. We will need this to load the Vulkan base wrapper. Let's continue with the code:

```zig
pub const VkInstance = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        ...
        const appInfo = vulkan.ApplicationInfo{
            .p_application_name = "app_name",
            .application_version = @bitCast(vulkan.makeApiVersion(0, 1, 0, 0)),
            .p_engine_name = "app_name",
            .engine_version = @bitCast(vulkan.makeApiVersion(0, 1, 0, 0)),
            .api_version = @bitCast(vulkan.API_VERSION_1_3),
        };
        ...
    }
    ...
};
```

In this case we are defining our application information with the structure `ApplicationInfo` (the equivalent of `VkApplicationInfo` in the
zig Vulkan bindings we are using). We need to define the following attributes:

- `p_application_name`: It is basically just some text that will identify the application that uses this instance.
- `application_version`: The version of our application.
- `p_engine_name`: The engine name (as a null-terminated string).
- `engine_version`: The engine version.
- `api_version`: The version of the Vulkan API. This value should be the highest value of the Vulkan version that his application should use
encoded according to what is stated in Vulkan specification (major, minor and patch version). In this case we are using version `1.3.0`.

## Layers

Vulkan is a layered API.
When you read about the Vulkan core, you can think of that as the mandatory lowest level layer.
On top of that, we there are additional layers that will support useful things like validation and debugging information.
As said before, Vulkan is a low overhead API,
this means that **the driver assumes that you are using the API correctly and does not waste time in performing validations**
(error checking is minimal in the core layer).
If you want the driver to perform extensive validation, you must enable them through specific layers
(validations are handled through extension validation layers).
While we are developing, it is good advice to turn these validation layers on, to check that we are being compliant with the specification.
This can be turned off when our application is ready for delivery.

> [!NOTE]
> to use validation layers, you will need to install [Vulkan SDK](https://www.lunarg.com/vulkan-sdk/) for your platform,
> please consult the specific instructions for your platform. In fact, if you install Vulkan SDK you can use Vulkan Configurator
> to configure any validation layer you want without modifying source code.

Our `create` functions receives a boolean parameter indication is validations should be enabled or not.
If validation is requested, we will use the `VK_LAYER_KHRONOS_validation` layer. 

```zig
pub const VkInstance = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        ...
        var layer_names = try std.ArrayList([*:0]const u8).initCapacity(allocator, 2);
        defer layer_names.deinit(allocator);
        if (validate) {
            log.debug("Enabling validation. Make sure Vulkan SDK is installed", .{});
            try layer_names.append(allocator, "VK_LAYER_KHRONOS_validation");
        }
        ...
    }
    ...
};
```

## Extensions

Now that we've set up all the validation layers, we move on to extensions.

```zig
pub const VkInstance = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        ...
        var extension_names = try std.ArrayList([*:0]const u8).initCapacity(allocator, 2);
        defer extension_names.deinit(allocator);
        try extension_names.appendSlice(allocator, sdlExtensions);
        const is_macos = builtin.target.os.tag == .macos;
        if (is_macos) {
            try extension_names.append("VK_KHR_portability_enumeration");
        }

        for (extension_names.items) |value| {
            log.debug("Instance create extension: {s}", .{value});
        }
        ...
    }
    ...
};
```

First we get the name of SDL extensions that we will need to use when creating the instance. This will allow Vulkan to use the SDL window.
If we are using MacOs we need also to enable portability extension.

## Creating the instance

With all the information we can finally create the Vulkan instance:

```zig
pub const VkInstance = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        ...
        const createInfo = vulkan.InstanceCreateInfo{
            .p_application_info = &appInfo,
            .enabled_extension_count = @intCast(extension_names.items.len),
            .pp_enabled_extension_names = extension_names.items.ptr,
            .enabled_layer_count = @intCast(layer_names.items.len),
            .pp_enabled_layer_names = layer_names.items.ptr,
            .flags = .{ .enumerate_portability_bit_khr = is_macos },
        };
        const instance = try vkb.createInstance(&createInfo, null);

        const vki = try allocator.create(vulkan.InstanceWrapper);
        vki.* = vulkan.InstanceWrapper.load(instance, vkb.dispatch.vkGetInstanceProcAddr.?);
        const instanceProxy = vulkan.InstanceProxy.init(instance, vki);

        return .{ .vkb = vkb, .instanceProxy = instanceProxy };
    }
    ...
};
```

We need to complete the code with a `cleanup` function to properly free resources when we are finished:

```zig
pub const VkInstance = struct {
    ...
    pub fn cleanup(self: *VkInstance, allocator: std.mem.Allocator) !void {
        log.debug("Destroying Vulkan instance", .{});
        self.instanceProxy.destroyInstance(null);
        allocator.destroy(self.instanceProxy.wrapper);
        self.instanceProxy = undefined;
    }
};
```

## Completing the code

We will crate a new struct, named `VkCtx` which will group most relevant Vulkan context structs together. By now, it will only have a
reference to the `VkInstance` struct:

```zig
const std = @import("std");
const sdl3 = @import("sdl3");
const com = @import("com");
const vk = @import("mod.zig");

pub const VkCtx = struct {
    constants: com.common.Constants,
    vkInstance: vk.inst.VkInstance,

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants) !VkCtx {
        const vkInstance = try vk.inst.VkInstance.create(allocator, constants.validation);

        return .{
            .constants = constants,
            .vkInstance = vkInstance,
        };
    }

    pub fn cleanup(self: *VkCtx, allocator: std.mem.Allocator) !void {
        try self.vkInstance.cleanup(allocator);
    }
};
```
Finally, we can will use the Instance `VkCtx` struct in our `Render` struct, in the `create` function. We will need to call the `VkCtx`
`cleanup` function also:

```zig
pub const Render = struct {
    vkCtx: vk.ctx.VkCtx,

    pub fn cleanup(self: *Render, allocator: std.mem.Allocator) !void {
        try self.vkCtx.cleanup(allocator);
    }

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants) !Render {
        const vkCtx = try vk.ctx.VkCtx.create(allocator, constants);
        return .{
            .vkCtx = vkCtx,
        };
    }
    ...
};
```

We have added a new configuration variable to control if validation should be used or not:

```zig
pub const Constants = struct {
    ...
    validation: bool,

    pub fn load(allocator: std.mem.Allocator) !Constants {
        ...
        const constants = Constants{
            .ups = tmp.ups,
            .validation = tmp.validation,
        };
        ...
    }
};
```

We need to add a new parameter in the `res/cfg/cfg.toml` file:

```toml
validation=true
```

We will need also to modify the `Engine` type to properly instantiate the `Render` struct:

```zig
pub fn Engine(comptime GameLogic: type) type {
    ...
        pub fn create(allocator: std.mem.Allocator, gameLogic: *GameLogic, wndTitle: [:0]const u8) !Engine(GameLogic) {
            ...
            const render = try eng.rend.Render.create(allocator, engCtx.constants);
            ...
        }
    ...
};
```

And that's all! As you can see, we have to write lots of code just to set up the Vulkan instance. You can see now why Vulkan is considered
an explicit API. A whole chapter passed, and we can't even clear the screen. So, contain your expectations, since in the next chapters we
will continue writing lots of code required to set up everything. It will take some time to draw something, so please be patient. The good
news is that when everything is set up, adding incremental features to draw more complex models or to support advanced techniques should
require less amount of code. And if we do it correctly, we get a good understanding of Vulkan.

[Next chapter](../chapter-03/chapter-03.md)