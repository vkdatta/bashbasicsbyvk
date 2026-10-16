# Canvas element / rendering path

Use only when a canvas or equivalent rendering surface already exists. Do not add one. If the project has a local contract for it (`canvas_xd.md` map branch, or an installed rendering skill), follow that.

Inspect, in this order of likelihood:
- Render-loop ownership, frame scheduling, cancellation of `requestAnimationFrame`, cleanup on unmount
- Event listener add/remove symmetry
- Coordinate transforms, `devicePixelRatio`, resize handling
- Hit testing and pointer/touch mapping (wrong transform gives wrong object mutated)
- Full vs selective (dirty-region) redraw; work done while hidden/offscreen
- Allocations in hot loops, object counts, stale references
- GPU/CPU boundaries where applicable

Measure with a profiler or frame timing; reference budgets 8.3ms (120Hz) and 16.7ms (60Hz).
