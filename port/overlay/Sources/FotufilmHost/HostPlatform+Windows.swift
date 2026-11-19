#if os(Windows)
import Foundation
#if canImport(CFotufilmCodecs)
import CFotufilmCodecs
#endif
#if canImport(FotufilmHalide)
import FotufilmHalide
#endif

extension HostPlatform {
    /// Windows: photographs, scans, stills and thumbnails through the portable codecs
    /// (`Sources/CFotufilmCodecs`: LibRaw, lcms2, libjpeg-turbo, libpng, libtiff, libheif and
    /// OpenEXR, from the vcpkg tree the build links). The GPU developer arrives with the Halide
    /// Vulkan kernels; the clipboard, the plug-ins, the release feed and the film packs follow as
    /// each service is written, and each one that is missing keeps its feature off.
    static var windows: HostPlatform {
        var platform = HostPlatform()
        // The AOT Vulkan kernels (FotufilmHalideLinux.cpp, which this port compiles) answer through
        // the same developer service the Linux desktop uses. A machine whose driver offers no
        // Vulkan device gets no developer here, and HostEngine falls back to the portable CPU one
        // (the kernels tools/generate-halide-cpu-windows.ps1 writes), so it still develops, slowly.
        #if canImport(FotufilmHalide)
        if fotufilm_halide_gpu_device() != 0 {
            platform.developer = HalideGPUDeveloper()
        }
        platform.portableDeveloper = fotufilm_halide_available() == 1
        #endif
        #if canImport(CFotufilmCodecs)
        platform.decoder = PortableImageDecoder()
        platform.scans = PortableScanDecoder()
        platform.encoder = PortableStillEncoder()
        platform.thumbnails = PortableThumbnailer()
        #endif
        return platform
    }
}
#endif
