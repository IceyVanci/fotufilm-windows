// swift-tools-version: 5.9
import Foundation
import PackageDescription

// Halide is an optional build-time dependency. Homebrew installs it into one of the first two
// roots; HALIDE_ROOT also supports source/binary releases and Linux CI images.
let halideRoots = [
    ProcessInfo.processInfo.environment["HALIDE_ROOT"],
    "/opt/homebrew",
    "/usr/local",
].compactMap { $0 }

let halideDisabled = ProcessInfo.processInfo.environment["FOTUFILM_DISABLE_HALIDE"] == "1"
let halideRoot = halideDisabled ? nil : halideRoots.first {
    let manager = FileManager.default
    guard manager.fileExists(atPath: "\($0)/include/Halide.h") else { return false }
    // Homebrew and the source build put the library in lib/; the Windows release keeps the
    // release configuration one directory down.
    return manager.fileExists(atPath: "\($0)/lib/libHalide.dylib")
        || manager.fileExists(atPath: "\($0)/lib/libHalide.so")
        || manager.fileExists(atPath: "\($0)/lib/Release/Halide.lib")
}
/// Where the Halide library this manifest found keeps its linkable archive.
let halideLibraryDirectory: String? = halideRoot.map { root in
    FileManager.default.fileExists(atPath: "\(root)/lib/Release/Halide.lib")
        ? "\(root)/lib/Release" : "\(root)/lib"
}

// Windows ships ahead-of-time Vulkan kernels instead of a compiler: FOTUFILM_AOT_DIR names the
// directory tools/generate-halide-aot-windows.ps1 filled, and the shim (FotufilmHalideLinux.cpp,
// which the port compiles with its Windows loader path) selects the variant at run time.
let aotDirectory = ProcessInfo.processInfo.environment["FOTUFILM_AOT_DIR"] ?? ""
let aotLibraries: [String] = aotDirectory.isEmpty ? [] : (
    (try? FileManager.default.contentsOfDirectory(atPath: aotDirectory))?
        .filter { $0.hasSuffix(".lib") || $0.hasSuffix(".a") }.sorted() ?? [])
let windowsAOT = !aotLibraries.isEmpty
// Built statement by statement: inside a ternary the compiler picks PackageDescription's
// unavailable overloads, and inside Package it runs out of type-checking patience.
var windowsAOTCXXSettings: [CXXSetting] = []
if windowsAOT {
    windowsAOTCXXSettings.append(
        .unsafeFlags(["-DFOTUFILM_HALIDE_LINUX_AOT", "-I\(aotDirectory)"],
                     .when(platforms: [.windows])))
}
// Built one statement at a time: the manifest's single Package expression runs out of type-checking
// patience once a list this long is folded into it.
var windowsAOTLinkerSettings: [LinkerSetting] = []
if windowsAOT {
    windowsAOTLinkerSettings.append(
        .unsafeFlags(["-L\(aotDirectory)"], .when(platforms: [.windows])))
    for library in aotLibraries {
        // Halide writes the standalone runtime as runtime.a whatever the host; the linker wants the
        // whole path for it, and the name alone for the .lib archives beside it.
        if library.hasSuffix(".a") {
            windowsAOTLinkerSettings.append(
                .unsafeFlags(["\(aotDirectory)/\(library)"],
                             .when(platforms: [.windows])))
        } else {
            let name = library.split(separator: ".").dropLast().joined(separator: ".")
            windowsAOTLinkerSettings.append(
                .linkedLibrary(name, .when(platforms: [.windows])))
        }
    }
}

