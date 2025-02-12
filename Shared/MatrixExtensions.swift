//
//  MatrixExtensions.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-12.
//


//
//  MatrixExtensions.swift
//  XR Anatomy
//
//  Provides simd_float4x4 convenience extensions for position, toArray, fromArray
//

import simd

extension simd_float4x4 {
    /// Extract the position (translation) from the matrix's fourth column.
    var position: SIMD3<Float> {
        let t = self.columns.3
        return SIMD3<Float>(t.x, t.y, t.z)
    }

    /// Convert this 4x4 matrix into a 16-element Float array.
    func toArray() -> [Float] {
        return [
            columns.0.x, columns.0.y, columns.0.z, columns.0.w,
            columns.1.x, columns.1.y, columns.1.z, columns.1.w,
            columns.2.x, columns.2.y, columns.2.z, columns.2.w,
            columns.3.x, columns.3.y, columns.3.z, columns.3.w
        ]
    }

    /// Create a simd_float4x4 from a 16-element Float array.
    static func fromArray(_ arr: [Float]) -> simd_float4x4 {
        guard arr.count == 16 else {
            return matrix_identity_float4x4
        }
        return simd_float4x4(
            SIMD4<Float>(arr[0],  arr[1],  arr[2],  arr[3]),
            SIMD4<Float>(arr[4],  arr[5],  arr[6],  arr[7]),
            SIMD4<Float>(arr[8],  arr[9],  arr[10], arr[11]),
            SIMD4<Float>(arr[12], arr[13], arr[14], arr[15])
        )
    }
}
