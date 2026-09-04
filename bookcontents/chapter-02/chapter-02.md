# Chapter 02 - Vulkan Instance

In this chapter, we will be having our first taste of Vulkan by creating a Vulkan instance. This is the very first thing that will be
created when dealing with Vulkan. Basically, a Vulkan instance is where all the application state is grouped together. In Vulkan, there is
no global state--all that information is organized around a Vulkan instance.

You can find the complete source code for this chapter [here](../../booksamples/chapter-02).

## Instance first steps

Usually you will have a single Vulkan instance for each application, but the spec allows you to have more. A potential use case for having
more than one is if you are using a legacy library that already uses Vulkan (possibly even a different Vulkan version) and you do not want
that to interfere with your code. You could then set up a separate instance just for your code. We will start from scratch in this book and,
therefore, we will use just a single instance.

Most of the Vulkan-related code will be placed in the `vk` module (in the `src/eng/vk` folder). In this case, we will create a new
struct named `VkInstance` to wrap all the initialization code. So let's start by coding the `create` function, which starts like this:

**File: src/eng/vk/vkInstance.zig**
```zig
const builtin = @import("builtin");
const std = @import("std");
const vulkan = @import("vulkan");
const sdl3 = @import("sdl3");
const log = std.log.scoped(.vk);

const VALIDATION_LAYER = "VK_LAYER_KHRONOS_validation";

pub const VkInstance = struct {
    vkb: vulkan.BaseWrapper,
    debugMessenger: ?vulkan.DebugUtilsMessengerEXT = null,    
    instanceProxy: vulkan.InstanceProxy,

    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        const rawProc = sdl3.vulkan.getVkGetInstanceProcAddr() catch |err| {
            log.err("Vulkan not available: {}\n", .{err});
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

**File: src/eng/vk/vkInstance.zig**
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
- `api_version`: The version of the Vulkan API. This value should be the highest value of the Vulkan version that this application should
use encoded according to what is stated in Vulkan specification (major, minor and patch version). In this case we are using version `1.3.0`.

## Extensions

A Vulkan extension is a piece of functionality that is not part of the core Vulkan specification, but can be added to the API optionally.
You can think about extensions like plugins. As the Vulkan standard evolve, some of the extensions have been included in the core API
so make sure you check this if you plan to include a new one. Let's review which extensions we will use in the code:

**File: src/eng/vk/vkInstance.zig**
```zig
pub const VkInstance = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        ...
        var extensionNames = try std.ArrayList([*:0]const u8).initCapacity(allocator, 2);
        defer extensionNames.deinit(allocator);
        const sdlExtensions = try sdl3.vulkan.getInstanceExtensions();
        try extensionNames.appendSlice(allocator, sdlExtensions);
        const is_macos = builtin.target.os.tag == .macos;
        if (is_macos) {
            try extensionNames.append("VK_KHR_portability_enumeration");
        }
        ...
    }
    ...
};
```

First we get the name of SDL extensions that we will need to use when creating the instance. This will allow Vulkan to use the SDL window.
If we are using macOS we need also to enable portability extension (`VK_KHR_portability_enumeration`).

## Layers

Vulkan is a layered API. When you read about the Vulkan core, you can think of it as the mandatory lowest level layer. On top of that,
there are additional layers that will support useful things like validation and debugging information. As said before, Vulkan is a low
overhead API, this means that **the driver assumes that you are using the API correctly and does not waste time in performing validations**
(error checking is minimal in the core layer). If you want the driver to perform extensive validation, you must enable them through specific
layers (validation is handled through validation layers implemented as extension). While we are developing, it is good advice to turn these
validation layers on, to check that we are being compliant with the specification. This can be turned off when our application is ready for
delivery.

> [!NOTE]
> to use validation layers, you will need to install [Vulkan SDK](https://www.lunarg.com/vulkan-sdk/) for your platform,
> please consult the specific instructions for your platform. In fact, if you install Vulkan SDK you can use Vulkan Configurator
> to configure any validation layer you want without modifying source code.
> In Linux you will need to create one environment variables if you manually install the SDK: `VK_LAYER_PATH` which should point
> to the directory where the validation layers are define: `$VULKAN_SDK/x86_64/share/vulkan/explicit_layer.d` (`VULKAN_SDK` should
> have the path of the base directory of the Vulkan SDK)

Our `create` function receives a boolean parameter indicating if validation should be enabled or not. If validation is requested, we will
use the `VK_LAYER_KHRONOS_validation` layer (defined in the constant `VALIDATION_LAYER`). In addition to that, if we support validation
we will add a new layer to be able to use a callback that will be invoked whenever a validation event occurs.

**File: src/eng/vk/vkInstance.zig**
```zig
pub const VkInstance = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        ...
        var layerNames = try std.ArrayList([*:0]const u8).initCapacity(allocator, 2);
        defer layerNames.deinit(allocator);

        const supValidation = try supportsValidation(allocator, &vkb);
        if (validate) {
            if (supValidation) {
                log.debug("Enabling validation", .{});
                try layerNames.append(allocator, VALIDATION_LAYER);
                try extensionNames.append(allocator, vulkan.extensions.ext_debug_utils.name);
            } else {
                log.debug("Validation layer not supported. Make sure Vulkan SDK is installed", .{});
            }
        }
        for (extensionNames.items) |value| {
            log.debug("Instance create extension: {s}", .{value});
        }
        ...
    }
    ...
};
```

The `supportsValidation` function is defined like this:

**File: src/eng/vk/vkInstance.zig**
```zig
pub const VkInstance = struct {
    ...
    fn supportsValidation(allocator: std.mem.Allocator, vkb: *const vulkan.BaseWrapper) !bool {
        var result = false;
        var numLayers: u32 = 0;
        _ = try vkb.enumerateInstanceLayerProperties(&numLayers, null);

        const layers = try allocator.alloc(vulkan.LayerProperties, numLayers);
        defer allocator.free(layers);
        _ = try vkb.enumerateInstanceLayerProperties(&numLayers, layers.ptr);

        for (layers) |layerProps| {
            const layerName = std.mem.sliceTo(&layerProps.layer_name, 0);
            log.debug("Supported layer [{s}]", .{layerName});
            if (std.mem.eql(u8, layerName, VALIDATION_LAYER)) {
                result = true;
            }
        }

        return result;
    }
};
```

We first get the number of supported layers by calling the `enumerateInstanceLayerProperties` function which just a pointer to an
`u32` variable to get the number of supported layers. After that, we call again the `enumerateInstanceLayerProperties` function to get
the layers themselves passing a preallocated array. If we find the validation layer, we can enable it.

## Creating the instance

With all the information we can finally create the Vulkan instance:

**File: src/eng/vk/vkInstance.zig**
```zig
pub const VkInstance = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        ...
        const createInfo = vulkan.InstanceCreateInfo{
            .p_application_info = &appInfo,
            .enabled_extension_count = @intCast(extensionNames.items.len),
            .pp_enabled_extension_names = extensionNames.items.ptr,
            .enabled_layer_count = @intCast(layerNames.items.len),
            .pp_enabled_layer_names = layerNames.items.ptr,
            .flags = .{ .enumerate_portability_bit_khr = is_macos },
        };
        const instance = try vkb.createInstance(&createInfo, null);

        const vki = try allocator.create(vulkan.InstanceWrapper);
        vki.* = vulkan.InstanceWrapper.load(instance, vkb.dispatch.vkGetInstanceProcAddr.?);
        const instanceProxy = vulkan.InstanceProxy.init(instance, vki);
        ...
    }
    ...
};
```

If validation is enabled and supported we need to create the debug messenger extension:

**File: src/eng/vk/vkInstance.zig**
```zig
pub const VkInstance = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        ...
        if (validate and supValidation) {
            debugMessenger = try instanceProxy.createDebugUtilsMessengerEXT(&.{
                .message_severity = .{
                    .warning_bit_ext = true,
                    .error_bit_ext = true,
                },
                .message_type = .{
                    .general_bit_ext = true,
                    .validation_bit_ext = true,
                    .performance_bit_ext = true,
                },
                .pfn_user_callback = &VkInstance.debugUtilsMessengerCallback,
                .p_user_data = null,
            }, null);
        }
        ...
    }
    ...
};    
```

The `message_severity` attribute is a composition of flags which triggers when the debug callback should be invoked. We are interested
in just errors and warnings, but you can enable information and verbose levels. The `message_type` is used to filter the type of
messages we are interested in. We will activate validation messages, general information and performance ones. Finally we will set up
the callback to be invoked in the `pfn_user_callback` attribute. The function set as a callback is defined like this:

**File: src/eng/vk/vkInstance.zig**
```zig
pub const VkInstance = struct {
    ...
    fn debugUtilsMessengerCallback(
        severity: vulkan.DebugUtilsMessageSeverityFlagsEXT,
        msgType: vulkan.DebugUtilsMessageTypeFlagsEXT,
        callback_data: ?*const vulkan.DebugUtilsMessengerCallbackDataEXT,
        _: ?*anyopaque,
    ) callconv(.c) vulkan.Bool32 {
        _ = msgType;
        const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";
        if (severity.error_bit_ext) {
            log.err("{s}", .{message});
        } else if (severity.warning_bit_ext) {
            log.warn("{s}", .{message});
        } else if (severity.info_bit_ext) {
            log.info("{s}", .{message});
        } else {
            log.debug("{s}", .{message});
        }
        return vulkan.Bool32.false;
    }
    ...
};
```

We just debug the message according to the severity level. We return a boolean stating if the process should be aborted
(`vulkan.Bool32.true`) or not (`vulkan.Bool32.false`).

Back to the `create` function, with all that information we just create the `VkInstance` structure and return it:

**File: src/eng/vk/vkInstance.zig**
```zig
pub const VkInstance = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, validate: bool) !VkInstance {
        ...
        return .{
            .vkb = vkb,
            .debugMessenger = debugMessenger,
            .instanceProxy = instanceProxy,
        };
    }
    ...
};
```

We need to complete the code with a `cleanup` function to properly free resources when we are finished:

**File: src/eng/vk/vkInstance.zig**
```zig
pub const VkInstance = struct {
    ...
    pub fn cleanup(self: *VkInstance, allocator: std.mem.Allocator) void {
        log.debug("Destroying Vulkan instance", .{});
        if (self.debugMessenger) |dbg| {
            self.instanceProxy.destroyDebugUtilsMessengerEXT(dbg, null);
        }
        self.instanceProxy.destroyInstance(null);
        allocator.destroy(self.instanceProxy.wrapper);
        self.instanceProxy = undefined;
    }
};
```

## Completing the code

We will create a new struct, named `VkCtx` which will group most relevant Vulkan context structs together. By now, it will only have a
reference to the `VkInstance` struct:

**File: src/eng/vk/vkCtx.zig**
```zig
const std = @import("std");
const sdl3 = @import("sdl3");
const com = @import("com");
const vk = @import("mod.zig");