let halidePlatforms: [Platform] = [.macOS, .linux, .windows]
let halideCXXSettings: [CXXSetting] = halideRoot.map { root in
    [
        .define("FOTUFILM_HALIDE_ENABLED", .when(platforms: halidePlatforms)),
        // MSVC keeps the C math constants (M_LN10 and friends) behind this macro.
        .define("_USE_MATH_DEFINES", .when(platforms: [.windows])),
        .define("FOTUFILM_ENABLE_COMPILED_CACHE", .when(platforms: [.macOS])),
        .unsafeFlags(["-I\(root)/include", "-std=c++17"], .when(platforms: halidePlatforms)),
    ]
} ?? []
let halideLinkerSettings: [LinkerSetting] = halideRoot.map { root in
    [
        // Resolve relocatable Halide libraries as well as Homebrew installations.
        .unsafeFlags(
            ["-L\(halideLibraryDirectory ?? "\(root)/lib")"],
            .when(platforms: halidePlatforms)),
        // Apple and Linux load the library from the tree that built it; Windows finds Halide.dll
        // beside the executable.
        .unsafeFlags(
            ["-Xlinker", "-rpath", "-Xlinker", "\(root)/lib"],
            .when(platforms: [.macOS, .linux])),
        .linkedLibrary("Halide", .when(platforms: halidePlatforms)),
        .linkedFramework("Metal", .when(platforms: [.macOS])),
        .linkedFramework("Accelerate", .when(platforms: [.macOS])),
        .linkedLibrary("dl", .when(platforms: [.linux])),
        .linkedLibrary("pthread", .when(platforms: [.linux])),
    ]
} ?? []

// Windows: the portable codecs take the same libraries from a vcpkg tree that the Linux build
// takes from the system (LibRaw, lcms2, libjpeg-turbo, libpng, libtiff, libheif, OpenEXR).
// FOTUFILM_VCPKG_ROOT names the tree; without it the codec target stays out of the Windows build
// and the host keeps the services it can supply.
let vcpkgRoot = ProcessInfo.processInfo.environment["FOTUFILM_VCPKG_ROOT"]
    ?? "F:/Futo/toolchain/vcpkg"
// x64-windows-static-md: static codec archives against the dynamic C runtime, which is what
// Swift on Windows compiles against (/MD). The plain -static triplet links the static CRT and
// the two cannot be mixed.
let vcpkgTriplet = ProcessInfo.processInfo.environment["FOTUFILM_VCPKG_TRIPLET"]
    ?? "x64-windows-static-md"
let vcpkgPrefix = "\(vcpkgRoot)/installed/\(vcpkgTriplet)"
let vcpkgLibs = "\(vcpkgPrefix)/lib"
// LibRaw's static release is raw_r.lib; its presence means the codec libraries are installed.
let vcpkgAvailable = FileManager.default.fileExists(atPath: "\(vcpkgLibs)/raw_r.lib")
let vcpkgCXXSettings: [CXXSetting] = vcpkgAvailable ? [
    .unsafeFlags(["-I\(vcpkgPrefix)/include", "-std=c++17"], .when(platforms: [.windows]))
] : [.unsafeFlags(["-std=c++17"], .when(platforms: [.windows]))]
let vcpkgLinkerSettings: [LinkerSetting] = {
    guard vcpkgAvailable,
          let entries = try? FileManager.default.contentsOfDirectory(atPath: vcpkgLibs) else { return [] }
    // Every library the tree installed: the codecs' static archives carry no record of their own
    // dependencies, so the link needs each one named.
    var settings: [LinkerSetting] = []
    let windowsOnly: [Platform] = [.windows]
    for entry in entries.sorted() {
        guard entry.hasSuffix(".lib"), !entry.lowercased().contains("debug") else { continue }
        let name = String(entry.dropLast(4))
        settings.append(.linkedLibrary(name, .when(platforms: windowsOnly)))
    }
    // LibRaw is built with its OpenMP feature here, so the codecs call MSVC's OpenMP runtime;
    // vcomp.lib lives in the toolchain, not in the vcpkg tree.
    settings.append(.linkedLibrary("vcomp", .when(platforms: windowsOnly)))
    return settings
}()

