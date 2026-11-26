// harness <engine.so> <capture dir> <frames> <out dir>
// Calls vana_nr_dispatch the way vana-client does, with the capture's colour and motion in the client's formats and
// layouts (no depth), and writes each frame's output as linear f32 RGBA to <out dir>/NN.out.f32.
#include "nrvk.hpp"

#include <dlfcn.h>
#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

extern "C" {
typedef struct { uint64_t image, view; uint32_t format, layout, width, height; } VanaUpscaleImage;
typedef struct {
    uint32_t version, queue_family;
    uint64_t instance, physical_device, device, queue, command_buffer;
    VanaUpscaleImage color, depth, motion, reactive, composition, output;
    uint32_t render_size[2], output_size[2];
    float jitter[2];
    uint32_t reset, reversed_z;
    float frame_time_ms, near_plane, far_plane, fov_y, meters_per_unit, exposure, sharpness;
} VanaUpscaleFrame;
}

static uint16_t to_half(float f) {
    uint32_t u; std::memcpy(&u, &f, 4);
    const uint32_t sign = (u >> 16) & 0x8000u;
    const int e = int((u >> 23) & 0xFF) - 127 + 15;
    if (e <= 0) return uint16_t(sign);
    if (e >= 31) return uint16_t(sign | 0x7BFFu);
    uint32_t h = (uint32_t(e) << 10) | ((u & 0x7FFFFFu) >> 13);
    const uint32_t rest = u & 0x1FFFu;
    if (rest > 0x1000u || (rest == 0x1000u && (h & 1u))) ++h;
    return uint16_t(sign | h);
}
static float from_half(uint16_t h) {
    const int e = (h >> 10) & 0x1F, m = h & 0x3FF;
    const float v = e == 0 ? std::ldexp(float(m), -24) : std::ldexp(float(m | 0x400), e - 25);
    return (h & 0x8000) ? -v : v;
}
static std::vector<float> floats(const std::string& path, size_t n) {
    std::ifstream f(path, std::ios::binary);
    std::vector<float> v(n);
    if (!f.read(reinterpret_cast<char*>(v.data()), std::streamsize(n * 4))) throw std::runtime_error("cannot read " + path);
    return v;
}

int main(int argc, char** argv) try {
    if (argc < 5) { std::fprintf(stderr, "usage: harness <engine.so> <capture dir> <frames> <out dir>\n"); return 2; }
    void* lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!lib) { std::fprintf(stderr, "%s\n", dlerror()); return 1; }
    auto dispatch = reinterpret_cast<int (*)(const VanaUpscaleFrame*)>(dlsym(lib, "vana_nr_dispatch"));
    if (!dispatch) { std::fprintf(stderr, "no vana_nr_dispatch\n"); return 1; }
    const uint32_t w = 1280, h = 720;
    const int frames = atoi(argv[3]);

    nrvk::Context ctx;
    ctx.create();
    auto color = ctx.image(w, h, VK_FORMAT_R16G16B16A16_SFLOAT, true);   // SHADER_READ_ONLY_OPTIMAL
    auto motion = ctx.image(w, h, VK_FORMAT_R16G16_SFLOAT, true);
    auto output = ctx.image(w, h, VK_FORMAT_R16G16B16A16_SFLOAT, false); // GENERAL

    auto img = [](const nrvk::Context::Image& im) {
        return VanaUpscaleImage{uint64_t(reinterpret_cast<uintptr_t>(im.handle)), uint64_t(reinterpret_cast<uintptr_t>(im.view)),
                                uint32_t(im.format), uint32_t(im.layout), im.w, im.h};
    };
    const int loops = std::getenv("HARNESS_LOOPS") ? std::max(1, atoi(std::getenv("HARNESS_LOOPS"))) : 1;
    for (int n = 0; n < loops * frames; ++n) {
        const int i = n % frames;
        const bool last = n >= (loops - 1) * frames;
        char dir[1024]; std::snprintf(dir, sizeof dir, "%s/frame_%03d", argv[2], i);
        const auto c = floats(std::string(dir) + "/color.f32", size_t(w) * h * 4);
        const auto m = floats(std::string(dir) + "/motion.f32", size_t(w) * h * 2);
        std::vector<uint16_t> ch(c.size()), mh(m.size());
        for (size_t k = 0; k < c.size(); ++k) ch[k] = to_half(c[k]);
        for (size_t k = 0; k < m.size(); ++k) mh[k] = to_half(i ? m[k] : 0.0f);
        ctx.upload(color, ch.data(), ch.size() * 2);
        ctx.upload(motion, mh.data(), mh.size() * 2);

        VanaUpscaleFrame f{};
        f.version = 1; f.queue_family = ctx.family;
        f.instance = uint64_t(reinterpret_cast<uintptr_t>(ctx.instance));
        f.physical_device = uint64_t(reinterpret_cast<uintptr_t>(ctx.physical));
        f.device = uint64_t(reinterpret_cast<uintptr_t>(ctx.device));
        f.queue = uint64_t(reinterpret_cast<uintptr_t>(ctx.queue));
        f.color = img(color); f.motion = img(motion); f.output = img(output);
        f.render_size[0] = f.output_size[0] = w; f.render_size[1] = f.output_size[1] = h;
        f.reset = n == 0;
        int r = 1;
        // the runtime is built on the first call, before this recording is submitted
        ctx.one_shot([&](VkCommandBuffer cmd) {
            f.command_buffer = uint64_t(reinterpret_cast<uintptr_t>(cmd));
            r = dispatch(&f);
        });
        if (r) { std::fprintf(stderr, "frame %d: engine returned %d\n", i, r); return 1; }
        if (!last) continue;
        std::vector<uint16_t> oh(ch.size());
        ctx.download(output, oh.data(), oh.size() * 2);
        std::vector<float> of(oh.size());
        for (size_t k = 0; k < oh.size(); ++k) of[k] = from_half(oh[k]);
        char out[1024]; std::snprintf(out, sizeof out, "%s/%02d.out.f32", argv[4], i);
        std::ofstream(out, std::ios::binary).write(reinterpret_cast<const char*>(of.data()), std::streamsize(of.size() * 4));
        std::printf("frame %d ok\n", i);
    }
    return 0;
} catch (const std::exception& e) {
    std::fprintf(stderr, "harness: %s\n", e.what());
    return 1;
}
