//
//  Date+Timestamp.swift
//  Storage
//
//  Created by king on 2025/10/21.
//

import Foundation

extension Date {
    /// 当前时间 → 毫秒时间戳
    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1000.0).rounded())
    }

    /// 毫秒时间戳 → Date
    init(millisecondsSince1970: Int64) {
        self = Date(timeIntervalSince1970: TimeInterval(millisecondsSince1970) / 1000.0)
    }
}
