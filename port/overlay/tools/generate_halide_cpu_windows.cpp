// The Windows CPU fallback's kernels: the reference CPU pipeline (Pipeline/Cpu.h) compiled for
// this machine, so a host with no Vulkan device develops photographs instead of refusing to start.
//
// The modules match web/engine/fotufilm_wasm_cpu.cpp's, which the browser's CPU fallback links:
// one develop schedule per spatial feature set (the full stage set, with the runtime gates that
// skip what a frame does not ask for), the print stage per (reversal, monochrome) pair, and the
// plain schedule Normal develops with.
//
// Every module is compiled with NoRuntime: FotufilmHalideLinux.cpp links the one standalone
// runtime the Vulkan set already ships (generate-halide_ios.cpp's --extras step), and a second
// copy would collide with it.
#define FOTUFILM_HALIDE_ENABLED 1
#define FOTUFILM_HALIDE_AOT_GENERATOR 1
#include "../Sources/FotufilmHalide/Pipeline/Cpu.h"
#include "../Sources/FotufilmHalide/include/FotufilmAotVariants.h"

using namespace fotufilm;
using namespace fotufilm::pipelines;

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <iterator>

int main(int argc, char **argv) {
    if (argc < 2) {
        std::cerr << "usage: generate_halide_cpu_windows OUTPUT_DIRECTORY [HALIDE_TARGET]\n"
                     "       (default target: x86-64-windows-avx2)\n";
        return 2;
    }
    const std::filesystem::path output(argv[1]);
    std::filesystem::create_directories(output);
    const std::string target_name = argc > 2 ? argv[2] : "x86-64-windows-avx2";
    const Halide::Target target(target_name);
    std::cout << "target " << target << "\n";

    const auto compile = [&](const std::string &name, const auto &call) {
        std::cout << "  " << name << std::flush;
        call((output / name).string(), name);
        std::cout << " ok\n";
    };

    // The develop stage: the full stage set once, with and without annular halation, exactly as
    // the browser's fallback carries it.
    for (const bool annular : {false, true}) {
        const int32_t features =
            FOTUFILM_AOT_FULL_STAGES | (annular ? FOTUFILM_FRAME_HALATION_ANNULAR : 0);
        const std::string name = annular ? "develop_flexible_annular" : "develop_flexible";
        DevelopPipeline pipeline(features, "_" + name);
        compile(name, [&](const std::string &path, const std::string &function) {
            pipeline.compile_aot(path, function, false, target, true);
        });
    }

    // Reversal and monochrome each change the print graph.
    for (int variant = 0; variant < 4; ++variant) {
        const bool reversal = (variant & 1) != 0;
        const bool monochrome = (variant & 2) != 0;
        const std::string name = "print_" + std::to_string(variant);
        PrintPipeline pipeline(reversal, monochrome, "_windows_print_variant_" +
                                                       std::to_string(variant));
        compile(name, [&](const std::string &path, const std::string &function) {
            pipeline.compile_aot(path, function, false, target);
        });
    }

    // Normal: no film in the gate.
    PlainPipeline plain(false, "_windows_plain", false, 0);
    compile("plain_float", [&](const std::string &path, const std::string &function) {
        plain.compile_aot(path, function, false, target);
    });
    return 0;
}
