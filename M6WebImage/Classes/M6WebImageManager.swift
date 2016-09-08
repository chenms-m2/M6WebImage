//
//  M6WebImageManager.swift
//  Pods
//
//  Created by chenms on 16/9/7.
//
//

import Foundation

private let instance = M6WebImageManager()

public class M6WebImageManager {
    // MARK: - var
    var cache: M6WebImageCache
    var downloader: M6WebImageDownloader
    

    // MARK: - singleton
    public static func sharedInstance() -> M6WebImageManager {
        return instance
    }
    
    
    // MARK: - init
    init() {
        cache = M6WebImageCache.sharedInstance()
        downloader = M6WebImageDownloader.sharedInstance()
    }
    
    
    // MARK: - retrieve
    public func retrieveImageWithURL(url: NSURL,
                                     progressBlock: ProgressBlock? = nil,
                                     completionBlock: CompletionBlock? = nil) -> () {
        cache.retrieveImageForKey(url.absoluteString, completionBlock: {[weak self] image in
            if let image = image {
                completionBlock?(image: image, error: nil)
            } else {
                if let sSelf = self {
                    sSelf.downloader.downloadImageForURL(url,
                        progressBlock: progressBlock,
                        completionBlock: completionBlock)
                }
            }
        })
    }

}