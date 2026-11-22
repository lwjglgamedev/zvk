# Chapter 03 - Physical, Logical devices and Surface

In this chapter we will progress in the definition of the Vulkan structures required to render a 3D scene. Specifically, we will set up the
Physical and Logical devices and a Surface.

You can find the complete source code for this chapter [here](../../booksamples/chapter-03).

## Physical device selection

A physical device represents any piece of hardware that provides a complete implementation of the Vulkan interface (usually a physical GPU).
You can have several Vulkan-capable physical devices (you may have more than one GPU), but you will usually just use one (we will not be
dealing with multi-GPU rendering here). As a side note, as we progress through this book we will define many concepts. In order to help you
in understanding the relationship between all of them, we will be filling up a diagram. Here you can find the diagram that shows the
elements described so far.

![UML Diagram](rc03-yuml-01.svg)

So let's go back to coding and start by encapsulating all the code for selecting and creating a physical device in a new struct named
`VkPhysDevice` (in the file `src/eng/vk/vkPhysDevice.zig`, remember to update the `mod.zig` file to include it:
`pub const phys = @import("vkPhysDevice.zig");`). It starts like this:

**File: src/eng/vk/vkPhysDevice.zig**
```zig
const std = @import("std");
const vulkan = @import("vulkan");
const com = @import("com");
const vk = @import("mod.zig");

const log = std.log.scoped(.vk);
pub const reqExtensions = [_][*:0]const u8{vulkan.device_extensions.khr_swapchain.name};

const QueuesInfo = struct {
    graphics_family: u32,
    present_family: u32,
};

pub const VkPhysDevice = struct {
    features: vulkan.PhysicalDeviceFeatures,
    pdev: vulkan.PhysicalDevice,
    props: vulkan.PhysicalDeviceProperties,
    queuesInfo: QueuesInfo,
    memProps: vulkan.PhysicalDeviceMemoryProperties,
    ...
};
```

The `QueuesInfo` struct will hold the family indices of the queues used to submit graphics or present commands (more on this later). The
`VkPhysDevice` struct stores the features of the physical device (`features`), a reference to the Vulkan physical device (`pdev`), its
properties (`props`), the queues information and the device memory properties (`memProps`). It provides a `create` function which
instantiates this struct and that starts like this:

**File: src/eng/vk/vkPhysDevice.zig**
```zig
pub const VkPhysDevice = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants, instance: vulkan.InstanceProxy, vkSurface: vk.surf.VkSurface) !VkPhysDevice {
        const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
        defer allocator.free(pdevs);

        var list = try std.ArrayList(VkPhysDevice).initCapacity(allocator, 1);
        defer list.deinit(allocator);
        ...
    }
    ...
};
```

As it has been said before, we may have more than one Vulkan physical device in our host machine. We first need to ask the Vulkan instance
to retrieve the list of supported Vulkan devices (by calling the `enumeratePhysicalDevicesAlloc` function). After that we iterate over that
list trying to get the most suitable one:

**File: src/eng/vk/vkPhysDevice.zig**
```zig
pub const VkPhysDevice = struct {
    ...
    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants, instance: vulkan.InstanceProxy, vkSurface: vk.surf.VkSurface) !VkPhysDevice {
        ...
        for (pdevs) |pdev| {
            const props = instance.getPhysicalDeviceProperties(pdev);
            const memProps = instance.getPhysicalDeviceMemoryProperties(pdev);
            const features = instance.getPhysicalDeviceFeatures(pdev);
            log.debug("Checking [{s}] physical device", .{std.mem.sliceTo(&props.device_name, 0)});

            if (!try checkExtensionSupport(instance, pdev, allocator)) {
                continue;
            }
            if (try hasRequiredQueues(instance, pdev, vkSurface, allocator)) |queuesInfo| {
                const vkPhysDevice = VkPhysDevice{
                    .features = features,
                    .pdev = pdev,
                    .props = props,
                    .queuesInfo = queuesInfo,
                    .memProps = memProps,
                };
                const name_slice = std.mem.sliceTo(&vkPhysDevice.props.device_name, 0);
                if (std.mem.eql(u8, constants.gpu, name_slice)) {
                    try list.insert(allocator, 0, vkPhysDevice);
                    break;
                }
                if (props.device_type == vulkan.PhysicalDeviceType.discrete_gpu) {
                    try list.insert(allocator, 0, vkPhysDevice);
                } else {
                    try list.append(allocator, vkPhysDevice);
                }
            }
        }
        if (list.items.len == 0) {
            return error.NoSuitablePhysicalDevice;
        }
        const result = list.items[0];

        log.debug("Selected [{s}] physical device", .{std.mem.sliceTo(&result.props.device_name, 0)});
        return result;
    }
    ...
};
```

