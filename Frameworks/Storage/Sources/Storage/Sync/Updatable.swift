//
//  Updatable.swift
//  Storage
//
//  Created by king on 2025/10/28.
//

import Foundation

/// 为支持通过 KeyPath 进行统一修改和差异检测的实体提供统一接口。
///
/// `Updatable` 允许安全地通过 KeyPath 修改对象属性，并在属性值变化时执行额外逻辑（例如标记为已修改）。
/// - `update` 方法：仅当新值与旧值不相等时执行赋值并返回 `true`。
/// - `assign` 方法：无条件赋值，不比较旧值。
///
/// ⚠️ 注意：
/// - 仅当 `KeyPath` 是 `ReferenceWritableKeyPath`（可写引用）时才允许修改
/// - 对只读 KeyPath 调用 `update` / `assign` 时会触发断言失败（不会崩溃，但在 Debug 模式下提示）。
public protocol Updatable: AnyObject {
    /// 当值类型支持 `Equatable` 时，仅在值发生变化时更新。
    /// - Parameters:
    ///   - keyPath: 要更新的属性 KeyPath。
    ///   - newValue: 新值。
    /// - Returns: 若更新生效（值有变化）则返回 `true`。
    @discardableResult
    func update<Value: Equatable>(_ keyPath: KeyPath<Self, Value>, to newValue: Value) -> Bool

    /// 当值类型支持 `Equatable` 时，仅在值发生变化时更新。
    /// - Parameters:
    ///   - keyPath: 可写 KeyPath。
    ///   - newValue: 新值。
    /// - Returns: 若更新生效（值有变化）则返回 `true`。
    @discardableResult
    func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Self, Value>, to newValue: Value) -> Bool

    /// 无条件为属性赋新值（即使新旧值相同）。
    /// - Parameters:
    ///   - keyPath: 属性的 KeyPath。
    ///   - newValue: 要赋的新值。
    func assign<Value>(_ keyPath: KeyPath<Self, Value>, to newValue: Value)

    /// 无条件为属性赋新值（即使新旧值相同）。
    /// - Parameters:
    ///   - keyPath: 可写属性的 KeyPath。
    ///   - newValue: 要赋的新值。
    func assign<Value>(_ keyPath: ReferenceWritableKeyPath<Self, Value>, to newValue: Value)
}

public extension Updatable {
    /// 对只读 KeyPath 的 `update` 调用时自动进行安全检查。
    /// 若 KeyPath 不可写，会触发断言提示。
    @discardableResult
    func update<Value: Equatable>(_ keyPath: KeyPath<Self, Value>, to newValue: Value) -> Bool {
        guard let writable = keyPath as? ReferenceWritableKeyPath<Self, Value> else {
            assertionFailure("❌ Attempted to update a read-only keyPath: \(keyPath)")
            return false
        }
        return update(writable, to: newValue)
    }

    /// 对只读 KeyPath 的 `assign` 调用时自动进行安全检查。
    /// 若 KeyPath 不可写，会触发断言提示。
    func assign<Value>(_ keyPath: KeyPath<Self, Value>, to newValue: Value) {
        guard let writable = keyPath as? ReferenceWritableKeyPath<Self, Value> else {
            assertionFailure("❌ Attempted to assign to a read-only keyPath: \(keyPath)")
            return
        }
        assign(writable, to: newValue)
    }
}
