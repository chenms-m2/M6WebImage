//
//  M6WebImageHelper.swift
//  Pods
//
//  Created by chenms on 16/9/7.
//
//

import Foundation

public typealias ProgressBlock = ((_ receivedSize: Int64, _ expectedSize: Int64) -> ())
public typealias CompletionBlock = ((_ image: UIImage?, _ error: NSError?) -> ())

public let M6WebImagePrefix = "cn.m2.chenms."

func safe_async_main_queue(_ block: @escaping (()->())) {
    safe_async_queue(DispatchQueue.main, block)
}

private func safe_async_queue(_ queue: DispatchQueue, _ block: @escaping (()->())) {
    if queue === DispatchQueue.main && Thread.isMainThread {
        block()
    } else {
        queue.async(execute: { 
            block()
        })
    }
}