#if os(Linux)
// CUDA benchmarking requires Halide. Objective-C++ Metal kernels require Apple frameworks.
let benchmarkTargets: [Target] = halideRoot != nil ? [
    .executableTarget(name: "fotufilmbench",
                      dependencies: ["FotufilmCore", "FotufilmHalide"]),
] : []
let benchmarkProducts: [Product] = halideRoot != nil ? [
    .executable(name: "fotufilmbench", targets: ["fotufilmbench"]),
] : []
let halideGPUCXXSettings: [CXXSetting] = halideRoot != nil
    ? [.define("FOTUFILM_HALIDE_CUDA", .when(platforms: [.linux]))]
    : []

// SwiftPM builds every test file before applying filters; exclude Apple-only fixtures on Linux.
let appleOnlyTests = [
    // Unguarded CoreGraphics/CoreImage/ImageIO: these seven reach Apple's frameworks directly.
    "RGBAImage.swift",
    "GamutShowcaseTool.swift",
    "LensCorpusHarness.swift",
    "LensCorrectionFilterTests.swift",
    "UnitCropCoordinatesTests.swift",
    "GrainABTool.swift",
    "NegativeScanFramingTests.swift",
    // Image comparisons use ImageIO through RGBAImage.
    "PrintDifference.swift",
    "CatalogueStocks.swift",
    "ReferenceChart.swift",
    "ImageInstrumentTests.swift",
    "SelfRetentionMeasurement.swift",
    "SpectrumSceneTests.swift",
]
#else
let benchmarkTargets: [Target] = []
let benchmarkProducts: [Product] = []
let halideGPUCXXSettings: [CXXSetting] = []
let appleOnlyTests: [String] = []
#endif

// Composed once, outside Package and after every input has initialised: the manifest's single
// expression will not type-check a chain of array concatenations this long, and a top-level
// reference to a later declaration reads an uninitialised global.
let halideTargetCXXSettings: [CXXSetting] =
    halideCXXSettings + halideGPUCXXSettings + windowsAOTCXXSettings
let halideTargetLinkerSettings: [LinkerSetting] =
    halideLinkerSettings + windowsAOTLinkerSettings

// The codec target's settings, composed once: the compiler type-checks this manifest as one
// expression, and the Windows additions push the array literals past what it will solve inline.
let codecCXXSettings: [CXXSetting] =
    [.unsafeFlags(["-std=c++17"], .when(platforms: [.linux]))] + vcpkgCXXSettings
let vcpkgLinkerPaths: [LinkerSetting] = vcpkgAvailable
    ? [.unsafeFlags(["-L\(vcpkgLibs)"], .when(platforms: [.windows]))]
    : []
let codecLinkerSettings: [LinkerSetting] =
    ["raw_r", "lcms2", "jpeg", "png", "tiff", "heif"].map {
        .linkedLibrary($0, .when(platforms: [.linux]))
    } + vcpkgLinkerPaths + vcpkgLinkerSettings

