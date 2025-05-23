//
//  AlertItem.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-14.
//


import Foundation

/// Application alert items
struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}