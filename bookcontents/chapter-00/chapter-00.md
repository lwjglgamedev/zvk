# Chapter 00 - Introduction

So what is Vulkan? Here's the definition for the Vulkan standard landing page:

> Vulkan is a new generation graphics and compute API that provides high-efficiency,
> cross-platform access to modern GPUs used in a wide variety of devices from PCs and consoles to mobile phones and embedded platforms.

Vulkan is a standard developed by the [Khronos group](https://www.khronos.org/),
which is an open industry consortium behind many other well-known standards such as [OpenGL](https://www.khronos.org/opengl/) and [OpenCL](https://www.khronos.org/opencl/).

## Why Vulkan?

The first questions to come to mind are why Vulkan? Why adopt another cross-platform graphics API? Why not just stick with OpenGL, which is also cross-platform?

[![](https://imgs.xkcd.com/comics/standards.png)](https://xkcd.com/927/)

- It is as modern of an API as you can get, designed without the constraints of having to maintain backwards compatibility or legacy hardware.
  Take, for instance OpenGL,
  it is an aging API that has been evolving over the years and needs to support all parts of a graphics pipeline,
  from immediate modes to programmable pipelines.

- As a modern API, it has been designed with modern hardware capabilities in mind (GPUs and CPUs).
  For example, [concurrency support](https://en.wikipedia.org/wiki/Concurrency_(computer_science)) is part one of the strongest points of Vulkan.
  This dramatically improves the performance of applications that may now be CPU constrained by the single-threaded nature of some other APIs (such us OpenGL).

- It is a lower overhead API, in the sense that the most part of the work shall be explicitly done in the application.
  Hence, developers need to be very direct and precisely control every aspect.
  This simplifies the Vulkan drivers which provide a very thin layer on top of the hardware.

- Due to its lower overhead and its explicit nature, you will have direct control.
  You will get what you ask for, the drivers will not have to guess or assume about the next steps in your application, nor will it hold your hand.
  This will mean the differences between implementations and drivers may be much lower than in other APIs,
  resulting in more predictable and portable applications.

- It is indeed a platform-agnostic API not only for desktop computing but also for mobile platforms.

All that has been said above comes at a cost.
It is an API that imposes a lot of responsibility onto the developers.
And with great power, comes big responsibility.
You will have to properly control everything, from memory allocation, to resource management,
and to guarantee proper synchronization between your CPU and graphics card.
As a result, you will have a more direct view about the GPU working inner details,
which combined with the knowledge on how your application works can lead to great performance improvements.

The next question that may come to your mind may be, Is it Vulkan the right tool for you?
The answer to this question depends on your skills and interests.
If you are new to programming or want to obtain a rapid product, Vulkan is not the most adequate solution for you.
As it has been already said, Vulkan is complex--you will have to invest lots of time understanding all the concepts,
which can be challenging to understand for even moderate programmers.
It is hard, but there will be a moment where all this complexity will start to fit in your mind and make sense.
As a result, you will have a deeper knowledge of (and appreciation for) modern graphics applications and how GPUs work.

Besides complexity, other drawbacks of Vulkan may be:

- Verbosity.
  It is a very explicit API;
  you will have to specify every single detail, from available features, memory layouts,
  detailed pipeline execution, etc. This means that you will have to write a lot of code to manage it all.
- You may not directly translate concepts from other APIs to fully exploit Vulkan capabilities.
  This implies additional effort, specially if you have an existing codebase or assets.
- Its relatively new, so it is not so easy to find information about some specific topics.

Therefore, if you are new to programming,
it is much better to start with some existing game engines such as [Unity](https://unity.com) or [Godot](https://godotengine.org/) or even to start with OpenGL.

## Prerequisites

This book assumes that you have a good understanding of Zig language, and some previous knowledge of 3D graphics, such as OpenGL. 

Requisites:

- [Zig](https://ziglang.org/): We will be using 0.15.2 version.
- The Vulkan [SDK](https://vulkan.lunarg.com/). You will need to install it for your operative system. You will need to setup an environment variable
named `VULKAN_SDK` which points to the root folder of the SDK.
- We will be using Vulkan 1.3 so make sure your GPU supports that version.

> [!WARNING]  
> Source code is structured as a several zig projects. The recommended approach is to open each chapter independently. Resources (3D models, shaders, etc.)
> are loaded using relative > paths to the root folder, which is the folder associated to each chapter (chapter-01, chapter02, ... etc.).

## Resources used for writing this book

This book is the result of my self-learning process.
I do not work on this domain professionally, rather I'm just a hobbyist with an interest in learning new technologies.
As a result, you may find mistakes/bugs or even explanations that may be plain wrong.
Please feel free to contact me about that.
My aim is that this book may help others in learning Vulkan.

There are multiple materials that I've consulted to write this book.
The following list collects the ones that I've found more useful, and that I've consulted many times while leaning the Vulkan path:

- [The Vulkan tutorial](https://vulkan-tutorial.com/). This is a C based tutorial for Vulkan which describes in great detail the core concepts of the API.
- [Sascha Willems](https://github.com/SaschaWillems/Vulkan) Vulkan samples. This is an awesome collection of C++ samples which cover a huge set of Vulkan features.
- [Khronos Vulkan samples](https://github.com/KhronosGroup/Vulkan-Samples).

[Next chapter](../chapter-01/chapter-01.md)

## Renderdoc

[Renderdoc](https://renderdoc.org/) is a great tool to debug what is happening in your GPU when rendering a frame. Using this tool with
the code is quite simple, just select the executable and launch it. 

> [!WARNING]  
> If you are using Linux with Wayland just make sure to have the `SDL_VIDEODRIVER` environment variable to `x11`.