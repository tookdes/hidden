//
//  Date+Extension.swift
//  Hidden Bar
//
//  Created by Trung Phan on 22/03/2021.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import Foundation

extension Date {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE dd MMM"
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f
    }()
    static func dateString() -> String {
        return dateFormatter.string(from: Date())
    }
    static func timeString() -> String {
        return timeFormatter.string(from: Date())
    }
}
