# WORK — RENDER

THREAD: UPSTACK — RENDER
THREAD_TYPE: WORK
SCOPE: `res://scenes/game/TowerView.tscn, res://scripts/render/*`
VERSION: v0.1
LAST_REVIEWED: 2026-01-26

Rendering is a pure consumer of simulation state. It observes and visualizes, but never decides.

## Hard boundary

Render consumes, never decides.

### Allowed

- Read-only view of sim state snapshots or deltas
- Mapping state to visuals (meshes, sprites, materials, visibility)
- Camera framing and view transforms
- Grid, floor, and module visualization
- Debug rendering

### Forbidden

- Module placement or removal
- Collision, adjacency, power, stability, or scoring logic
- Player intent or input logic
- Mutation of sim state

Sim state must be treated as immutable data.

## Data contract

Render receives a minimal DTO-style snapshot.

### TowerRenderState

- tower_size
- floors: Array[FloorRenderState]

### FloorRenderState

- floor_index
- bounds (optional)
- cells

### CellRenderState

- pos
- occupied
- module_id
- powered
- power_level (optional)
- variant (optional)
- rotation
- health (optional)
- flags (optional)

If render needs more data, it likely does not belong in render.

## Scene structure

Recommended hierarchy:

- TowerView
  - GridRoot
  - FloorsRoot
  - LightingRoot
  - CameraRig
  - Materials (optional)

TowerView owns visuals and caches only.

## Script layout

Suggested separation:

- render_state.gd
- tower_view.gd
- grid_renderer.gd
- floor_renderer.gd
- module_renderer.gd
- power_visuals.gd
- camera_controller.gd
- view_culling.gd

This prevents TowerView from becoming a junk drawer.

## Rendering approach

- Grid via MultiMesh or grid shader
- One node per floor for clarity
- MultiMesh per module type per floor
- Per-instance custom data for power, health, etc.

## Powered visuals

Unpowered:

- Reduced saturation
- Higher roughness
- No emissive

Powered:

- Subtle emissive
- Optional pulse driven by power_level

All styling decisions live in one place.

## Camera logic

Camera exposes methods only:

- focus_floor
- focus_bounds
- set_view_mode
- set_floor_slice

No input handling. No state decisions.

## Update strategy

- set_state for full refresh
- diff against cached state
- update materials or transforms only when needed

## Acceptance criteria

- Rendering driven entirely by sim state
- No gameplay logic in visuals
- Deterministic output for identical input
