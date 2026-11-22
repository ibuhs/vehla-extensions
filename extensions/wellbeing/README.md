# Wellbeing (Notch)

- **Water:** a procedurally drawn drinking glass (no image assets) with a living water surface.
  - *Glass:* tapered body, wall thickness, a thick glass punt that bends light differently, an elliptical
    rim with a double lip, Fresnel edge brightening and key-light streaks.
  - *Water:* 100 coupled spring-mass nodes (Hooke's law, damping 0.96, 8 propagation passes of 0.25) give
    traveling ripples and wall reflections. A capillary meniscus curls the edges up; the surface is a
    foreshortened ribbon with crest glints; depth shading, caustics and a base reflection sit below it.
  - *Adding a drink:* a stream's impulse hits the centre while the level eases up over 700 ms, and 20–30
    bubbles rise, wobble and pop at the surface.
  - *Pointer:* sweep the cursor across the glass (or drag) and the water sloshes.
  - *Over your goal:* the surface tension bulges at the brim, then water spills over the front edges, clings to
    the glass, pinches into teardrops and splashes into a puddle. The spill's strength and duration scale with
    how far over you went, then taper to a full brim.
  - *Power:* the render loop pauses when the water is still (kinetic energy under 0.001, nothing in flight), so an
    idle glass uses no CPU. Reduce Motion skips the animation.
  - Controls: 8 / 16 / 32 fl oz (or 150 / 250 / 500 ml), a custom amount, undo, a goal setting and a daily
    reset (Settings). Numbers count up with the level.
- **Mindful:** a guided breathing exercise (Box 4-4-4-4, Relax 4-7-8, Calm 4-6) for 1–10 minutes.
  - *Box:* a glass track a glowing comet traces once per cycle: up the left side on the in-breath, across the
    top on the hold, down the right on the out-breath, across the bottom on the hold. Sides you have breathed
    stay lit. Other patterns trace a circle.
  - *Orb:* a glass orb swells and shrinks inside with eased timing, with rings that ripple out as you inhale and
    gather in as you exhale, drifting motes, and the seconds left in each phase counting down in its centre.
  - *Feel:* a light trackpad tap marks each new phase, so you can breathe with your eyes closed. The closed
    Notch shows the phase and a countdown ring.
  - Drawn procedurally every frame while a session runs, and not at all when idle. Reduce Motion updates once a
    second instead. Everything is monochrome white to match the other tabs.
- **Reminders:** a gentle activity in the closed Notch with **Log 250 ml** and **Snooze**. They wait an
  interval after your last drink, stay quiet overnight (default 21:00–09:00) and stop for the day once
  you reach your goal.

Data is local (`wellbeing.json` in the extension's data folder). The extension loads at Notch start so
reminders work while the Notch is closed. It is separate from Vehla's own break reminders and doesn't
read them.
