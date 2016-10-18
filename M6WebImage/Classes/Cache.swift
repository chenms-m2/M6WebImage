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
open class Cache {
    // var
    
    // memory
    fileprivate let memoryCache: NSCache<AnyObject, AnyObject>!
    
    // disk
    fileprivate let fileManager: FileManager!
    fileprivate var diskCachePath: String!
    fileprivate var ioQueue: DispatchQueue!
    fileprivate var callbackQueue: DispatchQueue!
    
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
        fileManager = FileManager()
        let diskPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true).first!
        diskCachePath = (diskPath as NSString).appendingPathComponent(cacheName)
        ioQueue = DispatchQueue(label: "Cache.ioQueue", attributes: [])
        callbackQueue = DispatchQueue(label: "Cache.callbackQueue", attributes: DispatchQueue.Attributes.concurrent)
        
        // notify
         NotificationCenter.default.addObserver(self, selector: #selector(clearMemoryCache), name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - retrieve
extension Cache {
    
    func retrieveImageForKey(_ key: String, completionBlock: ((UIImage?) -> ())? = nil) -> DispatchWorkItem? {
        guard let completionBlock = completionBlock else {
            return nil
        }
        
        if let image = retrieveImageFromMemoryForKey(key) {
            completionBlock(image)
            return nil
        } else {
            // TODO: 没有泄露？ 参考dispatch_block_cancel API
            var sSelf: Cache! = self
            
            let block = DispatchWorkItem {
                sSelf.retrieveImageFromDiskForKey(key, completionBlock: { image in
                    if let image = image {
                        sSelf.storeImageToMemory(image, key: key)
                        sSelf.callbackQueue.async(execute: {
                            completionBlock(image)
                        })
                    } else {
                        sSelf.callbackQueue.async(execute: {
                            completionBlock(nil)
                        })
                    }
                    sSelf = nil
                })
            }
            
            ioQueue.async(execute: block)
            
            return block
        }
    }
    
    // memory
    func retrieveImageFromMemoryForKey(_ key: String) -> UIImage? {
        return memoryCache.object(forKey: key as AnyObject) as? UIImage
    }
    
    // disk
    func retrieveImageFromDiskForKey(_ key: String, completionBlock: ((UIImage?) -> ())? = nil) {
        guard let completionBlock = completionBlock else {
            return
        }
        
        // TODO: MD5
        let path = filePathForKey(key)
        let image = UIImage(contentsOfFile: path)
        completionBlock(image)
    }

}

// MARK: - store & remove
extension Cache {
    // store
    func storeImageToMemory(_ image: UIImage, key: String) {
        memoryCache.setObject(image, forKey: key as AnyObject)
    }
    
    func storeImageToDisk(_ imageData: Data, key: String, completionBlock:(() -> ())? = nil) {
        ioQueue.async { 
            if !self.fileManager.fileExists(atPath: self.diskCachePath) {
                do {
                    try self.fileManager.createDirectory(atPath: self.diskCachePath, withIntermediateDirectories: true, attributes: nil)
                } catch _ {} // TODO: 是否处理
            }
            
            let path = self.filePathForKey(key)
            self.fileManager.createFile(atPath: path, contents: imageData, attributes: nil)
            self.callbackQueue.async(execute: {
                completionBlock?()
            })
        }
    }
    
    // remove
    func removeImageFromMemoryForKey(_ key: String) {
        memoryCache.removeObject(forKey: key as AnyObject)
    }
    
    func removeImageFromDistForKey(_ key: String) {
        ioQueue.async {
            do {
                let path = self.filePathForKey(key)
                try self.fileManager.removeItem(atPath: path)
            } catch _ {}
        }
    }
}

// MARK: - clear
extension Cache {
    public func clearCache(_ completionBlock: ((Bool)->())?) {
        clearMemoryCache()
        clearDiskCache(completionBlock)
    }
    
    @objc func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }
    
    func clearDiskCache(_ completionBlock: ((Bool)->())?) {
        ioQueue.async { 
            var success = true
            do {
                try self.fileManager.removeItem(atPath: self.diskCachePath)
            } catch _ {
                success = false
            }
            
            self.callbackQueue.async(execute: {
                completionBlock?(success)
            })
        }
    }
}


// MARK: - helper
extension Cache {
    func filePathForKey(_ key: String) -> String {
        return (diskCachePath as NSString).appendingPathComponent(key)
    }
    
    func keyForURL(_ url: URL) -> String {
        return url.absoluteString
    }
}
