//
//  Created by ktiays on 2025/2/20.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation

precedencegroup ForwardApplication {
    associativity: left
    higherThan: AssignmentPrecedence
}

infix operator ||>: ForwardApplication

@discardableResult
func ||> <U>(_ lhs: @autoclosure () -> some Any, _ rhs: @autoclosure () -> U) -> U {
    _ = lhs()
    return rhs()
}
