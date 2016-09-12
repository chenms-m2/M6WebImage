//
//  M6WebImageManager.swift
//  Pods
//
//  Created by chenms on 16/9/7.
//
//

import Foundation

private let instance = Manager()

// MARK: - Manager
public class Manager {
    
    // var
    var cache: Cache
    var downloader: Downloader
    
    // singleton
    static func sharedInstance() -> Manager {
        return instance
    }
    
    // init
    init() {
        cache = Cache.sharedInstance()
        downloader = Downloader.sharedInstance()
    }
    
    // retrieve
    func retrieveImageWithURL(url: NSURL,
                                     progressBlock: ProgressBlock? = nil,
                                     completionBlock: CompletionBlock? = nil) -> RetrieveImageTask {
        let key = cache.keyForURL(url)
        
        let task = RetrieveImageTask()
        
        // retrieve from cache
        let disTask = cache.retrieveImageForKey(key, completionBlock: {[weak self] image in
            task.diskTask = nil
            
            if let image = image {
                completionBlock?(image: image, error: nil)
            } else {
                if let sSelf = self {
                    // download
                    let downloadTask = sSelf.downloader.downloadImageForURL(url,
                        progressBlock: progressBlock,
                        completionBlock: {image, imageData, error in
                            task.downloadTask = nil
                            
                            guard let image = image, let imageData = imageData else {
                                completionBlock?(image: nil, error: error)
                                return
                            }
                            
                            // cache
                            sSelf.cache.storeImageToMemory(image, key: key)
                            sSelf.cache.storeImageToDisk(imageData, key: key, completionBlock: {
                                completionBlock?(image: image, error: nil)
                            })
                    })
                    
                    task.downloadTask = downloadTask
                }
            }
        })
        
        task.diskTask = disTask
        
        return task
    }
}

// MARK: - RetrieveImageTask
class RetrieveImageTask {
    var diskTask: dispatch_block_t?
    var downloadTask: DownloadTask?
    
    // cancel
    func cancel() {
        if let diskTask = diskTask {
            dispatch_block_cancel(diskTask)
        }
        
        if let downloadTask = downloadTask {
            downloadTask.cancel()
        }
    }
    
}

