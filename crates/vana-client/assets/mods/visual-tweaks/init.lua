-- The world's look (the render tweak add-ons), as post passes in this order: a painted look (8-sector depth-guarded
-- Kuwahara); brightness, colour, anime grade, cel shading; Sobel outlines (on the depth, and on the colour if asked).
-- Wireframe through the client's switch.

local PAINT = [[
fn view_dist(d: f32) -> f32 {
  return 0.1 * 2000.0 / (2000.0 - d * 1999.9);
}

fn at(p: vec2<i32>) -> vec2<i32> {
  return clamp(p, vec2<i32>(0), vec2<i32>(post.size) - 1);
}

// The eighth of the circle (dx, dy) lies in, counted from +x as atan2 would, without the trig.
fn sector(dx: i32, dy: i32) -> i32 {
  var x = dx;
  var y = dy;
  var s = 0;
  if (y < 0 || (y == 0 && x < 0)) {
    x = -x;
    y = -y;
    s = 4;
  }
  if (x > 0 && y < x) {
    return s;
  }
  if (x > 0) {
    return s + 1;
  }
  if (y > -x) {
    return s + 2;
  }
  return s + 3;
}

@fragment fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let p = vec2<i32>(in.pos.xy);
  let r = i32(post.p[0].x);
  let d0 = view_dist(textureLoad(depth, p, 0));
  let c0 = textureLoad(scene, p, 0);
  // The centre counts in every sector.
  var m: array<vec3<f32>, 8>;
  var m2: array<vec3<f32>, 8>;
  var count: array<f32, 8>;
  for (var s = 0; s < 8; s = s + 1) {
    m[s] = c0.rgb;
    m2[s] = c0.rgb * c0.rgb;
    count[s] = 1.0;
  }
  for (var dy = -r; dy <= r; dy = dy + 1) {
    for (var dx = -r; dx <= r; dx = dx + 1) {
      if ((dx == 0 && dy == 0) || dx * dx + dy * dy > r * r) {
        continue;
      }
      let q = at(p + vec2<i32>(dx, dy));
      let dq = view_dist(textureLoad(depth, q, 0));
      if (abs(dq - d0) / max(d0, 0.5) >= 0.15) {
        continue;
      }
      let sec = sector(dx, dy);
      let c = textureLoad(scene, q, 0).rgb;
      m[sec] = m[sec] + c;
      m2[sec] = m2[sec] + c * c;
      count[sec] = count[sec] + 1.0;
    }
  }
  var best = c0.rgb;
  var least = 1e9;
  let w = vec3<f32>(0.299, 0.587, 0.114);
  for (var s = 0; s < 8; s = s + 1) {
    // A sector with only the centre says nothing about the strokes around it.
    if (count[s] > 1.0) {
      let mean = m[s] / count[s];
      let v = max(vec3<f32>(0.0), m2[s] / count[s] - mean * mean);
      let total = dot(v, w);
      if (total < least) {
        least = total;
        best = mean;
      }
    }
  }
  return vec4<f32>(best, c0.a);
}
]]

local LOOK = [[
fn view_dist(d: f32) -> f32 {
  return 0.1 * 2000.0 / (2000.0 - d * 1999.9);
}

const BANDS = 5.0;
const EDGE_LO = 0.04;
const EDGE_HI = 0.12;

fn lum_at(p: vec2<i32>) -> f32 {
  let c = textureLoad(scene, clamp(p, vec2<i32>(0), vec2<i32>(post.size) - 1), 0).rgb;
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn inv_at(p: vec2<i32>) -> f32 {
  return 1.0 / view_dist(textureLoad(depth, clamp(p, vec2<i32>(0), vec2<i32>(post.size) - 1), 0));
}

@fragment fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let c = textureSample(scene, samp, in.uv);
  let l = dot(c.rgb, vec3<f32>(0.299, 0.587, 0.114));
  var rgb = mix(vec3<f32>(l), c.rgb, post.p[0].y) * post.p[0].x;
  let grade = post.p[0].w;
  if (grade > 0.001) {
    let lum_g = clamp(dot(rgb, vec3<f32>(0.299, 0.587, 0.114)), 0.0, 1.0);
    let shadow_w = 1.0 - smoothstep(0.05, 0.55, lum_g);
    let highlight_w = smoothstep(0.45, 0.95, lum_g);
    let shadow_tint = vec3<f32>(0.84, 0.88, 1.12);
    let highlight_tint = vec3<f32>(1.08, 1.02, 0.90);
    let tint = mix(vec3<f32>(1.0), shadow_tint, shadow_w * grade)
             * mix(vec3<f32>(1.0), highlight_tint, highlight_w * grade);
    rgb = rgb * tint;
  }
  if (post.p[0].z > 0.5) {
    let p = vec2<i32>(in.pos.xy);
    // Brightness in soft bands. A band is picked from the brightness around (5 x 5, 3 px apart), so the bands follow
    // the light, not the grain of a texture; each pixel keeps its detail against that, half flattened. The darkest
    // band keeps its own brightness, so night stays night.
    var ls = 0.0;
    for (var k = 0; k < 25; k = k + 1) {
      ls = ls + lum_at(p + (vec2<i32>(k % 5, k / 5) - 2) * 3);
    }
    let around = max(ls / 25.0 * post.p[0].x, 0.0);
    let x = min(around, 1.0) * BANDS;
    let band = floor(x);
    let up = smoothstep(0.85, 1.0, x - band);
    let level = select((band + 0.5 + up) / BANDS, mix(around, 1.5 / BANDS, up), band < 1.0);
    let lb = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
    rgb = rgb * mix(level / max(around, 0.01), min(level, 1.0) / max(lb, 0.01), 0.5);
    // Outlines where 1 / distance bends: it changes evenly across any flat surface, however steep, so only an edge
    // in front of something farther draws one (on its nearer side, a line wide), unless the Outlines pass draws them.
    if (post.p[1].x < 0.5) {
      let i0 = inv_at(p);
      let ix = inv_at(p + vec2<i32>(1, 0)) + inv_at(p - vec2<i32>(1, 0));
      let iy = inv_at(p + vec2<i32>(0, 1)) + inv_at(p - vec2<i32>(0, 1));
      let bend = max(abs(ix - 2.0 * i0), abs(iy - 2.0 * i0)) / i0;
      let nearer = f32(i0 * 4.0 > ix + iy);
      let line = smoothstep(EDGE_LO, EDGE_HI, bend) * nearer * (1.0 - smoothstep(150.0, 300.0, 1.0 / i0));
      rgb = rgb * (1.0 - 0.8 * line);
    }
  }
  return vec4<f32>(rgb, c.a);
}
]]