For each physical device we will retrieve all the properties and features we need to use it and to support the device selection. We need to
check for two things:

- That the device supports the swapchain extension (`VK_KHR_swapchain`), which is required to present images to a screen. This is done by
calling the `checkExtensionSupport` function.
- That the device has queue families able to submit graphics commands and to present to our surface. This is done by calling the
`hasRequiredQueues` function.

You may be surprised that presentation is not part of the core API, but think that you may have GPUs that are used just for computing or
that are not even attached to any display (they may do off-screen rendering). Since presentation is optional, we need to be sure that the
selected device supports it, both through the extension and through a queue family that can present to our surface. We will show later on
the implementation of those two functions.

If the device fulfills both conditions, we then check if its name matches the preferred device name (if this has been specified). If so, we
already have our candidate and there's no need to continue so we break the loop. If not, we just add that device to the list of potential
candidates and continue with the loop. We tend to select discrete GPU devices, that is, non integrated GPUs, so we add them on top of the
list to have the highest priority.

Once we have finished with the loop, if the list is empty (no device met the requirements) we return an error. Otherwise, we pick the first
device in the list, which is either the preferred one or the best candidate. You can add more sophistication to this selection process
trying to pick the most capable one, but at this moment this approach should be enough.

The `checkExtensionSupport` function is defined like this:

**File: src/eng/vk/vkPhysDevice.zig**
```zig
pub const VkPhysDevice = struct {
    ...
    fn checkExtensionSupport(
        instance: vulkan.InstanceProxy,
        pdev: vulkan.PhysicalDevice,
        allocator: std.mem.Allocator,
    ) !bool {
        const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
        defer allocator.free(propsv);

        for (reqExtensions) |ext| {
            for (propsv) |props| {
                if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                    break;
                }
            } else {
                return false;
            }
        }

        return true;
    }
};
```

It enumerates the extensions supported by the device and checks that all the ones stored in `reqExtensions` are present. For now, that
constant only contains the name of the `VK_KHR_swapchain` extension.

## Queue families

Since the only function we still have to show is the one named `hasRequiredQueues`, it is now the moment to talk a little bit about Vulkan
queues. In Vulkan, any work is performed by submitting command buffers through specific queues. We do not command the GPU to immediately
draw a specific shape, we submit a command to a queue which contains the instructions to perform an operation like render the vertices that
are part of that shape. Commands in those queues are consumed and executed asynchronously. Devices have different types of queues, which are
organized in families. Each queue family only accepts a specific set of command types. For example, we may have graphic commands (used to
render) and compute commands. Each of these command types may require to be submitted to different types of queue.
In our case, we want to be sure that the selected device has a queue family capable of handling graphics commands and a queue family capable
of presenting to our surface (they may be the same family). This is what we check within the `hasRequiredQueues` function:

**File: src/eng/vk/vkPhysDevice.zig**
```zig
pub const VkPhysDevice = struct {
    ...
    fn hasRequiredQueues(
        instance: vulkan.InstanceProxy,
        pdev: vulkan.PhysicalDevice,
        vkSurface: vk.surf.VkSurface,
        allocator: std.mem.Allocator,
    ) !?QueuesInfo {
        const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
        defer allocator.free(families);

        var graphics_family: ?u32 = null;
        var present_family: ?u32 = null;

        const surfaceKhr = vkSurface.surface;

        for (families, 0..) |properties, i| {
            const family: u32 = @intCast(i);

            if (graphics_family == null and properties.queue_count > 0 and properties.queue_flags.graphics) {
                graphics_family = family;
            }

            if (present_family == null and properties.queue_count > 0 and
                (try instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surfaceKhr)) == vulkan.Bool32.true)
            {
                present_family = family;
            }
        }

        if (graphics_family != null and present_family != null) {
            return QueuesInfo{
                .graphics_family = graphics_family.?,
                .present_family = present_family.?,
            };
        }

        return null;
    }
    ...
};
```

