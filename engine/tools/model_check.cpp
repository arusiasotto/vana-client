// model_check <nvngx_dlssnr.dll or .zip> <out dir>: vana_model::check, then make, with progress.
#include "model.hpp"

#include <chrono>
#include <cstdio>

int main(int argc, char** argv) {
    if (argc != 3) { std::fprintf(stderr, "usage: model_check <nvngx_dlssnr.dll or .zip> <out dir>\n"); return 2; }
    const auto t0 = std::chrono::steady_clock::now();
    auto secs = [&] { return std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count(); };
    vana_model::DllInfo info;
    std::string err;
    if (!vana_model::check(argv[1], info, err)) { std::printf("check: %s\n", err.c_str()); return 1; }
    std::printf("check: %s (%s%s) in %.2f s\n", info.version.c_str(), info.original ? "original" : "", info.small ? " + small" : "", secs());
    int shown = -10;
    const bool ok = vana_model::make(argv[1], argv[2], [&](float f) {
        const int pct = int(f * 100);
        if (pct / 10 != shown / 10) { shown = pct; std::printf("  %3d%%  %.1f s\n", pct, secs()); std::fflush(stdout); }
    }, err);
    if (!ok) { std::printf("make: %s\n", err.c_str()); return 1; }
    std::printf("made in %.2f s\n", secs());
    return 0;
}
