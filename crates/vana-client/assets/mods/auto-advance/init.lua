-- An event message waiting for a key goes on by itself once its page has been open the set seconds (Instant: as soon
-- as it waits), as Enter would move it (not while a menu asks a question).
local INSTANT = -1

timer.every(0.1, function()
  local secs = settings.get("seconds") or 0
  if secs == 0 then return end
  if secs == INSTANT then secs = 0 end
  local e = game.event()
  local t = e and e.text
  if t and t.waiting and not e.menu and t.open >= secs then
    actions.advance()
  end
end)