We iterate over the supported queue families. For each one we check whether it has the graphics flag and, separately, whether it can present
to our surface (by calling the `getPhysicalDeviceSurfaceSupportKHR` function). We keep the first family found for each purpose and return
null if either is missing. They are often the same family, but Vulkan does not guarantee it, so we store them separately.
We will explain in more detail the concepts related to queues and commands as we progress through the book.

## Logical Device

Now that we have a physical device we can start with the logical device. Vulkan separates these two concepts, while a physical device
maps directly to capable physical hardware, a logical device represents the actual interface to that hardware. The logical device
is the interface through which we create resources such as buffers and images, which must be destroyed before the device itself.

In case you wonder, you may create more than one logical device, it is another layer of abstraction over our GPU (the physical device) that
allows us to manage the resources. In any case, here we will stick just with one logical device instance. The next picture shows the diagram
updated.

![UML Diagram](rc03-yuml-02.svg)

As in our previous samples, we will create a new struct, named `VkDevice` to wrap device creation and some utility functions around it
(Remember to update the `mod.zig` file to include it: `pub const dev = @import("vkDevice.zig");`). It provides a `create` function to
instantiate it which starts like this:

**File: src/eng/vk/vkDevice.zig**
```zig
const std = @import("std");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

const log = std.log.scoped(.vk);

pub const VkDevice = struct {
    deviceProxy: vulkan.DeviceProxy,

    pub fn create(allocator: std.mem.Allocator, vkInstance: vk.inst.VkInstance, vkPhysDevice: vk.phys.VkPhysDevice) !VkDevice {
        const priority = [_]f32{0};

        const maxFamilies = 2;
        var uniqueFamilies: [maxFamilies]u32 = undefined;
        var uniqueCount: u32 = 0;
        for ([_]u32{
            vkPhysDevice.queuesInfo.graphics_family,
            vkPhysDevice.queuesInfo.present_family,
        }) |family| {
            var alreadyPresent = false;
            for (uniqueFamilies[0..uniqueCount]) |existing| {
                if (existing == family) {
                    alreadyPresent = true;
                    break;
                }
            }
            if (!alreadyPresent) {
                uniqueFamilies[uniqueCount] = family;
                uniqueCount += 1;
            }
        }

        var qciBuf: [maxFamilies]vulkan.DeviceQueueCreateInfo = undefined;
        for (uniqueFamilies[0..uniqueCount], 0..) |family, i| {
            qciBuf[i] = .{
                .queue_family_index = family,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            };
        }
        const qci = qciBuf[0..uniqueCount];

        const features13 = vulkan.PhysicalDeviceVulkan13Features{
            .dynamic_rendering = vulkan.Bool32.true,
            .synchronization_2 = vulkan.Bool32.true,
        };
        const features12 = vulkan.PhysicalDeviceVulkan12Features{
            .p_next = @constCast(&features13),
        };
        const features = vulkan.PhysicalDeviceFeatures{
            .sampler_anisotropy = vkPhysDevice.features.sampler_anisotropy,
        };

        const devCreateInfo: vulkan.DeviceCreateInfo = .{
            .queue_create_info_count = @intCast(qci.len),
            .p_next = @ptrCast(&features12),
            .p_queue_create_infos = qci.ptr,
            .enabled_extension_count = vk.phys.reqExtensions.len,
            .pp_enabled_extension_names = vk.phys.reqExtensions[0..].ptr,
            .p_enabled_features = @ptrCast(&features),
        };
        const device = try vkInstance.instanceProxy.createDevice(vkPhysDevice.pdev, &devCreateInfo, null);

        const vkd = try allocator.create(vulkan.DeviceWrapper);
        vkd.* = vulkan.DeviceWrapper.load(device, vkInstance.instanceProxy.wrapper.dispatch.vkGetDeviceProcAddr.?);
        const deviceProxy = vulkan.DeviceProxy.init(device, vkd);

        return .{ .deviceProxy = deviceProxy };
    }
    ...
};
```

