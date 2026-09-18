import SceneKit

/// Builds a solid by sweeping a profile around the y axis. The cross section is
/// a superellipse rather than a circle, so the same code makes a soft body or a
/// boxy one depending on how square you ask for it.
///
/// The profile comes from `BodyGeometry`, which is what the flat drawing uses,
/// so the modelled pet is the same creature and not a lookalike.
enum Revolve {
    /// - Parameters:
    ///   - height: how tall the finished shape is.
    ///   - radius: half width at the widest point.
    ///   - squareness: 2 is a circular section, 4 or more reads as a rounded
    ///     box. Above about 8 the edges are sharp enough to alias.
    ///   - profile: half width at a fraction from the top, 0 to 1, as a share
    ///     of `radius`.
    static func geometry(
        height: CGFloat,
        radius: CGFloat,
        depth: CGFloat = 1,
        squareness: CGFloat = 2,
        rings: Int = 44,
        segments: Int = 72,
        profile: (CGFloat) -> CGFloat
    ) -> SCNGeometry {
        var positions: [SCNVector3] = []
        var uvs: [CGPoint] = []

        for ring in 0...rings {
            let drop = CGFloat(ring) / CGFloat(rings)
            let y = height / 2 - drop * height
            let r = max(0.0001, profile(drop) * radius)

            for segment in 0...segments {
                let angle = CGFloat(segment) / CGFloat(segments) * 2 * .pi
                let unit = superellipse(at: angle, squareness: squareness)
                positions.append(SCNVector3(r * unit.x, y, r * depth * unit.y))
                uvs.append(CGPoint(x: CGFloat(segment) / CGFloat(segments), y: drop))
            }
        }

        var indices: [Int32] = []
        let stride = segments + 1
        for ring in 0..<rings {
            for segment in 0..<segments {
                let a = Int32(ring * stride + segment)
                let b = a + 1
                let c = Int32((ring + 1) * stride + segment)
                let d = c + 1
                // Counter clockwise seen from outside. Wound the other way the
                // faces point inward, get culled, and the shape renders as the
                // inside of its own far side.
                indices += [a, b, c, b, d, c]
            }
        }

        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: smoothNormals(positions, indices)),
                SCNGeometrySource(textureCoordinates: uvs),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }

    /// A point on the unit superellipse. `squareness` 2 gives a circle; higher
    /// pushes the curve out toward its bounding square.
    private static func superellipse(at angle: CGFloat, squareness: CGFloat) -> CGPoint {
        let exponent = 2 / squareness
        let cosine = cos(angle)
        let sine = sin(angle)
        return CGPoint(
            x: pow(abs(cosine), exponent) * (cosine < 0 ? -1 : 1),
            y: pow(abs(sine), exponent) * (sine < 0 ? -1 : 1)
        )
    }

    /// Averaged from the faces that meet at each vertex. Derived from the
    /// geometry rather than from the profile's slope, which only happened to be
    /// right while the section was a circle.
    private static func smoothNormals(
        _ positions: [SCNVector3], _ indices: [Int32]
    ) -> [SCNVector3] {
        var normals = [SCNVector3](repeating: SCNVector3Zero, count: positions.count)
        for triangle in Swift.stride(from: 0, to: indices.count, by: 3) {
            let ia = Int(indices[triangle])
            let ib = Int(indices[triangle + 1])
            let ic = Int(indices[triangle + 2])
            let a = positions[ia], b = positions[ib], c = positions[ic]
            let u = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
            let v = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
            let face = SCNVector3(u.y * v.z - u.z * v.y,
                                  u.z * v.x - u.x * v.z,
                                  u.x * v.y - u.y * v.x)
            for index in [ia, ib, ic] {
                normals[index] = SCNVector3(normals[index].x + face.x,
                                            normals[index].y + face.y,
                                            normals[index].z + face.z)
            }
        }
        return normals.map { normal in
            let length = (normal.x * normal.x + normal.y * normal.y
                          + normal.z * normal.z).squareRoot()
            guard length > 0.00001 else { return SCNVector3(0, 1, 0) }
            return SCNVector3(normal.x / length, normal.y / length, normal.z / length)
        }
    }
}