local SOBEL = [[
fn view_dist(d: f32) -> f32 {
  return 0.1 * 2000.0 / (2000.0 - d * 1999.9);
}

fn at(p: vec2<i32>) -> vec2<i32> {
  return clamp(p, vec2<i32>(0), vec2<i32>(post.size) - 1);
}

// The gradient's size over a 3x3 block laid out row by row.
fn sobel(a: array<f32, 9>) -> f32 {
  let gx = (a[2] + 2.0 * a[5] + a[8]) - (a[0] + 2.0 * a[3] + a[6]);
  let gy = (a[6] + 2.0 * a[7] + a[8]) - (a[0] + 2.0 * a[1] + a[2]);
  return sqrt(gx * gx + gy * gy);
}

@fragment fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let p = vec2<i32>(in.pos.xy);
  let w = i32(post.p[0].y);
  let colour_edges = post.p[0].z > 0.5;
  var lum: array<f32, 9>;
  var dist: array<f32, 9>;
  for (var k = 0; k < 9; k = k + 1) {
    let q = at(p + (vec2<i32>(k % 3, k / 3) - 1) * w);
    dist[k] = log(view_dist(textureLoad(depth, q, 0)));
    if (colour_edges) {
      lum[k] = dot(textureLoad(scene, q, 0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    }
  }
  var e = sobel(dist) * 1.6;
  if (colour_edges) {
    let glow_fade = 1.0 - smoothstep(0.65, 0.95, lum[4]);
    e = max(e, sobel(lum) * glow_fade);
  }
  let d0 = view_dist(textureLoad(depth, p, 0));
  let line = smoothstep(0.6, 1.2, e * post.p[0].x) * (1.0 - smoothstep(200.0, 400.0, d0));
  let c = textureLoad(scene, p, 0);
  return vec4<f32>(c.rgb * (1.0 - line * 0.9), c.a);
}
]]

local function look_on()
  return settings.get("brightness") ~= 1
    or settings.get("saturation") ~= 1
    or settings.get("toon")
    or (settings.get("anime_grade") or 0) > 0
end

-- Drawn in this order.
local PASSES = {
  {
    id = "paint",
    src = PAINT,
    on = function() return settings.get("paint") end,
    params = function() return { { settings.get("paint_radius"), 0, 0, 0 } } end,
  },
  {
    id = "look",
    src = LOOK,
    on = look_on,
    params = function()
      return {
        {
          settings.get("brightness"),
          settings.get("saturation"),
          settings.get("toon") and 1 or 0,
          settings.get("anime_grade") or 0,
        },
        { settings.get("sobel") and 1 or 0, 0, 0, 0 },
      }
    end,
  },
  {
    id = "sobel",
    src = SOBEL,
    on = function() return settings.get("sobel") end,
    params = function()
      return { { settings.get("sobel_sensitivity"), settings.get("sobel_width"),
        settings.get("sobel_colour") and 1 or 0, 0 } }
    end,
  },
}

local loaded = {}

local function apply()
  local on = settings.get("on")
  local want = {}
  for _, p in ipairs(PASSES) do
    if on and p.on() then
      want[#want + 1] = p
    end
  end
  -- A pass added later is drawn last, so a change in which are on loads them all again in order.
  local same = #want == #loaded
  for i, p in ipairs(want) do
    same = same and loaded[i] == p.id
  end
  if not same then
    for _, id in ipairs(loaded) do
      render.shader(id, nil)
    end
    loaded = {}
    for _, p in ipairs(want) do
      render.shader(p.id, p.src)
      loaded[#loaded + 1] = p.id
    end
  end
  for _, p in ipairs(want) do
    render.shader_params(p.id, p.params())
  end
  client.set_option("wireframe", on and settings.get("wireframe") or false)
end

apply()
events.on("settings_changed", apply)
