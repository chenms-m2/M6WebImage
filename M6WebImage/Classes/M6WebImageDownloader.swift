//
//  M6WebImageDownloader.swift
//  Pods
//
//  Created by chenms on 16/9/7.
//
//

import Foundation

private let instance = M6WebImageDownloader()

class M6WebImageDownloader {
    static func sharedInstance() -> M6WebImageDownloader {
        return instance
    }
    
    func downloadImageForURL(url: NSURL,
                             progressBlock: ProgressBlock? = nil,
                             completionBlock: CompletionBlock? = nil) {
        
    }
}