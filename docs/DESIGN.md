# Ultra Idle Cycling: design doc

Status: draft for the prototype, November 2026.

## Pitch

You're an ultra-distance cyclist on an endless road through cel-shaded landscapes. The game sits open in the corner of your screen while you do other things. Every few minutes you glance over and decide: shift gears, change cadence, eat, drink, stop at the next shop or ride on. Good decisions mean more kilometres. Kilometres buy better kit, and the rider gets fitter just by riding.

## Core loop

1. **Ride.** The rider holds your chosen gear and cadence. The road keeps changing under them: climbs, descents, heat at midday.
2. **Check in.** Something has drifted. You're grinding up a climb in too big a gear, the bottles are empty, or the glycogen bar is sliding toward a bonk. Fix it.
3. **Shop.** Shops come up every 25 to 45 km. Plan a stop to refill bottles and buy food. Later, buy upgrades.
4. **Get better.** Distance earns coins. Riding trains the body. Upgrades and training let you go further between check-ins, which is the real idle reward.

The tension: **riding harder is faster but burns carbs faster than the gut can replace them.** Pacing is the skill.

## Time

Game time runs 10x faster than real time (`time_scale`), so one real minute is ten game minutes and a 15-minute demo session is about 2.5 game hours, roughly 55 to 65 km.

The game is meant to be left open in a corner of the screen, but **the ride carries on while it's closed** too. When you come back, the game catches up on the time you were away (up to 12 real hours) using the same rules as live play. A rider left without food and water slows down, walks, and ends up sitting by the road, so long absences cost you progress rather than earning it.

## Rider model

All numbers live in `config/tuning.json`. The simulation is `sim/rider_sim.gd`.

### Speed and power

Speed comes from cadence and gear: `speed = cadence × (chainring / cog) × wheel circumference`. The power needed to hold that speed comes from real cycling physics: rolling resistance, gravity on the slope, and air drag.

- If the rider has the power, they hold the speed.
- If not, they're **grinding**: they push as hard as they can and the cadence drops. Grinding is slow, burns carbs fast and tires the muscles.
- If the road drops away faster than the gear, they **coast** for free.

The rider can deliver up to `ftp × capacity × effort_cap` watts. Capacity is the rider's current condition, from 1.0 when fresh down to 0.15 when wrecked.

### Gears and cadence

The bike starts with a 34/50 chainring and an 11 to 32 cassette.

- **Cadence efficiency** peaks at about 88 rpm. Spinning faster or slower wastes energy and costs more carbs.
- **Torque**: big gear plus low cadence means high force per pedal stroke. That builds **muscle fatigue**, which recovers slowly.
- A gear that's right on the flat is wrong on the climb. This is why check-ins matter, and why the auto-shift upgrade is valuable.

### Carbs (glycogen)

- Glycogen store: 450 g, starting at 430 g.
- Burn rate depends on power and on what share comes from carbs vs fat. Easy riding is mostly fat. Hard riding is mostly carbs. At about 55 % of FTP the rider burns roughly what the gut can absorb (about 50 to 60 g per hour). Ride harder and you're running a deficit.
- Food goes into the **gut** first and is absorbed at 60 g per hour, more as the gut trains. Eating more than the gut holds (90 g) gives a 10 % penalty, so you can't just eat everything at once.
- Below 15 % glycogen the rider **bonks** and capacity falls toward 20 %. With an empty tank, general fatigue also climbs steadily until the rider has to sit down.

| Food | Carbs | Price |
|---|---|---|
| Gel | 25 g | 6 |
| Bar | 40 g | 8 |
| Banana | 27 g | 4 |
| Rice cake | 35 g | 5 |

The rider starts with 4 pocket slots.

### Water

- Sweat rate rises with power and with temperature above 16 °C. Temperature follows the time of day (peak mid-afternoon) and the biome (mountains are cooler, coast is warmer).
- Two 0.75 L bottles to start. Each drink is a 150 ml sip.
- Up to 1.5 % body-weight water loss is free. Beyond that capacity drops 7 % per percent. At 6 % the rider **sits down by the road**.

### Fatigue

- **General fatigue** builds with intensity (steeply, `intensity^2.5`) and recovers when riding easy or resting. At 100 the rider sits down by the road.
- **Muscle fatigue** builds from high torque (grinding, wrong gears) and recovers when the legs spin easily.
- Both reduce capacity.

### Running out: crawl, walk, sit

The rider **never eats or drinks on their own**. Only the player (or a paid automation upgrade) feeds them. When neglected, things go downhill in stages:

1. **Crawling.** Bonked and dehydrated, the rider has a fraction of their power and slows right down.
2. **Walking.** When the cadence would drop below 40 rpm (a steep climb, a gear that's too big, or no strength left), the rider gets off and pushes the bike at about 4.5 km/h.
3. **Sitting by the road.** At 6 % dehydration or full exhaustion the rider stops completely and waits.

A sitting rider gets up only when the cause is fixed: water deficit under 4 %, some carbs in the tank or gut, and fatigue under 80. Fatigue recovers while sitting, but food and water have to come from the player. If the pockets and bottles are empty, the player can **flag down a car** for water and food. It costs 15 coins, or nothing if the player is broke, so a rider can never get permanently stuck.

## Progression

### Training: the rider gets better by riding

Each stat gains XP from the matching activity. Level is `floor(sqrt(xp / 0.5))`, so early levels come quickly and later ones slow down.

| Stat | Trained by | Effect per level |
|---|---|---|
| Endurance | Time spent above 50 % FTP | +2 % FTP |
| Stamina | Time on the bike | −4 % general fatigue build-up |
| Strength | Riding under high torque | −5 % muscle fatigue build-up |
| Gut | Carbs absorbed | +4 g per hour absorption |
| Cooling | Sweating in the heat | −3 % sweat rate |

### Shops and upgrades (step 2)

Shops sell food and refill water for free. Planned upgrades, roughly in unlock order:

- **Kit:** saddle bag (+pocket slots), third bottle cage, bigger bottles, aero bars (lower CdA), lighter wheels, better tyres (lower Crr), wider-range cassette.
- **Automation (the idle upgrades):** auto-drink, auto-eat, electronic auto-shift, "stop at shop when low". These let you check in less often without losing distance, which is what makes an idle game feel rewarding.
- **Consumables:** drink mix (carbs in the bottle), salt tabs, caffeine gel (short-term capacity boost).

### Landscapes

The road runs in 80 km segments, each in one biome, blended at the borders:

| Biome | Terrain | Notes |
|---|---|---|
| Fields | Flat | The first segment is always fields |
| Hills | Rolling, short steep climbs | More coins per km |
| Coast | Gentle, warm | Thirstier |
| Mountains | Long climbs, cool | Most coins per km |

The road is generated from a seed, so it's the same every time and the renderer can draw exactly what the simulation rides.

## The route

The game is **one long ride across a continent**, currently 4,000 km, and it ends at the finish line. Biomes change every 80 km along the way.

Later ideas, not in the prototype: **meta progression** (the rider keeps some strength between crossings) and **new continents** with their own landscapes.

## Demo and paid content (step 3)

- The free demo ends after about 15 minutes of play, around the second shop. That gives enough time to feel a bonk, a shop stop and a level-up.
- Paid content (more biomes, shop tiers, the automation upgrades) ships as a **separate Godot content pack (.pck)** that is only downloaded after purchase. The free build doesn't contain it, so there's nothing in it to unlock by hacking.
- For real protection the pack has to be served by a small server that checks the store receipt (Apple, Google, Steam) before handing out a signed, short-lived download link. The Vercel project could host this. In the prototype the purchase is a stub.

## What the pacing run shows

`docs/pacing_baseline.txt` holds the output of `tools/simulate.gd`. It simulates players with different check-in habits for 2 real hours, plus closing the game after 15 minutes.

| Player | km after 15 min | km after 2 h | What happens |
|---|---|---|---|
| Never checks in | 63 | 164 | Sits down from dehydration after about 1 hour, at km 164 |
| Every 5 min | 56 | 355 | Never sits down |
| Every 20 min | 63 | 295 | Walks 27 % of the time |
| Every 20 min with all automation | 65 | 342 | Runs out of food: automation doesn't stop at shops |

Closing the game after 15 minutes of play:

| Time away | Extra km | Result |
|---|---|---|
| 30 min | +111 | Still riding |
| 2 h | +149 | Sat down (dehydration) about 50 minutes after closing |
| 8 h | +149 | Same: the rider waits by the road |

What this tells us:

- **Checking in now pays off strongly.** An attentive player rides more than twice as far as a neglected one over 2 hours.
- **Offline progress is capped by supplies, not by a timer.** You get about an hour of riding, then the rider waits. That's a natural reason to come back. Bigger bottles and more pockets let the rider go further offline, which makes those upgrades feel valuable.
- **Walking replaces grinding** as the penalty for a wrong gear on a climb, so muscle fatigue barely builds now. Auto-shift still matters because it avoids walking.
- **Food supply is the limit after about 1 real hour.** With 4 pocket slots even careful players run low between shops. The saddle bag should be the first upgrade.
- The first 15 minutes still don't reward attention much. We'll fix that in step 2 with an early climb and a cheap first upgrade.

## Decisions

Answered by Tomek on 27 November 2026:

1. **No self-care.** The rider never eats or drinks unattended. They crawl, walk and finally sit by the road.
2. **No separate effort control.** Cadence and gears are the controls. Finer difficulty settings can come later.
3. **Progress continues while the game is closed,** with the same rules as live play.
4. **One continent-long ride with an end.** Meta progression and new continents later.

## Code layout

```
config/tuning.json    all balance numbers
sim/bike_physics.gd   power, speed, gears (pure functions)
sim/terrain.gd        seeded endless road, biomes, temperature, shops
sim/rider_sim.gd      the full game state and step(dt), save/load
tools/simulate.gd     headless pacing simulation
tests/run_tests.gd    unit tests
```
