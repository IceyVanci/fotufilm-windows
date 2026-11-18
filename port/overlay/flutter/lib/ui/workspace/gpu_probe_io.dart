import 'dart:io';

/// Whether the Windows runner found no Vulkan device before Flutter started: it sets
/// `FOTUFILM_NO_VULKAN`, so the editor need not touch the engine to learn it.
bool get noVulkanDevice => Platform.environment['FOTUFILM_NO_VULKAN'] == '1';
