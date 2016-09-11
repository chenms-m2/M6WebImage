//
//  M6WebImageCache.swift
//  Pods
//
//  Created by chenms on 16/9/7.
//
//

import Foundation

private let cacheName = M6WebImagePrefix + "M6WebImageCache"

// singleton
private let instance = Cache()


// MARK: - base
class Cache {
    // var
    
    // memory
    private let memoryCache: NSCache!
    
    // disk
    private let fileManager: NSFileManager!
    private var diskCachePath: String!
    private var ioQueue: dispatch_queue_t!
    private var callbackQueue: dispatch_queue_t!
    
    // singleton
    static func sharedInstance() -> Cache {
        return instance
    }
    
    // init
    init() {
        // memory
        memoryCache = NSCache()
        memoryCache.name = cacheName
        
        // disk
        fileManager = NSFileManager()
        let diskPath = NSSearchPathForDirectoriesInDomains(.CachesDirectory, NSSearchPathDomainMask.UserDomainMask, true).first!
        diskCachePath = (diskPath as NSString).stringByAppendingPathComponent(cacheName)
        ioQueue = dispatch_queue_create(cacheName + "io", DISPATCH_QUEUE_SERIAL)
        callbackQueue = dispatch_queue_create(cacheName + "callback", DISPATCH_QUEUE_CONCURRENT)
    }
}

// MARK: - retrieve
extension Cache {
    
    func retrieveImageForKey(key: String, completionBlock: ((UIImage?) -> ())? = nil) -> dispatch_block_t? {
        guard let completionBlock = completionBlock else {
            return nil
        }
        
        if let image = retrieveImageFromMemoryForKey(key) {
            completionBlock(image)
            return nil
        } else {
            // TODO: 没有泄露？ 参考dispatch_block_cancel API
            var sSelf: Cache! = self
            
            let block = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, {
                sSelf.retrieveImageFromDiskForKey(key, completionBlock: { image in
                    if let image = image {
                        sSelf.storeImageToMemory(image, key: key)
                        dispatch_async(sSelf.callbackQueue, {
                            completionBlock(image)
                        })
                    } else {
                        dispatch_async(sSelf.callbackQueue, {
                            completionBlock(nil)
                        })
                    }
                    sSelf = nil
                })
            })
            
            dispatch_async(ioQueue, block)
            
            return block
        }
    }
    
    // memory
    func retrieveImageFromMemoryForKey(key: String) -> UIImage? {
        return memoryCache.objectForKey(key) as? UIImage
    }
    
    // disk
    func retrieveImageFromDiskForKey(key: String, completionBlock: ((UIImage?) -> ())? = nil) {
        guard let completionBlock = completionBlock else {
            return
        }
        
        // TODO: MD5
        let path = filePathForKey(key)
        let image = UIImage(contentsOfFile: path)
        completionBlock(image)
    }

}



// MARK: - store
extension Cache {
    func storeImageToMemory(image: UIImage, key: String) {
        memoryCache.setObject(image, forKey: key)
    }
    
    func storeImageToDisk(imageData: NSData, key: String, completionBlock:(() -> ())? = nil) {
        dispatch_async(ioQueue) { 
            if !self.fileManager.fileExistsAtPath(self.diskCachePath) {
                do {
                    try self.fileManager.createDirectoryAtPath(self.diskCachePath, withIntermediateDirectories: true, attributes: nil)
                } catch _ {} // TODO: 是否处理
            }
            
            let path = self.filePathForKey(key)
            self.fileManager.createFileAtPath(path, contents: imageData, attributes: nil)
            dispatch_async(self.callbackQueue, {
                completionBlock?()
            })
        }
    }
}


// MARK: - helper
extension Cache {
    func filePathForKey(key: String) -> String {
        return (diskCachePath as NSString).stringByAppendingPathComponent(key)
    }
    
    func keyForURL(url: NSURL) -> String {
        return url.absoluteString
    }
}
