-- The world's look (the render tweak add-ons), as post passes in this order: a painted look (Kuwahara: each pixel
-- the mean of the calmest of the four squares around it); brightness and colour, cel shading (colour in bands,
-- outlines where the depth jumps); Sobel outlines (on the depth, and on the colour if asked). Wireframe through the
-- client's switch.

local PAINT = [[
fn px(p: vec2<i32>) -> vec3<f32> {
  return textureLoad(scene, clamp(p, vec2<i32>(0), vec2<i32>(post.size) - 1), 0).rgb;
}

@fragment fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let p = vec2<i32>(in.pos.xy);
  let r = i32(post.p[0].x);
  let n = f32((r + 1) * (r + 1));
  var best = vec3<f32>(0.0);
  var least = 1e9;
  for (var q = 0; q < 4; q = q + 1) {
    let s = vec2<i32>(select(-1, 1, (q & 1) == 1), select(-1, 1, (q & 2) == 2));
    var m = vec3<f32>(0.0);
    var m2 = vec3<f32>(0.0);
    for (var j = 0; j <= r; j = j + 1) {
      for (var i = 0; i <= r; i = i + 1) {
        let c = px(p + vec2<i32>(i, j) * s);
        m = m + c;
        m2 = m2 + c * c;
      }
    }
    m = m / n;
    let v = m2 / n - m * m;
    let total = v.r + v.g + v.b;
    if (total < least) {
      least = total;
      best = m;
    }
  }
  return vec4<f32>(best, textureLoad(scene, p, 0).a);
}
]]

local LOOK = [[
fn view_dist(d: f32) -> f32 {
  return 0.1 * 2000.0 / (2000.0 - d * 1999.9);
}

@fragment fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let c = textureSample(scene, samp, in.uv);
  let l = dot(c.rgb, vec3<f32>(0.299, 0.587, 0.114));
  var rgb = mix(vec3<f32>(l), c.rgb, post.p[0].y) * post.p[0].x;
  if (post.p[0].z > 0.5) {
    // Brightness in bands, the hue kept.
    let lb = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lq = (floor(lb * 4.0) + 0.5) / 4.0;
    rgb = rgb * (lq / max(lb, 0.02));
    // Outlines where the depth jumps against the pixels around.
    let p = vec2<i32>(in.pos.xy);
    let d0 = view_dist(textureLoad(depth, p, 0));
    var jump = 0.0;
    for (var i = 0; i < 4; i = i + 1) {
      let o = array<vec2<i32>, 4>(vec2<i32>(2, 0), vec2<i32>(-2, 0), vec2<i32>(0, 2), vec2<i32>(0, -2))[i];
      jump = max(jump, view_dist(textureLoad(depth, p + o, 0)) - d0);
    }
    if (jump / max(d0, 0.5) > 0.12 && d0 < 300.0) {
      rgb = rgb * 0.1;
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
  var lum: array<f32, 9>;
  var dist: array<f32, 9>;
  for (var k = 0; k < 9; k = k + 1) {
    let q = at(p + (vec2<i32>(k % 3, k / 3) - 1) * w);
    lum[k] = dot(textureLoad(scene, q, 0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    // The log, so a step counts by its ratio: as strong far away as near.
    dist[k] = log(view_dist(textureLoad(depth, q, 0)));
  }
  var e = sobel(dist) * 1.6;
  if (post.p[0].z > 0.5) {
    e = max(e, sobel(lum));
  }
  let d0 = view_dist(textureLoad(depth, p, 0));
  let line = smoothstep(0.6, 1.2, e * post.p[0].x) * (1.0 - smoothstep(200.0, 400.0, d0));
  let c = textureLoad(scene, p, 0);
  return vec4<f32>(c.rgb * (1.0 - line * 0.9), c.a);
}
]]

local function look_on()
  return settings.get("brightness") ~= 1 or settings.get("saturation") ~= 1 or settings.get("toon")
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
      return { { settings.get("brightness"), settings.get("saturation"), settings.get("toon") and 1 or 0, 0 } }
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
