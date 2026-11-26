// The model files, made from the player's own nvngx_dlssnr.dll.
#pragma once
#include <functional>
#include <string>
namespace vana_model {
struct DllInfo { std::string version; bool small = false, original = false; };  // version "310.9.16" / "310.8.0"
// path: nvngx_dlssnr.dll or a .zip holding it. Fast: hashes the DLL and identifies it. false + err (one plain sentence for players, e.g. "This is not nvngx_dlssnr 310.9.16 or 310.8.0.") otherwise.
bool check(const std::string& path, DllInfo& info, std::string& err);
// Writes dlssnr.bin (and dlssnr-small.bin for 310.9.16) into out_dir: each written to a temp name, verified against the tested model (the per-entry SHA-256 lists), then renamed into place. progress(0..1) may be empty. Never loads or runs the DLL.
bool make(const std::string& path, const std::string& out_dir, const std::function<void(float)>& progress, std::string& err);
}
