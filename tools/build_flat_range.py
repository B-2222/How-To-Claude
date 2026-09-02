"""Emit scenes/arenas/flat_range.tscn from a block list.

The arena is authored as data rather than clicked out in the editor so the
layout can be diffed, and so distances stay exact - a 60 m target has to be
60.0 m away for the Phase 2 distance tiers to mean anything.

Blocks are (name, position, size, euler_degrees). Everything is an axis-aligned
box unless it is a ramp. Run from the project root:

    python3 tools/build_flat_range.py
"""
import math

BLOCKS = []
TARGETS = []


def block(name, pos, size, rot=(0.0, 0.0, 0.0)):
    BLOCKS.append((name, pos, size, rot))


def target(pos, respawn=2.5):
    TARGETS.append((pos, respawn))


# --- Shell -----------------------------------------------------------------
block("Floor", (0, -0.5, 0), (100, 1, 100))
block("WallNorth", (0, 6, -50), (100, 12, 2))
block("WallSouth", (0, 6, 50), (100, 12, 2))
block("WallEast", (50, 6, 0), (2, 12, 100))
block("WallWest", (-50, 6, 0), (2, 12, 100))

# --- Slide ramps flanking spawn. Shallow enough to slide down and build speed.
block("RampWest", (-20, 1.0, 30), (10, 0.5, 14), (-12, 0, 0))
block("RampEast", (20, 1.0, 30), (10, 0.5, 14), (-12, 0, 0))

# --- Bunny hop gap course, west side. Gaps widen, so each platform demands
# more speed than the last. Clearing the final gap requires real strafe gain.
gap_z = 26.0
for i, gap in enumerate([4, 5, 6, 7, 8]):
    block("Hop%d" % i, (-26, 1.5, gap_z), (6, 0.5, 6))
    gap_z -= 6 + gap
block("Hop5", (-26, 1.5, gap_z), (6, 0.5, 6))

# --- Ascending platforms, east side. Air-strafe up, or drop off for airborne
# shots at height.
block("Plat1", (26, 2, 10), (8, 0.5, 8))
block("Plat2", (34, 5, 0), (8, 0.5, 8))
block("Plat3", (26, 8, -10), (8, 0.5, 8))
block("Plat4", (34, 11, -20), (8, 0.5, 8))
block("Tower", (40, 7, -34), (10, 14, 10))

# --- Mid-field pillars. Cover for blind shots, and flat vertical faces for the
# bounce weapon in Phase 3.
for name, x, z in [("PillarA", -10, 5), ("PillarB", 10, 5),
                   ("PillarC", -8, -14), ("PillarD", 8, -14),
                   ("PillarE", 0, -28)]:
    block(name, (x, 3, z), (2, 6, 2))

# --- Targets ---------------------------------------------------------------
# Centre lane at roughly 10/20/30/40/60/80 m from the spawn at z = 42.
for z, y in [(32, 1.6), (22, 2.2), (12, 1.4), (2, 2.6), (-18, 1.8), (-38, 3.2)]:
    target((0, y, z))
# Above the hop course, so a clean bhop run has something to shoot.
for z, y in [(16, 3.2), (-7, 3.6), (-20, 4.0)]:
    target((-26, y, z))
# Along the ascending platforms.
for x, y, z in [(26, 4.0, 10), (34, 7.0, 0), (26, 10.0, -10), (34, 13.0, -20)]:
    target((x, y, z))
# Long corner shots, ~90 m from spawn.
target((-40, 2.0, -46))
target((40, 2.0, -46))


def basis_columns(rx, ry, rz):
    """Godot's default Euler order is YXZ: Ry * Rx * Rz."""
    rx, ry, rz = map(math.radians, (rx, ry, rz))

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    mx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    my = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    mz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    m = mul(mul(my, mx), mz)
    # Transform3D takes basis COLUMNS in order: x axis, y axis, z axis.
    return [[m[0][c], m[1][c], m[2][c]] for c in range(3)]


def fmt(v):
    return ("%g" % round(v, 6))


def transform(pos, rot):
    """Serialise a Transform3D the way .tscn expects it.

    The literal is stored ROW BY ROW: Transform3D(a,b,c, d,e,f, g,h,i, ...)
    gives basis.x = (a, d, g). Writing the three axis vectors back to back
    instead silently stores the transpose, which for a rotation is its inverse,
    so ramps tilt the wrong way and lights point backwards.
    """
    cols = basis_columns(*rot)
    rows = [cols[axis][component] for component in range(3) for axis in range(3)]
    return "Transform3D(%s)" % ", ".join(fmt(v) for v in rows + list(pos))


def main():
    ext = [
        '[ext_resource type="Material" path="res://resources/greybox_material.tres" id="1_grid"]',
        '[ext_resource type="PackedScene" path="res://scenes/targets/target.tscn" id="2_target"]',
    ]
    subs, nodes = [], []

    for index, (name, pos, size, rot) in enumerate(BLOCKS):
        size_str = "Vector3(%s, %s, %s)" % tuple(fmt(v) for v in size)
        subs.append('[sub_resource type="BoxMesh" id="Mesh_%d"]\nsize = %s\n' % (index, size_str))
        subs.append('[sub_resource type="BoxShape3D" id="Shape_%d"]\nsize = %s\n' % (index, size_str))
        nodes.append(
            '[node name="%s" type="StaticBody3D" parent="Geometry"]\n'
            'transform = %s\n'
            'collision_layer = 1\n'
            'collision_mask = 0\n' % (name, transform(pos, rot)))
        nodes.append(
            '[node name="Mesh" type="MeshInstance3D" parent="Geometry/%s"]\n'
            'mesh = SubResource("Mesh_%d")\n'
            'material_override = ExtResource("1_grid")\n' % (name, index))
        nodes.append(
            '[node name="Collider" type="CollisionShape3D" parent="Geometry/%s"]\n'
            'shape = SubResource("Shape_%d")\n' % (name, index))

    for index, (pos, respawn) in enumerate(TARGETS):
        nodes.append(
            '[node name="Target%02d" parent="Targets" instance=ExtResource("2_target")]\n'
            'transform = %s\n'
            'respawn_time = %s\n' % (index, transform(pos, (0, 0, 0)), fmt(respawn)))

    load_steps = len(ext) + len(subs) + 1
    out = ['[gd_scene load_steps=%d format=3]\n' % load_steps]
    out.append("\n".join(ext) + "\n")
    out.append("\n".join(subs))
    out.append('[node name="FlatRange" type="Node3D"]\n')
    out.append('[node name="Geometry" type="Node3D" parent="."]\n')
    out.append('[node name="Targets" type="Node3D" parent="."]\n')
    out.append('[node name="Spawn" type="Marker3D" parent="."]\n'
               'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.1, 42)\n')
    out.append("\n".join(nodes))

    with open("scenes/arenas/flat_range.tscn", "w") as handle:
        handle.write("\n".join(out))
    print("flat_range.tscn: %d blocks, %d targets" % (len(BLOCKS), len(TARGETS)))


if __name__ == "__main__":
    main()