The struct `VkDevice` is the one that will hold our Vulkan logical device. We will use it to create the resources we need later on. We start
by defining the queues that this logical device will create. When we retrieve a queue later on, we have to specify the family it belongs to,
and it is invalid to ask for a queue from a family that was not requested when the device was created. We need queues from the graphics
family and from the present family. The family index represents the purpose of a queue (submitting graphics commands, presenting results to
the screen, etc.), but different purposes can share the same family index. For example, a single family may support both graphics and
presentation. This is why we filter duplicates, so each family is requested only once.

After that, we create an array of `DeviceQueueCreateInfo` structs, one per unique family, each holding the family index, the number of
queues to create (one) and their priorities. Priorities are values between `0.0` and `1.0` assigned to each queue as a hint for the driver
to favor some queues over others. The specification does not mandate how drivers use them, so since we create a single queue per family we
simply set its priority to `0.0`.

We need to enable some features that are present in the `PhysicalDeviceVulkan13Features` struct (`features13` in the code) to enable dynamic
rendering and new synchronization functions (also called sync2) which we will use in next chapters. Vulkan structures can be extended by
chaining them through their `p_next` field, and that is how we pass these features to the device. We link `features13` to the `p_next` field
of the Vulkan 1.2 features struct (`features12`), which we do not fill in because we do not need any Vulkan 1.2 feature yet. It simply acts
as the head of the chain, and it is where we would enable more of them later on (for example, buffer device address). Finally, we link
`features12` to the `p_next` field of `DeviceCreateInfo`. Since `p_next` is an untyped pointer, we need to cast the pointers.

We will also enable sampler anisotropy (we will use it later on for textures) if available by setting the proper flag in the
`PhysicalDeviceFeatures` struct (`features` in the code), which is passed through the `p_enabled_features` field of `DeviceCreateInfo`.

We also enable the extensions stored in `reqExtensions` (for now, just `VK_KHR_swapchain`). We defined that constant in `VkPhysDevice` so
the same list is used to check that the GPU supports them and to enable them when creating the logical device.

With all of the above we can fill up the structure required to create a logical device, which is called `DeviceCreateInfo`.

To complete the `VkDevice` struct, here are the rest of the functions:

**File: src/eng/vk/vkDevice.zig**
```zig
pub const VkDevice = struct {
    ...
    pub fn cleanup(self: *VkDevice, allocator: std.mem.Allocator) void {
        log.debug("Destroying Vulkan Device", .{});
        self.deviceProxy.destroyDevice(null);
        allocator.destroy(self.deviceProxy.wrapper);
    }

    pub fn wait(self: *VkDevice) !void {
        try self.deviceProxy.deviceWaitIdle();
    }
};
```

As you can see they are basically a `cleanup` function to free resources plus one additional function named `wait` which will be used later
on. This function just calls the Vulkan `deviceWaitIdle` function which waits that all the pending operations on any queue for that device
complete.

## Surface

Once we have defined the `VkPhysDevice` it is time to create a surface to display the rendering results. In order to create the surface
we will create a new struct named `VkSurface` (Remember to update the `mod.zig` file to include it:
`pub const surf = @import("vkSurface.zig");`). The following picture updates all the concepts seen so far with this new struct.

![UML Diagram](rc03-yuml-03.svg)

The `VkSurface` struct starts like this:

**File: src/eng/vk/vkSurface.zig**
```zig
const std = @import("std");
const sdl3 = @import("sdl3");
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

const log = std.log.scoped(.vk);

pub const VkSurface = struct {
    surface: vulkan.SurfaceKHR,

    pub fn cleanup(self: *VkSurface, vkInstance: vk.inst.VkInstance) void {
        vkInstance.instanceProxy.destroySurfaceKHR(self.surface, null);
    }

    pub fn create(window: sdl3.video.Window, vkInstance: vk.inst.VkInstance) !VkSurface {
        const vkHandle = vkInstance.instanceProxy.handle;
        const instancePtr: ?*sdl3.c.struct_VkInstance_T = @ptrFromInt(@intFromPtr(vkHandle));

        const surface = sdl3.vulkan.Surface.init(window, instancePtr, null) catch |err| {
            const sdlError = sdl3.c.SDL_GetError();
            log.err("Failed to create Vulkan surface. SDL Error: {s}, Zig Error: {}", .{ sdlError, err });
            return err;
        };

        return .{ .surface = @enumFromInt(@intFromPtr(surface.surface)) };
    }
    ...
};
```