pub const VkCtx = struct {
    constants: com.common.Constants,
    vkInstance: vk.inst.VkInstance,

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants) !VkCtx {
        var vkInstance = try vk.inst.VkInstance.create(allocator, constants.validation);
        vkInstance.cleanup(allocator);



        return .{
            .constants = constants,
            .vkInstance = vkInstance,
        };
    }

    pub fn cleanup(self: *VkCtx, allocator: std.mem.Allocator) void {
        self.vkInstance.cleanup(allocator);
    }
};
```
Finally, we can use the Instance `VkCtx` struct in our `Render` struct, in the `create` function. We will need to call the `VkCtx`
`cleanup` function also:

**File: src/eng/vk/vkCtx.zig**
```zig
pub const Render = struct {
    vkCtx: vk.ctx.VkCtx,

    pub fn cleanup(self: *Render, allocator: std.mem.Allocator) void {
        self.vkCtx.cleanup(allocator);
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

**File: src/eng/vk/vkCtx.zig**
```zig
pub const Constants = struct {
    ...
    validation: bool,

    pub fn load(allocator: std.mem.Allocator, io: std.Io) !Constants {
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

**File: res/cfg/cfg.toml**
```toml
validation=true
```

We will also need to modify the `Engine` type to properly instantiate the `Render` struct:

**File: src/eng/render.zig**
```zig
pub fn Engine(comptime GameLogic: type) type {
    ...
        pub fn create(allocator: std.mem.Allocator, io: std.Io, gameLogic: *GameLogic, wndTitle: [:0]const u8) !Engine(GameLogic) {
            ...
            const render = try eng.rend.Render.create(allocator, engCtx.constants);
            ...
        }
    ...
};
```

And that's all! As you can see, we have to write lots of code just to set up the Vulkan instance. You can see now why Vulkan is considered
an explicit API. A whole chapter passed, and we can't even clear the screen. So, manage your expectations, since in the next chapters we
will continue writing lots of code required to set up everything. It will take some time to draw something, so please be patient. The good
news is that when everything is set up, adding incremental features to draw more complex models or to support advanced techniques should
require less code. And if we do it correctly, we get a good understanding of Vulkan.

[Back to Table of Contents](../README.md)

[Previous chapter](../chapter-01/chapter-01.md) | [Next chapter](../chapter-03/chapter-03.md)