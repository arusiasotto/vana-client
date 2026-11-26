// vana-client neural rendering engine: NVIDIA's DLSS 5 network on the pre-upscale colour, through
// DLSSNR-RDNA3's runtime (mauri870, MIT), itself built on DLSSNR-AMD (mochizuki0323, MIT). Thanks to both.
// Layout next to this .so: nr/dlssnr-amd/{shaders,dlssnr.bin,dlssnr-small.bin}, nr/{prep,compose}.spv,
// nr/engine.ini (settings, re-read while running; made from engine.ini.default), nr/engine.log, nr/model-tools.
#include "model.hpp"
#include "nr_runtime.hpp"

#include <dlfcn.h>
#include <sys/stat.h>
#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cerrno>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

extern "C" {
typedef struct {
    uint64_t image, view;
    uint32_t format, layout, width, height;
} VanaUpscaleImage;

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

// The nr/ files (the shaders, engine.ini.default), packed into the library by build.sh (files.S, pack_files.py).
extern "C" const unsigned char vana_nr_files[], vana_nr_files_end[];

#ifndef VANA_NR_VERSION
#define VANA_NR_VERSION "dev"
#endif

namespace {

constexpr uint32_t kRing = 8;  // per-frame descriptor sets and queries; more than the client's frames in flight

std::string own_dir() {
    Dl_info info{};
    if (!dladdr(reinterpret_cast<void*>(&own_dir), &info) || !info.dli_fname) return ".";
    std::string p = info.dli_fname;
    const auto slash = p.rfind('/');
    return slash == std::string::npos ? "." : p.substr(0, slash);
}

std::string root() {
    static const std::string r = std::getenv("VANA_NR_ROOT") ? std::getenv("VANA_NR_ROOT") : own_dir() + "/nr";
    return r;
}

void log(const char* fmt, ...) {
    char line[1024];
    va_list ap; va_start(ap, fmt); std::vsnprintf(line, sizeof line, fmt, ap); va_end(ap);
    std::fprintf(stderr, "[vana-nr] %s\n", line);
    static FILE* f = std::fopen((root() + "/engine.log").c_str(), "w");
    if (f) std::fprintf(f, "%s\n", line), std::fflush(f);
}

// Writes the packed files into nr/ when nr/.files does not name this pack yet. Empty, or why it failed.
std::string unpack() {
    static std::mutex m;
    static std::string done;
    const std::lock_guard lock(m);
    if (done == "ok") return {};
    namespace fs = std::filesystem;
    const unsigned char* p = vana_nr_files;
    const unsigned char* end = vana_nr_files_end;
    auto u32 = [&] { uint32_t v; std::memcpy(&v, p, 4); p += 4; return v; };
    auto u64 = [&] { uint64_t v; std::memcpy(&v, p, 8); p += 8; return v; };
    if (end - p < 8 || std::memcmp(p, "VNRPACK1", 8) != 0) return done = "the library's packed files are damaged";
    p += 8;
    const uint32_t stamp_len = u32();
    const std::string stamp(reinterpret_cast<const char*>(p), stamp_len);
    p += stamp_len;
    const fs::path dir = root();
    std::error_code ec;
    fs::create_directories(dir, ec);
    {
        std::ifstream f(dir / ".files");
        std::string have;
        if (f && std::getline(f, have) && have == stamp) return done = "ok", std::string{};
    }
    while (p < end) {
        const uint32_t name_len = u32();
        const fs::path rel(std::string(reinterpret_cast<const char*>(p), name_len));
        p += name_len;
        const uint64_t size = u64();
        const fs::path to = dir / rel, part = dir / (rel.string() + ".part");
        fs::create_directories(to.parent_path(), ec);
        {
            std::ofstream o(part, std::ios::binary | std::ios::trunc);
            o.write(reinterpret_cast<const char*>(p), std::streamsize(size));
            if (!o) return done = "cannot write " + part.string() + ": " + std::strerror(errno);
        }
        fs::rename(part, to, ec);
        if (ec) return done = "cannot write " + to.string() + ": " + ec.message();
        p += size;
    }
    std::ofstream(dir / ".files") << stamp << "\n";
    return done = "ok", std::string{};
}

bool has_file(const std::string& rel) {
    struct stat st{};
    return stat((root() + "/" + rel).c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

// The models made from the player's nvngx_dlssnr.dll: 1 small (310.9.16), 0 original (310.9.16 and 310.8.0).
bool has_model(int model) { return has_file(model ? "dlssnr-amd/dlssnr-small.bin" : "dlssnr-amd/dlssnr.bin"); }

int put(char* msg, uint32_t size, int code, const std::string& text) {
    if (msg && size) std::snprintf(msg, size, "%s", text.c_str());
    return code;
}

// nr/engine.ini; every key optional.
struct Settings {
    int model = 1;               // model = small | original
    float scale = 1.0f;          // network size as a fraction of the render size, 0.25..1
    int reuse_every = 2;         // run the network every Nth frame (1 = every frame)
    float reuse_gate = 40.0f;    // most motion (1080p pixels) a reused frame may carry
    int style = 0;               // 0 standard, 1 natural, 2 cinematic
    float intensity = 1.0f;      // 0..2
    float local_tone = 1.0f;     // 0..2
    float local_structure = 1.0f;// 0..2
    float skin_structure = -1.0f;// -1 stock .. 1
    float exposure_ev = 0.0f;    // gain on what the network is shown, undone after
    float strength = -1.0f;      // edit strength; negative: 1 at full size, 0.49 + 0.52 * scale below it
    float color = 0.0f;          // share of the network's colour change, 0 (lightness only) .. 1
    float chroma_clamp = 1.0f;   // most colour change, in stops
    float vivid_guard = 1.0f;    // 0..1, how much of the network's dimming of saturated colour is held back
    float history = -1.0f;       // the post block's history blend; negative: the model's own
    int log_every = 600;         // frames between GPU time lines in engine.log

    bool same_build(const Settings& o) const { return model == o.model && scale == o.scale && (reuse_every > 1) == (o.reuse_every > 1); }
    float edit_strength() const { return strength >= 0 ? strength : scale >= 0.999f ? 1.0f : 0.49f + 0.52f * scale; }
};

Settings read_settings(const std::string& path) {
    Settings s;
    std::ifstream f(path);
    std::string line;
    while (std::getline(f, line)) {
        if (const auto hash = line.find_first_of("#;"); hash != std::string::npos) line.resize(hash);
        const auto eq = line.find('=');
        if (eq == std::string::npos) continue;
        auto trim = [](std::string v) { v.erase(0, v.find_first_not_of(" \t")); v.erase(v.find_last_not_of(" \t\r") + 1); return v; };
        const std::string k = trim(line.substr(0, eq)), v = trim(line.substr(eq + 1));
        const float n = std::strtof(v.c_str(), nullptr);
        if (k == "model") s.model = v == "original" ? 0 : 1;
        else if (k == "scale") s.scale = std::clamp(n, 0.25f, 1.0f);
        else if (k == "reuse_every") s.reuse_every = std::clamp(int(n), 1, 8);
        else if (k == "reuse_gate") s.reuse_gate = std::max(n, 0.0f);
        else if (k == "style") s.style = std::clamp(int(n), 0, 2);
        else if (k == "intensity") s.intensity = std::clamp(n, 0.0f, 2.0f);
        else if (k == "local_tone") s.local_tone = std::clamp(n, 0.0f, 2.0f);
        else if (k == "local_structure") s.local_structure = std::clamp(n, 0.0f, 2.0f);
        else if (k == "skin_structure") s.skin_structure = std::clamp(n, -1.0f, 1.0f);
        else if (k == "exposure_ev") s.exposure_ev = std::clamp(n, -4.0f, 4.0f);
        else if (k == "strength") s.strength = std::clamp(n, 0.0f, 4.0f);
        else if (k == "color") s.color = std::clamp(n, 0.0f, 1.0f);
        else if (k == "chroma_clamp") s.chroma_clamp = std::clamp(n, 0.0f, 2.0f);
        else if (k == "vivid_guard") s.vivid_guard = std::clamp(n, 0.0f, 1.0f);
        else if (k == "history") s.history = std::clamp(n, 0.0f, 1.0f);
        else if (k == "log_every") s.log_every = std::max(int(n), 1);
    }
    return s;
}

void image_barrier(VkCommandBuffer cb, VkImage img, VkImageLayout from, VkImageLayout to, VkAccessFlags src,
                   VkAccessFlags dst, VkPipelineStageFlags s0, VkPipelineStageFlags s1) {
    VkImageMemoryBarrier b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    b.srcAccessMask = src; b.dstAccessMask = dst; b.oldLayout = from; b.newLayout = to;
    b.srcQueueFamilyIndex = b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.image = img; b.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    vkCmdPipelineBarrier(cb, s0, s1, 0, 0, nullptr, 0, nullptr, 1, &b);
}

void memory_barrier(VkCommandBuffer cb, VkPipelineStageFlags s0, VkAccessFlags a0, VkPipelineStageFlags s1, VkAccessFlags a1) {
    VkMemoryBarrier m{VK_STRUCTURE_TYPE_MEMORY_BARRIER};
    m.srcAccessMask = a0; m.dstAccessMask = a1;
    vkCmdPipelineBarrier(cb, s0, s1, 0, 1, &m, 0, nullptr, 0, nullptr);
}

struct Image {
    VkImage image{};
    VkDeviceMemory memory{};
    VkImageView view{};
};

struct Pass {
    VkDescriptorSetLayout set_layout{};
    VkPipelineLayout layout{};
    VkPipeline pipeline{};
    VkDescriptorSet sets[kRing]{};
};

struct Engine {
    VkPhysicalDevice physical{};
    VkDevice device{};
    float timestamp_ms = 0;  // ms per tick
    Settings settings;
    std::string ini;
    time_t ini_mtime = -1;
    uint64_t frame = 0;

    uint32_t render_w{}, render_h{}, net_w{}, net_h{};
    std::unique_ptr<nr::Runtime> runtime;
    Image work, shown;      // network size: the network's in-place image, and a copy of what it was shown
    bool fresh = true;

    VkSampler linear{}, nearest{};
    Pass prep, compose;
    VkDescriptorPool pool{};
    VkQueryPool queries{};
    double gpu_ms_sum = 0;
    uint32_t gpu_samples = 0, reused = 0;
    bool failed = false;
    bool no_model = false;  // checked again every 2 s or so, so a model made while the game runs is picked up

    uint32_t memory_type(uint32_t bits) const {
        VkPhysicalDeviceMemoryProperties mem;
        vkGetPhysicalDeviceMemoryProperties(physical, &mem);
        for (uint32_t i = 0; i < mem.memoryTypeCount; ++i)
            if ((bits & (1u << i)) && (mem.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) return i;
        throw std::runtime_error("no device-local memory type");
    }

    Image make_image(uint32_t w, uint32_t h) {
        Image im;
        VkImageCreateInfo ii{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
        ii.imageType = VK_IMAGE_TYPE_2D; ii.format = VK_FORMAT_R16G16B16A16_SFLOAT;
        ii.extent = {w, h, 1}; ii.mipLevels = ii.arrayLayers = 1; ii.samples = VK_SAMPLE_COUNT_1_BIT;
        ii.tiling = VK_IMAGE_TILING_OPTIMAL;
        ii.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                   VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        if (vkCreateImage(device, &ii, nullptr, &im.image) != VK_SUCCESS) throw std::runtime_error("image");
        VkMemoryRequirements req;
        vkGetImageMemoryRequirements(device, im.image, &req);
        VkMemoryAllocateInfo mi{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
        mi.allocationSize = req.size; mi.memoryTypeIndex = memory_type(req.memoryTypeBits);
        if (vkAllocateMemory(device, &mi, nullptr, &im.memory) != VK_SUCCESS) throw std::runtime_error("image memory");
        vkBindImageMemory(device, im.image, im.memory, 0);
        VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
        vi.image = im.image; vi.viewType = VK_IMAGE_VIEW_TYPE_2D; vi.format = ii.format;
        vi.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        vkCreateImageView(device, &vi, nullptr, &im.view);
        return im;
    }

    void free_image(Image& im) {
        if (im.view) vkDestroyImageView(device, im.view, nullptr);
        if (im.image) vkDestroyImage(device, im.image, nullptr);
        if (im.memory) vkFreeMemory(device, im.memory, nullptr);
        im = {};
    }

    Pass make_pass(const char* spv, uint32_t samplers, uint32_t storages, uint32_t push_bytes) {
        Pass p;
        std::ifstream f(root() + "/" + spv, std::ios::binary);
        if (!f) throw std::runtime_error(std::string("cannot read nr/") + spv);
        std::vector<char> code((std::istreambuf_iterator<char>(f)), {});
        VkShaderModuleCreateInfo smi{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
        smi.codeSize = code.size(); smi.pCode = reinterpret_cast<const uint32_t*>(code.data());
        VkShaderModule module{};
        if (vkCreateShaderModule(device, &smi, nullptr, &module) != VK_SUCCESS) throw std::runtime_error("shader module");
        std::vector<VkDescriptorSetLayoutBinding> b;
        for (uint32_t i = 0; i < samplers + storages; ++i)
            b.push_back({i, i < samplers ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1,
                         VK_SHADER_STAGE_COMPUTE_BIT, nullptr});
        VkDescriptorSetLayoutCreateInfo li{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
        li.bindingCount = uint32_t(b.size()); li.pBindings = b.data();
        vkCreateDescriptorSetLayout(device, &li, nullptr, &p.set_layout);
        VkPushConstantRange pc{VK_SHADER_STAGE_COMPUTE_BIT, 0, push_bytes};
        VkPipelineLayoutCreateInfo pli{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
        pli.setLayoutCount = 1; pli.pSetLayouts = &p.set_layout; pli.pushConstantRangeCount = 1; pli.pPushConstantRanges = &pc;
        vkCreatePipelineLayout(device, &pli, nullptr, &p.layout);
        VkComputePipelineCreateInfo ci{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
        ci.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_COMPUTE_BIT, module, "main", nullptr};
        ci.layout = p.layout;
        const VkResult r = vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &ci, nullptr, &p.pipeline);
        vkDestroyShaderModule(device, module, nullptr);
        if (r != VK_SUCCESS) throw std::runtime_error(std::string("pipeline ") + spv);
        std::vector<VkDescriptorSetLayout> layouts(kRing, p.set_layout);
        VkDescriptorSetAllocateInfo ai{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
        ai.descriptorPool = pool; ai.descriptorSetCount = kRing; ai.pSetLayouts = layouts.data();
        if (vkAllocateDescriptorSets(device, &ai, p.sets) != VK_SUCCESS) throw std::runtime_error("descriptor sets");
        return p;
    }

    void init(const VanaUpscaleFrame& f) {
        device = reinterpret_cast<VkDevice>(f.device);
        physical = reinterpret_cast<VkPhysicalDevice>(f.physical_device);
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(physical, &props);
        timestamp_ms = props.limits.timestampPeriod / 1e6f;

        VkSamplerCreateInfo si{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
        si.addressModeU = si.addressModeV = si.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        si.magFilter = si.minFilter = VK_FILTER_LINEAR;
        vkCreateSampler(device, &si, nullptr, &linear);
        si.magFilter = si.minFilter = VK_FILTER_NEAREST;
        vkCreateSampler(device, &si, nullptr, &nearest);

        VkDescriptorPoolSize sizes[2] = {{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 4 * kRing},
                                         {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 3 * kRing}};
        VkDescriptorPoolCreateInfo pi{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
        pi.maxSets = 2 * kRing; pi.poolSizeCount = 2; pi.pPoolSizes = sizes;
        vkCreateDescriptorPool(device, &pi, nullptr, &pool);
        prep = make_pass("prep.spv", 1, 2, 12);
        compose = make_pass("compose.spv", 3, 1, 28);

        VkQueryPoolCreateInfo qi{VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO};
        qi.queryType = VK_QUERY_TYPE_TIMESTAMP; qi.queryCount = 2 * kRing;
        if (vkCreateQueryPool(device, &qi, nullptr, &queries) != VK_SUCCESS) queries = {};

        ini = root() + "/engine.ini";
        // First run: the commented defaults (engine.ini.default) become the user's engine.ini.
        if (struct stat st{}; stat(ini.c_str(), &st) != 0) {
            std::ifstream from(ini + ".default", std::ios::binary);
            if (from) std::ofstream(ini, std::ios::binary) << from.rdbuf();
        }
        reload(true);
    }

    // Re-reads engine.ini when it changed; true when the runtime must be rebuilt.
    bool reload(bool first = false) {
        struct stat st{};
        const time_t m = stat(ini.c_str(), &st) == 0 ? st.st_mtime : 0;
        if (!first && m == ini_mtime) return false;
        ini_mtime = m;
        const Settings s = read_settings(ini);
        const bool rebuild = !first && !s.same_build(settings);
        settings = s;
        log("settings: model %s, scale %.2f, reuse every %d, style %d, intensity %.2f, tone %.2f, structure %.2f, "
            "exposure %+.1f EV, strength %.2f, color %.2f, chroma clamp %.2f, vivid guard %.2f", s.model ? "small" : "original", s.scale, s.reuse_every, s.style,
            s.intensity, s.local_tone, s.local_structure, s.exposure_ev, s.edit_strength(), s.color, s.chroma_clamp, s.vivid_guard);
        return rebuild;
    }

    void destroy_sized() {
        if (runtime || work.image) vkDeviceWaitIdle(device);
        runtime.reset();
        free_image(work); free_image(shown);
        render_w = render_h = 0;
    }

    void make_sized(const VanaUpscaleFrame& f) {
        destroy_sized();
        render_w = f.color.width; render_h = f.color.height;
        net_w = std::max(64u, uint32_t(std::lround(render_w * settings.scale)) & ~1u);
        net_h = std::max(64u, uint32_t(std::lround(render_h * settings.scale)) & ~1u);
        work = make_image(net_w, net_h);
        shown = make_image(net_w, net_h);
        fresh = true;

        nr::HostDevice host;
        host.instance = reinterpret_cast<VkInstance>(f.instance);
        host.physical = physical; host.device = device;
        host.queue = reinterpret_cast<VkQueue>(f.queue); host.queue_family = f.queue_family;
        nr::RuntimeConfig config;
        config.root = root(); config.width = net_w; config.height = net_h;
        config.colour_format = VK_FORMAT_R16G16B16A16_SFLOAT;
        config.motion_point = true;
        config.network = settings.model == 1 && !has_model(1) ? 0 : settings.model;  // 310.8.0 makes the original only
        if (config.network != settings.model) log("model small asked for, but only the original is installed: using it");
        config.reuse = settings.reuse_every > 1;
        nr::TemporalConfig temporal;
        temporal.enable = true;
        temporal.shaders = root() + "/dlssnr-amd/shaders/temporal";
        runtime = std::make_unique<nr::Runtime>(host, config, nr::ControlMaskConfig{}, temporal);
        log("runtime: render %ux%u, network %ux%u", render_w, render_h, net_w, net_h);
    }

    void bind(VkCommandBuffer cb, Pass& p, const std::vector<VkDescriptorImageInfo>& images, uint32_t samplers) {
        VkDescriptorSet set = p.sets[frame % kRing];
        std::vector<VkWriteDescriptorSet> w(images.size());
        for (uint32_t i = 0; i < images.size(); ++i)
            w[i] = {VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, nullptr, set, i, 0, 1,
                    i < samplers ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, &images[i]};
        vkUpdateDescriptorSets(device, uint32_t(w.size()), w.data(), 0, nullptr);
        vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, p.pipeline);
        vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, p.layout, 0, 1, &set, 0, nullptr);
    }

    void read_timing() {
        if (!queries || frame < kRing) return;
        const uint32_t slot = frame % kRing;  // written kRing frames ago
        uint64_t t[2]{};
        if (vkGetQueryPoolResults(device, queries, 2 * slot, 2, sizeof t, t, sizeof(uint64_t), VK_QUERY_RESULT_64_BIT) == VK_SUCCESS) {
            gpu_ms_sum += double(t[1] - t[0]) * timestamp_ms;
            ++gpu_samples;
        }
        if (gpu_samples >= uint32_t(settings.log_every)) {
            log("gpu %.2f ms a frame (network %ux%u, %u of the last %u frames reused its edit)", gpu_ms_sum / gpu_samples,
                net_w, net_h, reused, gpu_samples);
            gpu_ms_sum = 0; gpu_samples = 0; reused = 0;
        }
    }

    int dispatch(const VanaUpscaleFrame& f) {
        if (failed) return 1;
        if (no_model || !device) {
            if (no_model && ++frame % 240) return 1;
            no_model = !has_model(0) && !has_model(1);
            if (no_model) { if (frame <= 1) log("no model: nr/dlssnr-amd/ has neither dlssnr.bin nor dlssnr-small.bin"); return 1; }
        }
        if (f.version != 1 || !f.command_buffer || !f.color.image || !f.output.image || !f.motion.image) return 1;
        if (f.output.width != f.color.width || f.output.height != f.color.height) return 1;  // pre-upscale only
        if (!device) init(f);
        if ((frame % 30 == 0 && reload()) || f.color.width != render_w || f.color.height != render_h) make_sized(f);
        read_timing();

        const auto cb = reinterpret_cast<VkCommandBuffer>(f.command_buffer);
        const uint32_t slot = frame % kRing;
        const VkAccessFlags all = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
        memory_barrier(cb, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_ACCESS_MEMORY_WRITE_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, all);
        if (queries) {  // after the client's work, so the time is the engine's own
            vkCmdResetQueryPool(cb, queries, 2 * slot, 2);
            vkCmdWriteTimestamp(cb, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, queries, 2 * slot);
        }
        if (fresh) {
            for (VkImage im : {work.image, shown.image})
                image_barrier(cb, im, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL, 0, VK_ACCESS_SHADER_WRITE_BIT,
                              VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT);
            fresh = false;
        }
        const float gain = std::exp2(settings.exposure_ev);
        const auto color_view = reinterpret_cast<VkImageView>(f.color.view);
        const auto color_layout = VkImageLayout(f.color.layout);

        // the frame -> the network's input
        bind(cb, prep, {{linear, color_view, color_layout}, {VK_NULL_HANDLE, work.view, VK_IMAGE_LAYOUT_GENERAL},
                        {VK_NULL_HANDLE, shown.view, VK_IMAGE_LAYOUT_GENERAL}}, 1);
        struct { uint32_t w, h; float gain; } pp{net_w, net_h, gain};
        vkCmdPushConstants(cb, prep.layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof pp, &pp);
        vkCmdDispatch(cb, (net_w + 7) / 8, (net_h + 7) / 8, 1);

        nr::EngineFrame ef;
        ef.colour.image = work.image; ef.colour.format = VK_FORMAT_R16G16B16A16_SFLOAT;
        ef.colour.width = net_w; ef.colour.height = net_h;
        ef.colour.before = ef.colour.after = VK_IMAGE_LAYOUT_GENERAL;
        ef.colour.before_stage = VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT; ef.colour.before_access = VK_ACCESS_SHADER_WRITE_BIT;
        ef.colour.after_stage = VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT; ef.colour.after_access = VK_ACCESS_SHADER_READ_BIT;
        ef.colour.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                          VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        ef.motion.image = reinterpret_cast<VkImage>(f.motion.image); ef.motion.format = VkFormat(f.motion.format);
        ef.motion.width = f.motion.width; ef.motion.height = f.motion.height;
        ef.motion.before = ef.motion.after = VkImageLayout(f.motion.layout);
        ef.motion.usage = VK_IMAGE_USAGE_SAMPLED_BIT;
        ef.motion_scale_x = 1.0f / float(f.motion.width);  // render pixels -> uv
        ef.motion_scale_y = 1.0f / float(f.motion.height);
        if (f.depth.image) {
            ef.depth.image = reinterpret_cast<VkImage>(f.depth.image); ef.depth.format = VkFormat(f.depth.format);
            ef.depth.width = f.depth.width; ef.depth.height = f.depth.height;
            ef.depth.before = ef.depth.after = VkImageLayout(f.depth.layout);
            ef.depth.usage = VK_IMAGE_USAGE_SAMPLED_BIT;
            ef.depth_inverted = f.reversed_z != 0;
        }
        ef.reset = f.reset != 0;
        ef.feature = 1;
        nr::Controls c;
        c.style = settings.style; c.intensity = settings.intensity;
        c.local_tone = settings.local_tone; c.local_structure = settings.local_structure;
        c.skin_structure = settings.skin_structure;
        c.history_strength = settings.history;
        c.reuse_every = settings.reuse_every > 1 ? settings.reuse_every : 0;
        c.reuse_gate = settings.reuse_gate;
        const auto r = runtime->record_engine(cb, ef, c);
        reused += r.frame.reused ? 1 : 0;

        // the edit -> the client's output
        bind(cb, compose, {{nearest, color_view, color_layout}, {linear, shown.view, VK_IMAGE_LAYOUT_GENERAL},
                           {linear, work.view, VK_IMAGE_LAYOUT_GENERAL},
                           {VK_NULL_HANDLE, reinterpret_cast<VkImageView>(f.output.view), VK_IMAGE_LAYOUT_GENERAL}}, 3);
        struct { uint32_t w, h; float gain, strength, color, chroma_clamp, vivid_guard; } cp{render_w, render_h, gain, settings.edit_strength(),
                                                                         settings.color, settings.chroma_clamp, settings.vivid_guard};
        vkCmdPushConstants(cb, compose.layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof cp, &cp);
        vkCmdDispatch(cb, (render_w + 7) / 8, (render_h + 7) / 8, 1);
        memory_barrier(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_ACCESS_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                       VK_ACCESS_MEMORY_READ_BIT);
        if (queries) vkCmdWriteTimestamp(cb, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, queries, 2 * slot + 1);
        ++frame;
        return 0;
    }
};

// Leaked on purpose: at exit the client's device may already be gone.
Engine& engine() { static Engine* e = new Engine; return *e; }

}  // namespace

extern "C" __attribute__((visibility("default"))) int vana_nr_dispatch(const VanaUpscaleFrame* f) {
    try {
        if (const std::string e = unpack(); !e.empty()) throw std::runtime_error(e);
        return f ? engine().dispatch(*f) : 1;
    } catch (const std::exception& e) {
        engine().failed = true;
        log("disabled: %s", e.what());
        return 1;
    }
}

// The engine's version: the vana-client release it was built with.
extern "C" __attribute__((visibility("default"))) const char* vana_nr_version() { return VANA_NR_VERSION; }

// The model's state, without a device. 0 ready, 1 no model, 2 the engine's files cannot be written; msg says which.
extern "C" __attribute__((visibility("default"))) int vana_nr_model_status(char* msg, uint32_t size) {
    try {
        if (const std::string e = unpack(); !e.empty()) return put(msg, size, 2, e);
        const bool small = has_model(1), original = has_model(0);
        if (small && original) return put(msg, size, 0, "Ready: the small and original models.");
        if (small || original) return put(msg, size, 0, small ? "Ready: the small model." : "Ready: the original model.");
        return put(msg, size, 1, "Needs NVIDIA's nvngx_dlssnr.dll, version 310.9.16 or 310.8.0.");
    } catch (const std::exception& e) {
        return put(msg, size, 2, e.what());
    }
}

// Whether `path` (nvngx_dlssnr.dll or a zip holding it) can make the model. 0 yes (msg: what it makes), 1 no (why).
extern "C" __attribute__((visibility("default"))) int vana_nr_check_dll(const char* path, char* msg, uint32_t size) {
    try {
        vana_model::DllInfo info;
        std::string err;
        if (!path || !vana_model::check(path, info, err)) return put(msg, size, 1, err.empty() ? "No file." : err);
        return put(msg, size, 0, "nvngx_dlssnr " + info.version + (info.small ? ": the small and original models." : ": the original model."));
    } catch (const std::exception& e) {
        return put(msg, size, 1, e.what());
    }
}

// Makes the model into nr/dlssnr-amd/ from `path`. Blocks for a while: call it off the render thread. progress may be
// null. 0 done, 1 failed; msg says what was made or why not. Reads only the DLL's weight data; never loads or runs it.
extern "C" __attribute__((visibility("default"))) int vana_nr_make_model(const char* path, void (*progress)(float, void*),
                                                                         void* user, char* msg, uint32_t size) {
    try {
        if (const std::string e = unpack(); !e.empty()) return put(msg, size, 1, e);
        std::error_code ec;
        std::filesystem::create_directories(root() + "/dlssnr-amd", ec);
        std::string err;
        const auto report = [&](float x) { if (progress) progress(x, user); };
        if (!path || !vana_model::make(path, root() + "/dlssnr-amd", report, err)) return put(msg, size, 1, err.empty() ? "No file." : err);
        char status[256];
        vana_nr_model_status(status, sizeof status);
        log("model made from %s", path);
        return put(msg, size, 0, status);
    } catch (const std::exception& e) {
        return put(msg, size, 1, e.what());
    }
}
