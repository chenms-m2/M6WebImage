//
//  M6WebImageHelper.swift
//  Pods
//
//  Created by chenms on 16/9/7.
//
//

import Foundation

func safe_async_main_queue(block: (()->())) {
    safe_async_queue(dispatch_get_main_queue(), block)
}

private func safe_async_queue(queue: dispatch_queue_t, _ block: (()->())) {
    if queue === dispatch_get_main_queue() && NSThread.isMainThread() {
        block()
    } else {
        dispatch_async(queue, { 
            block()
        })
    }
}