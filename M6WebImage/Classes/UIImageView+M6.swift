//
//  UIImageView+M6WebImage.swift
//  Pods
//
//  Created by chenms on 16/9/7.
//
//

import UIKit

// MARK: - set image & cancel
extension UIImageView {
    
    // set image
    public func m6_setImageWithURL(_ url: URL,
                                   placeHolderImage: UIImage? = nil,
                                   progressBlock: ProgressBlock? = nil,
                                   completionBlock: CompletionBlock? = nil) {
        let task = Manager.sharedInstance().retrieveImageWithURL(url,
            progressBlock: progressBlock,
            completionBlock: { [weak self] image, error in
                safe_async_main_queue({
                    guard let sSelf = self else {
                        return
                    }
                    guard let image = image else {
                        completionBlock?(nil, error)
                        return
                    }
                    
                    sSelf.image = image
                    completionBlock?(image, error)
                })
            })
        
        m6_setImageTask(task)
    }
    
    // cancel
    public func m6_cancelImageTask() {
        if let task = m6_imageTask() {
            task.cancel()
        }
    }
    
}

private var imageTaskKey: Void?

// MARK: - store image task
extension UIImageView {
    fileprivate func m6_imageTask() -> RetrieveImageTask? {
        return (objc_getAssociatedObject(self, &imageTaskKey) as? RetrieveImageTask)
    }
    
    fileprivate func m6_setImageTask(_ task: RetrieveImageTask) {
        objc_setAssociatedObject(self, &imageTaskKey, task, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

