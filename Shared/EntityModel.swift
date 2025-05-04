//
//  EntityModel.swift
//  XR Anatomy
//
//  Created by Joanna  Lin  on 2025-04-22.
//

import Foundation
import SwiftUI


enum EntityType: Equatable {
    case named(String)
    case none
    
}


class EntityModel: ObservableObject {
    @Published var currentEntity: EntityType = .none
}
