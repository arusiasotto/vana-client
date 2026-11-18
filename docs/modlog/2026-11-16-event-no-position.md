<!-- dll-build: 30261006_0 -->
## No c2s 0x015 under the control lock: the airship berth doors (2026-11-16)

- Report: on retail, Port Jeuno's departures door for Windurst (`_6ue`, event 39) played the walk through the door and
  then left us where the event started. LSB lets us through.
- Event 39 (actor 0x010f605f): choice, `cm54` walk, `fdo0`, op 0x47 sub 0 to (3.064, 8.001, -59.25), the 0x05C round
  trip, `fdi0`. Our 0x05C is byte for byte what FUN_100b62b0 / FUN_100a05e0 build (x val@2, y val@6, z val@4,
  dir val@8). The retail server's answer (capture, two tries) is s2c 0x065 mode 1 plus 0x05B mode 0 at our stored
  place, to 0.001, with our facing: the pre-event spot. FUN_1009d500 case 1 puts that into our event body and the end
  keeps it (FUN_10089a60), so we stood back at the door. LSB answers with the 0x05C's own coordinates, so it worked
  there.
- Why the server had the old place: we sent c2s 0x015 every datagram through the event, the one carrying the 0x05C
  too, all at the pre-event place (our place waits while bound). Retail sends none: FUN_100983f0 builds the 0x015
  only while the control lock DAT_10482f18 is clear (0x10098530), and the talk request that started event 39
  (FUN_1007bf30, 0x1007c17b) set it. So the 0x05C is the only position the server has from us during the event.
- Who sets the lock (all 25 references in 30261006_0): the talk request; the zone-in set-up when the 0x00A carries an
  event (FUN_10094190 0x1009533e, FUN_10096640 0x1009679a, both under EventNum != 0); op 0x20 (0x100b34d0); the
  zone requests (0x1008af02 / 0x1008b15d); menus (0x101d55f8 / 0x101d5627). FUN_100aed00, the set-up every event
  runs, sets only DAT_10488100, and the 0x032 / 0x034 path only reads the lock (0x100ad59d). Ours set it at every
  event start: an event the server starts on its own (a trade, an item, a region) has none in retail.
- Ours: event::begin sets no lock; event::queue sets it for a zone-in event (after the zone-in cleared it), and the net
  thread's 0x00A handler marks SelfState::locked when EventNum != 0 so nothing goes out before the first frame.
  SelfState::locked mirrors World::control_lock each frame, and `sends_position` (test `position_gate`) queues no
  0x015 while it or the rider gate holds. The first datagram after the lock goes carries the place the event left us
  at.