let package = Package(
    name: "Fotufilm",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "FotufilmCore", targets: ["FotufilmCore"]),
        .library(name: "FotufilmUpdate", targets: ["FotufilmUpdate"]),
        .library(name: "FotufilmMetal", targets: ["FotufilmMetal"]),
        .library(name: "FotufilmImaging", targets: ["FotufilmImaging"]),
        .library(name: "FotufilmStockMatch", targets: ["FotufilmStockMatch"]),
        .library(name: "FotufilmEditModel", targets: ["FotufilmEditModel"]),
        // The engine behind `fotufilm.h`, for hosts in other languages.
        .library(name: "FotufilmHost", type: .dynamic, targets: ["FotufilmHost"]),
        .executable(name: "fotufilm", targets: ["fotufilm"]),
        .executable(name: "fotufilm-controls", targets: ["fotufilm-controls"]),
        .executable(name: "fotufilm-web-profile", targets: ["fotufilm-web-profile"]),
        .executable(name: "fotufilm-parity", targets: ["fotufilm-parity"]),
    ] + benchmarkProducts,
    targets: [
        .target(name: "FotufilmUpdate"),
        .target(
            name: "FotufilmHalide",
            path: "Sources/FotufilmHalide",
            publicHeadersPath: "include",
            cxxSettings: halideTargetCXXSettings,
            linkerSettings: halideTargetLinkerSettings
        ),
        .target(
            name: "FotufilmCore",
            dependencies: ["FotufilmHalide"],
            // Process camera profiles individually so dependency directory links are
            // dereferenced into self-contained resources. Stocks retain their pack directory.
            resources: [.process("Resources"),
                        .process("CameraProfiles"),
                        .copy("Stocks")]
        ),
        .target(
            name: "FotufilmMetal",
            dependencies: ["FotufilmCore", "FotufilmHalide"]
        ),
        // Core Image decoding and resampling shared by both apps and the CLI.
        .target(name: "FotufilmImaging", dependencies: ["FotufilmCore"]),
        // Choosing the film a photograph opens on.
        .target(name: "FotufilmStockMatch", dependencies: ["FotufilmCore"]),
        // Shared editor controls and their engine options.
        .target(name: "FotufilmEditModel", dependencies: ["FotufilmCore"]),
        // Installing the Resolve and Final Cut plug-ins, shared by the Mac app and Fotufilm Desktop.
        .target(name: "FotufilmPlugins"),
        .target(name: "CFotufilmHost"),
        // Still images where there is no ImageIO (Linux), through the system's libraries.
        .systemLibrary(name: "COpenEXR", pkgConfig: "OpenEXR",
                       providers: [.apt(["libopenexr-dev"])]),
        .target(name: "CFotufilmCodecs",
                dependencies: [.target(name: "COpenEXR", condition: .when(platforms: [.linux]))],
                cxxSettings: codecCXXSettings,
                linkerSettings: codecLinkerSettings),
        // Movies where there is no AVFoundation (Linux), through the system's FFmpeg, loaded
        // when first asked for.
        .target(name: "CFotufilmVideo",
                cxxSettings: [.unsafeFlags(["-std=c++17"])],
                linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        .target(name: "FotufilmHost",
                dependencies: ["CFotufilmHost", "FotufilmCore", "FotufilmImaging",
                               "FotufilmEditModel", "FotufilmStockMatch", "FotufilmPlugins",
                               "FotufilmUpdate",
                               .target(name: "FotufilmMetal",
                                       condition: .when(platforms: [.macOS, .iOS])),
                               // Linux develops through the graph's CUDA and Vulkan entry points.
                               .target(name: "FotufilmHalide",
                                       condition: .when(platforms: [.linux])),
                               .target(name: "CFotufilmCodecs",
                                       condition: .when(platforms: [.linux, .windows])),
                               .target(name: "CFotufilmVideo",
                                       condition: .when(platforms: [.linux]))]),
        .executableTarget(name: "fotufilm",
                          dependencies: ["FotufilmCore", "FotufilmImaging", "FotufilmEditModel"]),
        .executableTarget(name: "fotufilm-controls", dependencies: ["FotufilmEditModel"]),
        .executableTarget(name: "fotufilm-web-profile", dependencies: ["FotufilmEditModel"]),
        // Develops one scene on the CPU and the GPU (Metal, CUDA or Vulkan) for cross-machine parity.
        .executableTarget(name: "fotufilm-parity",
                          dependencies: ["FotufilmCore", "FotufilmHalide",
                                         .target(name: "FotufilmImaging",
                                                 condition: .when(platforms: [.macOS]))]),
        .testTarget(
            name: "FotufilmCoreTests",
            dependencies: ["FotufilmCore",
                           .target(name: "FotufilmMetal",
                                   condition: .when(platforms: [.macOS, .iOS])),
                           "FotufilmImaging", "FotufilmStockMatch"],
            exclude: appleOnlyTests
        ),
        .testTarget(
            name: "FotufilmEditModelTests",
            dependencies: ["FotufilmEditModel", "FotufilmCore"]
        ),
        .testTarget(
            name: "FotufilmHostTests",
            dependencies: ["FotufilmHost", "CFotufilmHost", "FotufilmPlugins"]
        ),
        .testTarget(
            name: "FotufilmUpdateTests",
            dependencies: ["FotufilmUpdate"]
        ),
    ] + benchmarkTargets
)