// A port of DLSSNR-RDNA3's model-tools (mauri870, MIT, from mochizuki0323's DLSSNR-AMD): extract_model.sh,
// inspect_nr.py, the unpack_*.py scripts and pack_model.py, byte for byte. Reads the DLL as data only.
#include "model.hpp"
#include "model_tables.hpp"

#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <iterator>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <vector>

namespace vana_model {
namespace {

using Bytes = std::vector<uint8_t>;
using vana_model_tables::Op;
using vana_model_tables::Step;

struct Fail : std::runtime_error { using std::runtime_error::runtime_error; };

// ---- SHA-256 ----
struct Sha256 {
    uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    uint8_t buf[64]; size_t used = 0; uint64_t total = 0;
    static uint32_t ror(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
    void block(const uint8_t* p) {
        static const uint32_t k[64] = {
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
            0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
            0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
            0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
            0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
            0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
        uint32_t w[64];
        for (int i = 0; i < 16; ++i) w[i] = uint32_t(p[4 * i]) << 24 | uint32_t(p[4 * i + 1]) << 16 | uint32_t(p[4 * i + 2]) << 8 | p[4 * i + 3];
        for (int i = 16; i < 64; ++i) {
            const uint32_t s0 = ror(w[i - 15], 7) ^ ror(w[i - 15], 18) ^ (w[i - 15] >> 3);
            const uint32_t s1 = ror(w[i - 2], 17) ^ ror(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
        for (int i = 0; i < 64; ++i) {
            const uint32_t t1 = hh + (ror(e, 6) ^ ror(e, 11) ^ ror(e, 25)) + ((e & f) ^ (~e & g)) + k[i] + w[i];
            const uint32_t t2 = (ror(a, 2) ^ ror(a, 13) ^ ror(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
            hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
        }
        h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
    }
    void add(const uint8_t* p, size_t n) {
        total += n;
        if (used) {
            const size_t take = std::min(n, 64 - used);
            std::memcpy(buf + used, p, take); used += take; p += take; n -= take;
            if (used == 64) block(buf), used = 0;
        }
        for (; n >= 64; p += 64, n -= 64) block(p);
        if (n) std::memcpy(buf, p, n), used = n;
    }
    void done(uint8_t out[32]) {
        const uint64_t bits = total * 8;
        const uint8_t pad = 0x80, zero = 0;
        add(&pad, 1);
        while (used != 56) add(&zero, 1);
        uint8_t len[8];
        for (int i = 0; i < 8; ++i) len[i] = uint8_t(bits >> (56 - 8 * i));
        add(len, 8);
        for (int i = 0; i < 8; ++i) for (int j = 0; j < 4; ++j) out[4 * i + j] = uint8_t(h[i] >> (24 - 8 * j));
    }
};

void sha256(const uint8_t* p, size_t n, uint8_t out[32]) { Sha256 s; s.add(p, n); s.done(out); }

std::string hex(const uint8_t* d, size_t n) {
    static const char* x = "0123456789abcdef";
    std::string s;
    for (size_t i = 0; i < n; ++i) s += x[d[i] >> 4], s += x[d[i] & 15];
    return s;
}

// ---- The input: the DLL, mapped, or inflated out of a zip ----
struct Input {
    const uint8_t* p = nullptr; size_t n = 0;
    void* map = nullptr; size_t map_n = 0;
    Bytes inflated;
    ~Input() { if (map) munmap(map, map_n); }
};

template <class T> T rd(const uint8_t* p, size_t n, size_t off) {
    if (off > n || n - off < sizeof(T)) throw Fail("out of bounds");
    T v; std::memcpy(&v, p + off, sizeof v); return v;
}

// The member named nvngx_dlssnr.dll (zipfile's rules: exactly one, at most 1 GiB, CRC checked).
void unzip(Input& in) {
    const uint8_t* z = in.p; const size_t n = in.n;
    size_t eocd = SIZE_MAX;
    for (size_t i = n >= 22 ? n - 22 : 0, stop = n > 22 + 65535 ? n - 22 - 65535 : 0;; --i) {
        if (n >= 22 && rd<uint32_t>(z, n, i) == 0x06054b50) { eocd = i; break; }
        if (i == stop) break;
    }
    if (eocd == SIZE_MAX) return;  // not a zip: the DLL itself
    uint64_t count = rd<uint16_t>(z, n, eocd + 10), cd = rd<uint32_t>(z, n, eocd + 16);
    if ((count == 0xFFFF || cd == 0xFFFFFFFF) && eocd >= 20 && rd<uint32_t>(z, n, eocd - 20) == 0x07064b50) {
        const uint64_t e64 = rd<uint64_t>(z, n, eocd - 12);
        if (rd<uint32_t>(z, n, e64) != 0x06064b50) throw Fail("bad zip64 record");
        count = rd<uint64_t>(z, n, e64 + 32); cd = rd<uint64_t>(z, n, e64 + 48);
    }
    struct Member { uint64_t csize, usize, local; uint16_t method, flags; uint32_t crc; };
    std::vector<Member> found;
    size_t o = cd;
    for (uint64_t i = 0; i < count; ++i) {
        if (rd<uint32_t>(z, n, o) != 0x02014b50) throw Fail("bad zip directory");
        Member m{rd<uint32_t>(z, n, o + 20), rd<uint32_t>(z, n, o + 24), rd<uint32_t>(z, n, o + 42),
                 rd<uint16_t>(z, n, o + 10), rd<uint16_t>(z, n, o + 8), rd<uint32_t>(z, n, o + 16)};
        const uint16_t nl = rd<uint16_t>(z, n, o + 28), xl = rd<uint16_t>(z, n, o + 30), cl = rd<uint16_t>(z, n, o + 32);
        if (o + 46 + nl > n) throw Fail("bad zip directory");
        std::string name(reinterpret_cast<const char*>(z + o + 46), nl);
        for (size_t x = o + 46 + nl; x + 4 <= o + 46 + nl + xl;) {  // zip64 sizes and offset
            const uint16_t id = rd<uint16_t>(z, n, x), len = rd<uint16_t>(z, n, x + 2);
            if (id == 1) {
                size_t f = x + 4;
                if (m.usize == 0xFFFFFFFF) m.usize = rd<uint64_t>(z, n, f), f += 8;
                if (m.csize == 0xFFFFFFFF) m.csize = rd<uint64_t>(z, n, f), f += 8;
                if (m.local == 0xFFFFFFFF) m.local = rd<uint64_t>(z, n, f);
            }
            x += 4 + len;
        }
        const auto slash = name.rfind('/');
        std::string base = slash == std::string::npos ? name : name.substr(slash + 1);
        for (auto& c : base) c = char(std::tolower(static_cast<unsigned char>(c)));
        if (base == "nvngx_dlssnr.dll") found.push_back(m);
        o += 46 + nl + xl + cl;
    }
    if (found.size() != 1) throw Fail(found.empty() ? "The zip has no nvngx_dlssnr.dll in it." : "The zip has more than one nvngx_dlssnr.dll in it.");
    const Member& m = found[0];
    if (m.usize > (1u << 30)) throw Fail("The nvngx_dlssnr.dll in the zip is too large.");
    if (m.flags & 1) throw Fail("The zip is encrypted.");
    if (rd<uint32_t>(z, n, m.local) != 0x04034b50) throw Fail("bad zip entry");
    const size_t data = m.local + 30 + rd<uint16_t>(z, n, m.local + 26) + rd<uint16_t>(z, n, m.local + 28);
    if (data > n || n - data < m.csize) throw Fail("The zip is cut short.");
    in.inflated.resize(m.usize);
    if (m.method == 0) {
        if (m.csize != m.usize) throw Fail("bad zip entry");
        std::memcpy(in.inflated.data(), z + data, m.usize);
    } else if (m.method == 8) {
        z_stream s{};
        if (inflateInit2(&s, -15) != Z_OK) throw Fail("zlib failed");
        s.next_in = const_cast<Bytef*>(z + data); s.avail_in = uInt(m.csize);
        s.next_out = in.inflated.data(); s.avail_out = uInt(m.usize);
        const int r = inflate(&s, Z_FINISH);
        inflateEnd(&s);
        if (r != Z_STREAM_END || s.total_out != m.usize) throw Fail("The zip's nvngx_dlssnr.dll is damaged.");
    } else {
        throw Fail("The zip uses a compression method that is not supported.");
    }
    if (crc32(0, in.inflated.data(), uInt(m.usize)) != m.crc) throw Fail("The zip's nvngx_dlssnr.dll is damaged.");
    munmap(in.map, in.map_n); in.map = nullptr;
    in.p = in.inflated.data(); in.n = in.inflated.size();
}

void load(const std::string& path, Input& in) {
    const int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) throw Fail("Cannot open " + path + ".");
    struct stat st{};
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size == 0) { ::close(fd); throw Fail(path + " is not a file."); }
    in.map_n = size_t(st.st_size);
    in.map = mmap(nullptr, in.map_n, PROT_READ, MAP_PRIVATE, fd, 0);
    ::close(fd);
    if (in.map == MAP_FAILED) { in.map = nullptr; throw Fail("Cannot read " + path + "."); }
    in.p = static_cast<const uint8_t*>(in.map); in.n = in.map_n;
    unzip(in);
}

// ---- The PE and its resources (inspect_nr.py) ----
struct Section { uint32_t rva, vsize, raw, size; };
struct Resource { std::vector<std::string> path; size_t off, size; };

struct Pe {
    const uint8_t* p; size_t n;
    std::vector<Section> sections;
    uint32_t res_rva = 0, res_size = 0;

    Pe(const uint8_t* d, size_t len) : p(d), n(len) {
        if (n < 2 || p[0] != 'M' || p[1] != 'Z') throw Fail("not a PE file");
        const uint32_t pe = rd<uint32_t>(p, n, 0x3c);
        if (rd<uint32_t>(p, n, pe) != 0x00004550) throw Fail("missing PE signature");
        const uint16_t count = rd<uint16_t>(p, n, pe + 6), opt_size = rd<uint16_t>(p, n, pe + 20);
        const size_t opt = pe + 24;
        if (rd<uint16_t>(p, n, opt) != 0x20b || opt_size < 144) throw Fail("expected PE32+ optional header");
        res_rva = rd<uint32_t>(p, n, opt + 128); res_size = rd<uint32_t>(p, n, opt + 132);
        for (uint16_t i = 0; i < count; ++i) {
            const size_t o = opt + opt_size + 40 * i;
            Section s{rd<uint32_t>(p, n, o + 12), rd<uint32_t>(p, n, o + 8), rd<uint32_t>(p, n, o + 20), rd<uint32_t>(p, n, o + 16)};
            if (size_t(s.raw) + s.size > n) throw Fail("section out of bounds");
            sections.push_back(s);
        }
    }
    size_t offset(uint32_t rva, uint32_t size) const {
        for (const auto& s : sections) {
            const int64_t delta = int64_t(rva) - s.rva;
            if (delta >= 0 && delta + size <= s.size) return s.raw + size_t(delta);
        }
        throw Fail("RVA not backed by file");
    }
    std::vector<Resource> resources() const {
        std::vector<Resource> out;
        if (!res_rva) return out;
        const size_t root = offset(res_rva, res_size);
        const uint8_t* t = p + root; const size_t tn = res_size;
        std::set<uint32_t> active;
        std::vector<std::string> path;
        std::function<void(uint32_t)> walk = [&](uint32_t rel) {
            if (active.count(rel) || path.size() > 8) throw Fail("cyclic or excessively deep resource tree");
            active.insert(rel);
            const uint32_t entries = uint32_t(rd<uint16_t>(t, tn, rel + 12)) + rd<uint16_t>(t, tn, rel + 14);
            for (uint32_t i = 0; i < entries; ++i) {
                const uint32_t name = rd<uint32_t>(t, tn, rel + 16 + 8 * i), child = rd<uint32_t>(t, tn, rel + 20 + 8 * i);
                std::string label;
                if (name & 0x80000000u) {
                    const uint32_t o = name & 0x7fffffff;
                    const uint16_t len = rd<uint16_t>(t, tn, o);
                    for (uint16_t c = 0; c < len; ++c) {
                        const uint16_t u = rd<uint16_t>(t, tn, o + 2 + 2 * c);
                        label += u < 0x80 ? char(u) : '\x7f';  // compared with ASCII names only
                    }
                } else {
                    label = std::to_string(name);
                }
                path.push_back(label);
                if (child & 0x80000000u) {
                    walk(child & 0x7fffffff);
                } else {
                    const uint32_t rva = rd<uint32_t>(t, tn, child), size = rd<uint32_t>(t, tn, child + 4);
                    out.push_back({path, offset(rva, size), size});
                }
                path.pop_back();
            }
            active.erase(rel);
        };
        walk(0);
        return out;
    }
};

// "a.b.c.d" from the version resource, or "".
std::string file_version(const Pe& pe, const std::vector<Resource>& res) {
    for (const auto& r : res) {
        if (r.path.empty() || r.path[0] != "16") continue;
        for (size_t i = r.off; i + 16 <= r.off + r.size; i += 4)
            if (rd<uint32_t>(pe.p, pe.n, i) == 0xFEEF04BDu) {
                const uint32_t ms = rd<uint32_t>(pe.p, pe.n, i + 8), ls = rd<uint32_t>(pe.p, pe.n, i + 12);
                return std::to_string(ms >> 16) + "." + std::to_string(ms & 0xffff) + "." + std::to_string(ls >> 16) + "." + std::to_string(ls & 0xffff);
            }
    }
    return "";
}

struct Record { size_t off, size; };

// The weight map (parse_weights): name -> payload, offsets into the DLL.
std::map<std::string, Record> weights(const Pe& pe, const char* resource) {
    const Resource* hit = nullptr; int hits = 0;
    const auto res = pe.resources();
    for (const auto& r : res)
        for (const auto& l : r.path)
            if (l == resource) { hit = &r; ++hits; break; }
    if (hits != 1) throw Fail(std::string("expected exactly one ") + resource + " resource");
    const uint8_t* d = pe.p + hit->off; const size_t n = hit->size;
    if (rd<uint64_t>(d, n, 0) != n) throw Fail("weight map size mismatch");
    std::map<std::string, Record> out;
    size_t p = 8;
    while (p < n) {
        const uint64_t name_size = rd<uint64_t>(d, n, p); p += 8;
        if (name_size == 0 || name_size > 4096 || p + name_size > n) throw Fail("invalid weight name length");
        std::string name(reinterpret_cast<const char*>(d + p), name_size); p += name_size;
        const uint64_t outer = rd<uint64_t>(d, n, p); p += 8;
        if (outer > n - p) throw Fail("weight record out of bounds");
        const uint8_t* body = d + p;
        const uint64_t inner = rd<uint64_t>(body, outer, 0), raw = rd<uint64_t>(body, outer, 8);
        const uint32_t device = rd<uint32_t>(body, outer, 16);
        if (inner != outer) throw Fail(name + ": inner/outer sizes differ");
        if (!raw || device > 1 || raw > outer - 20) throw Fail(name + ": empty data or non-host device");
        const uint64_t ndim = rd<uint64_t>(body, outer, 28 + raw);
        if (ndim > 32 || 36 + raw + 4 * ndim != inner) throw Fail(name + ": bad metadata");
        if (!out.emplace(name, Record{hit->off + p + 20, size_t(raw)}).second) throw Fail("duplicate weight name: " + name);
        p += outer;
    }
    if (p != n) throw Fail("weight map did not end exactly at resource boundary");
    return out;
}

// ---- The four re-orderings (unpack_*.py) ----
size_t step_size(const Step& s, const Record& r) {
    switch (s.op) {
        case Op::RAW: return (s.a[1] == 0xFFFFFFFFu ? r.size : s.a[1]) - s.a[0];
        case Op::SWIN: case Op::SPLIT: return size_t(s.a[1]) * s.a[2];
        case Op::QKV: return 1024 * 1024;
        case Op::OUTPROJ: return 1024;
    }
    return 0;
}

void build_step(const Step& s, const uint8_t* p, size_t n, Bytes& out) {
    auto at = [&](size_t i) -> uint8_t { if (i >= n) throw Fail("weight record shorter than its layout"); return p[i]; };
    switch (s.op) {
        case Op::RAW: {
            const size_t a = s.a[0], b = s.a[1] == 0xFFFFFFFFu ? n : s.a[1];
            if (a > b || b > n) throw Fail("weight record shorter than its layout");
            out.assign(p + a, p + b);
            break;
        }
        case Op::SWIN: {  // fragment order -> [N][K], t-major
            const size_t base = s.a[0], N = s.a[1], K = s.a[2], inner = s.a[3], kg = K / 32, st_k = 512 * inner, st_o = st_k * kg;
            out.assign(N * K, 0);
            for (size_t t = 0; t < N / 16; ++t)
                for (size_t g = 0; g < kg; ++g) {
                    const size_t off = base + (t % inner) * 512 + g * st_k + (t / inner) * st_o;
                    for (size_t half = 0; half < 2; ++half)
                        for (size_t r = 0; r < 8; ++r)
                            for (size_t k = 0; k < 32; ++k) {
                                const size_t lane = 4 * r + (k % 8) / 2, byte = 2 * (k / 8) + (k % 2);
                                out[(t * 16 + half * 8 + r) * K + g * 32 + k] = at(off + lane * 16 + half * 8 + byte);
                            }
                }
            break;
        }
        case Op::SPLIT: {  // slice = k_group * (N/16) + n_group
            const size_t base = s.a[0], N = s.a[1], K = s.a[2], ngrp = N / 16, kgrp = K / 32;
            out.assign(N * K, 0);
            for (size_t sl = 0; sl < ngrp * kgrp; ++sl) {
                const size_t ng = sl % ngrp, kgi = sl / ngrp, off = base + sl * 512;
                for (size_t half = 0; half < 2; ++half)
                    for (size_t lane = 0; lane < 32; ++lane) {
                        const size_t row = ng * 16 + half * 8 + lane / 4, src = off + lane * 16 + half * 8;
                        for (size_t byte = 0; byte < 8; ++byte)
                            out[row * K + kgi * 32 + 8 * (byte >> 1) + 2 * (lane % 4) + (byte & 1)] = at(src + byte);
                    }
            }
            break;
        }
        case Op::QKV: {  // Q, K, V alternate in 1024-byte tiles after a 128-byte header
            const size_t which = s.a[0];
            out.assign(1024 * 1024, 0);
            for (size_t row = 0; row < 1024; ++row)
                for (size_t k = 0; k < 1024; ++k) {
                    const size_t b = (k & 1) | ((k >> 1 & 1) << 4) | ((k >> 2 & 1) << 5) | ((k >> 3 & 1) << 1) | ((k >> 4 & 1) << 2) |
                                     ((row & 1) << 6) | ((row >> 1 & 1) << 7) | ((row >> 2 & 1) << 8) | ((row >> 3 & 1) << 3) | ((row >> 4 & 1) << 9);
                    const size_t tile = (row >> 5) | ((k >> 5) << 5);
                    out[row * 1024 + k] = at(128 + (3 * tile + which) * 1024 + b);
                }
            break;
        }
        case Op::OUTPROJ: {  // two 16-K blocks of m16n8k16 B fragments -> FP16[16][32]
            const size_t a = s.a[0];
            out.assign(1024, 0);
            for (size_t r = 0; r < 16; ++r)
                for (size_t k = 0; k < 32; ++k) {
                    const size_t i = (k / 16) * 256 + 32 * (r % 8) + 8 * ((k % 8) / 2) + 4 * (r / 8) + k % 2 + 2 * ((k % 16) / 8);
                    out[2 * (r * 32 + k)] = at(a + 2 * i); out[2 * (r * 32 + k) + 1] = at(a + 2 * i + 1);
                }
            break;
        }
    }
}

// ---- Which DLL ----
struct Known { const char* sha; const char* version; bool small; };
const Known kKnown[] = {
    {"2bc19bc09a7b89dd44f73e2ac0108fcc586e2154bdd0830f242f4f040e28789f", "310.9.16", true},
    {"e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e", "310.8.0", false},
#ifdef VANA_MODEL_TEST_310_8_0  // tests only: one more DLL hash taken as 310.8.0
    {VANA_MODEL_TEST_310_8_0, "310.8.0", false},
#endif
};

bool identify(const Input& in, DllInfo& info, std::string& err) {
    uint8_t d[32];
    sha256(in.p, in.n, d);
    const std::string got = hex(d, 32);
    for (const auto& k : kKnown)
        if (got == k.sha) { info = {k.version, k.small, true}; return true; }
    // Unknown: say what it is, where the file tells.
    try {
        Pe pe(in.p, in.n);
        const auto res = pe.resources();
        bool weights = false;
        for (const auto& r : res) for (const auto& l : r.path) weights |= l == "WEIGHTS_HT" || l == "WEIGHTS_CC_SMALL_FP8";
        const std::string v = file_version(pe, res);
        if (!weights) err = "This is not nvngx_dlssnr.dll: it has no neural rendering network in it.";
        else if (v.rfind("310.9.16.", 0) == 0 || v.rfind("310.8.0.", 0) == 0)
            err = "This nvngx_dlssnr.dll " + v.substr(0, v.rfind('.')) + " has been modified; NVIDIA's original file is needed.";
        else if (!v.empty()) err = "This is nvngx_dlssnr.dll " + v + "; version 310.9.16 or 310.8.0 is needed.";
        else err = "This is not nvngx_dlssnr 310.9.16 or 310.8.0.";
    } catch (const Fail&) {
        err = "This is not nvngx_dlssnr.dll, or a zip holding it.";
    }
    return false;
}

// Writes one model file (pack_model.py's layout) to a temp name, checking every entry; renames it into place.
void pack(const Pe& pe, const char* resource, const Step* steps, size_t count, const std::filesystem::path& dest,
          const std::function<void(size_t)>& advance) {
    const auto recs = weights(pe, resource);
    std::vector<const Record*> rec(count);
    std::vector<size_t> sizes(count);
    for (size_t i = 0; i < count; ++i) {
        const auto it = recs.find(steps[i].record);
        if (it == recs.end()) throw Fail(std::string("the DLL has no weights for ") + steps[i].record);
        if (steps[i].record_size && it->second.size != steps[i].record_size) throw Fail(std::string("unexpected layout of ") + steps[i].record);
        rec[i] = &it->second;
        sizes[i] = step_size(steps[i], it->second);
    }
    // NRMODEL1, u32 count, u32 0; per entry u32 name length, name, u64 offset, u64 size; data 256-byte aligned.
    Bytes index;
    auto put = [&](const void* v, size_t n) { index.insert(index.end(), static_cast<const uint8_t*>(v), static_cast<const uint8_t*>(v) + n); };
    const uint32_t head[2] = {uint32_t(count), 0};
    put("NRMODEL1", 8); put(head, 8);
    size_t header = 16;
    for (size_t i = 0; i < count; ++i) header += 4 + std::strlen(steps[i].name) + 16;
    std::vector<uint64_t> offs(count);
    uint64_t off = (header + 255) / 256 * 256;
    for (size_t i = 0; i < count; ++i) {
        const uint32_t nl = uint32_t(std::strlen(steps[i].name));
        offs[i] = off;
        const uint64_t o_s[2] = {off, sizes[i]};
        put(&nl, 4); put(steps[i].name, nl); put(o_s, 16);
        off = (off + sizes[i] + 255) / 256 * 256;
    }
    const auto tmp = dest.string() + ".part";
    std::unique_ptr<FILE, int (*)(FILE*)> f(std::fopen(tmp.c_str(), "wb"), std::fclose);
    if (!f) throw Fail("Cannot write " + tmp + ".");
    try {
        if (std::fwrite(index.data(), 1, index.size(), f.get()) != index.size()) throw Fail("Cannot write " + tmp + ".");
        uint64_t at = index.size();
        Bytes blob; const Bytes zeros(256, 0);
        for (size_t i = 0; i < count; ++i) {
            build_step(steps[i], pe.p + rec[i]->off, rec[i]->size, blob);
            uint8_t d[32];
            sha256(blob.data(), blob.size(), d);
            if (std::memcmp(d, steps[i].sha256, 32) != 0)
                throw Fail(std::string("The model made from this DLL differs from the tested one (") + steps[i].name + ").");
            for (; at < offs[i]; at += std::min<uint64_t>(256, offs[i] - at))
                std::fwrite(zeros.data(), 1, size_t(std::min<uint64_t>(256, offs[i] - at)), f.get());
            if (std::fwrite(blob.data(), 1, blob.size(), f.get()) != blob.size()) throw Fail("Cannot write " + tmp + ".");
            at += blob.size();
            advance(blob.size());
        }
        if (std::fflush(f.get()) != 0 || fsync(fileno(f.get())) != 0) throw Fail("Cannot write " + tmp + ".");
        f.reset();
        std::filesystem::rename(tmp, dest);
    } catch (...) {
        f.reset();
        std::error_code ec;
        std::filesystem::remove(tmp, ec);
        throw;
    }
}

}  // namespace

bool check(const std::string& path, DllInfo& info, std::string& err) {
    try {
        Input in;
        load(path, in);
        return identify(in, info, err);
    } catch (const Fail& e) {
        err = e.what();
    } catch (const std::exception& e) {
        err = std::string("Cannot read the file: ") + e.what() + ".";
    }
    return false;
}

bool make(const std::string& path, const std::string& out_dir, const std::function<void(float)>& progress, std::string& err) {
    try {
        Input in;
        load(path, in);
        DllInfo info;
        if (!identify(in, info, err)) return false;
        const Pe pe(in.p, in.n);
        std::filesystem::create_directories(out_dir);
        using namespace vana_model_tables;
        struct Job { const char* resource; const Step* steps; size_t count; const char* file; };
        std::vector<Job> jobs = {{"WEIGHTS_HT", kOriginal, std::size(kOriginal), "dlssnr.bin"}};
        if (info.small) jobs.push_back({"WEIGHTS_CC_SMALL_FP8", kSmall, std::size(kSmall), "dlssnr-small.bin"});
        // Progress by bytes written; the sizes are the tested model's, close enough before the DLL is read.
        size_t total = 0, done = 0;
        for (const auto& j : jobs) {
            const auto recs = weights(pe, j.resource);
            for (size_t i = 0; i < j.count; ++i)
                if (const auto it = recs.find(j.steps[i].record); it != recs.end()) total += step_size(j.steps[i], it->second);
        }
        if (progress) progress(0.0f);
        for (const auto& j : jobs)
            pack(pe, j.resource, j.steps, j.count, std::filesystem::path(out_dir) / j.file, [&](size_t n) {
                done += n;
                if (progress && total) progress(float(done) / float(total));
            });
        return true;
    } catch (const Fail& e) {
        err = e.what();
        if (err.empty() || std::islower(static_cast<unsigned char>(err[0]))) err = "The DLL's weights could not be read: " + err + ".";
    } catch (const std::exception& e) {
        err = std::string("Cannot write the model: ") + e.what() + ".";
    }
    return false;
}

}  // namespace vana_model