As you can see we just use the `init` function from `sdl3.vulkan.Surface` to create the surface. The handle obtained in this call will be
used later on to be able to construct the artifacts required to render something on the screen.

We also provide a function to retrieve surface capabilities:

**File: src/eng/vk/vkSurface.zig**
```zig
pub const VkSurface = struct {
    ...
    pub fn getSurfaceCaps(self: *const VkSurface, vkInstance: vk.inst.VkInstance, vkPhysDevice: vk.phys.VkPhysDevice) !vulkan.SurfaceCapabilitiesKHR {
        return try vkInstance.instanceProxy.getPhysicalDeviceSurfaceCapabilitiesKHR(vkPhysDevice.pdev, self.surface);
    }
    ...
};
```

We will also provide a function to retrieve a supported surface format:

**File: src/eng/vk/vkSurface.zig**
```zig
pub const VkSurface = struct {
    ...
    pub fn getSurfaceFormat(self: *const VkSurface, allocator: std.mem.Allocator, vkInstance: vk.inst.VkInstance, vkPhysDevice: vk.phys.VkPhysDevice) !vulkan.SurfaceFormatKHR {
        const preferred = vulkan.SurfaceFormatKHR{
            .format = .b8g8r8a8_srgb,
            .color_space = .srgb_nonlinear_khr,
        };

        const surfaceFormats = try vkInstance.instanceProxy.getPhysicalDeviceSurfaceFormatsAllocKHR(
            vkPhysDevice.pdev,
            self.surface,
            allocator,
        );
        defer allocator.free(surfaceFormats);

        for (surfaceFormats) |sfmt| {
            if (std.meta.eql(sfmt, preferred)) {
                return preferred;
            }
        }

        if (surfaceFormats.len == 0) {
            return error.NoSurfaceFormats;
        }

        return surfaceFormats[0];
    }
    ...
};
```

The first thing we do is set up a preferred surface format. This will be the one we select if we find it is supported by the physical
device. After that, we call the `getPhysicalDeviceSurfaceFormatsAllocKHR` function, which queries the number of supported formats and
allocates the list for us. We iterate over them looking for the preferred one. If no formats are reported we return an error, and if the
preferred one is not found we fall back to the first one.

## Queues

As it was introduced before, the way to submit work to our GPU is by submitting command buffers to queues. These command buffers contain the
instructions that will be executed when that job is carried out. An important concept to emphasize when examining the instructions for
commands, is that they will not be executed immediately, we are just recording the commands. Commands need to be submitted to a queue
to have the chance of being executed. Once submitted it is up to the GPU to execute them. We will see later on what is the execution order
and which synchronization mechanisms are available.

![UML Diagram](rc03-yuml-04.svg)

We will create a new struct which models queue retrieval, named `VkQueue` (Remember to update the `mod.zig` file to include it:
`pub const queue = @import("vkQueue.zig");`). The `VkQueue` struct itself is very simple:

**File: src/eng/vk/vkQueue.zig**
```zig
const vulkan = @import("vulkan");
const vk = @import("mod.zig");

pub const VkQueue = struct {
    handle: vulkan.Queue,
    family: u32,

    pub fn create(vkCtx: *const vk.ctx.VkCtx, family: u32) VkQueue {
        return .{
            .handle = vkCtx.vkDevice.deviceProxy.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};
```

In the `VkQueue` `create` function we just invoke the `getDeviceQueue` function which receives the following parameters:

- The index of the queue family that this queue belongs to. If you remember, when we created the device, we specified the queue families
allowed, this index should match one of the indices assigned to those queue families.
- The index of this queue within the queue family itself. When we created the logical device, we defined the queues that were being
pre-created. With this parameter we choose which of those queues to retrieve a handle for.

After calling this function we will get a handle to our queue.

## Render modifications

Now we need to update the `VkCtx` structure to create the new elements:

**File: src/eng/vk/vkCtx.zig**
```zig
const std = @import("std");
const sdl3 = @import("sdl3");
const com = @import("com");
const vk = @import("mod.zig");

pub const VkCtx = struct {
    constants: com.common.Constants,
    vkDevice: vk.dev.VkDevice,
    vkInstance: vk.inst.VkInstance,
    vkPhysDevice: vk.phys.VkPhysDevice,
    vkSurface: vk.surf.VkSurface,

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants, window: sdl3.video.Window) !VkCtx {
        var vkInstance = try vk.inst.VkInstance.create(allocator, constants.validation, constants.syncValidation);
        errdefer vkInstance.cleanup(allocator);

        var vkSurface = try vk.surf.VkSurface.create(window, vkInstance);
        errdefer vkSurface.cleanup(vkInstance);

        const vkPhysDevice = try vk.phys.VkPhysDevice.create(
            allocator,
            constants,
            vkInstance.instanceProxy,
            vkSurface,
        );

        var vkDevice = try vk.dev.VkDevice.create(allocator, vkInstance, vkPhysDevice);
        errdefer vkDevice.cleanup(allocator);

        return .{
            .constants = constants,
            .vkDevice = vkDevice,
            .vkInstance = vkInstance,
            .vkPhysDevice = vkPhysDevice,
            .vkSurface = vkSurface,
        };
    }

    pub fn cleanup(self: *VkCtx, allocator: std.mem.Allocator) void {
        self.vkDevice.cleanup(allocator);
        self.vkSurface.cleanup(self.vkInstance);
        self.vkInstance.cleanup(allocator);
    }
};
```

We added a new configuration variable in the `Constants` struct that allows us to select a specific GPU by name:

**File: src/eng/com/common.zig**
```zig
pub const Constants = struct {
    gpu: []const u8,    
    ...
    pub fn load(allocator: std.mem.Allocator, io: std.Io) !Constants {
        ...
        const constants = Constants{
            .gpu = try allocator.dupe(u8, tmp.gpu),
            .ups = tmp.ups,
            .validation = tmp.validation,
        };
        ...
    }

    pub fn cleanup(self: *Constants, allocator: std.mem.Allocator) void {
        allocator.free(self.gpu);
    }
};
```

You will need to update the `res/cfg/cfg.toml` file to add a new entry named `gpu`. If you set it to the exact name of your GPU (the log
prints the name of each device it checks), that device will be selected. Leaving it empty lets the engine choose automatically,
preferring discrete GPUs.

**File: res/cfg/cfg.toml**
```toml
gpu=""
```

Since we now need to have access to the window in the `VkCtx` struct we need to update the `Render` struct to properly instantiate it. We
will also update the `cleanup` function to wait for the device prior to perform any cleanup action:

**File: src/eng/render.zig**
```zig
...
const log = std.log.scoped(.eng);
...
pub const Render = struct {
    ...
    pub fn cleanup(self: *Render, allocator: std.mem.Allocator) void {
        self.vkCtx.vkDevice.wait() catch |err| log.err("Device wait failed in cleanup: {}", .{err});

        self.vkCtx.cleanup(allocator);
    }

    pub fn create(allocator: std.mem.Allocator, constants: com.common.Constants, window: sdl3.video.Window) !Render {
        var vkCtx = try vk.ctx.VkCtx.create(allocator, constants, window);
        errdefer vkCtx.cleanup(allocator);
        return .{
            .vkCtx = vkCtx,
        };
    }
    ...
}
```

Finally, we need to update the `Engine` struct to also pass a reference to the window when creating a `Render` instance:

**File: src/eng/eng.zig**
```zig
pub fn Engine(comptime GameLogic: type) type {
    ...
        pub fn create(allocator: std.mem.Allocator, io: std.Io, gameLogic: *GameLogic, wndTitle: [:0]const u8) !Engine(GameLogic) {
            ...
            var render = try eng.rend.Render.create(
                allocator,
                engCtx.constants,
                engCtx.wnd.window,
            );
            errdefer render.cleanup(allocator);
            ...
        }
    ...
};
```

That's all for this chapter, we are slowly defining the structs that we need in order to render something. We have still a long road ahead
of us, but I hope the pieces will start to make sense soon.

[Back to Table of Contents](../README.md)

[Previous chapter](../chapter-02/chapter-02.md) | [Next chapter](../chapter-04/chapter-04.md)