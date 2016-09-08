//
//  UIImageView+M6WebImage.swift
//  Pods
//
//  Created by chenms on 16/9/7.
//
//

import UIKit


public typealias ProgressBlock = ((receivedSize: Int64, expectedSize: Int64) -> ())
public typealias CompletionBlock = ((image: UIImage?, error: NSError?) -> ())

extension UIImageView {
    
    public func m6_setImageWithURL(url: NSURL?,
                                   placeHolderImage: UIImage? = nil,
                                   progressBlock: ProgressBlock? = nil,
                                   completionBlock: CompletionBlock? = nil) {
    
        guard let url = url else {
            return
        }
        
        M6WebImageManager.sharedInstance().retrieveImageWithURL(url,
            progressBlock: progressBlock,
            completionBlock: { [weak self] image, error in
                safe_async_main_queue({
                    guard let sSelf = self else {
                        return
                    }
                    
                    guard let image = image else {
                        completionBlock?(image: nil, error: error)
                        return
                    }
                    
                    sSelf.image = image
                    completionBlock?(image: image, error: error)
                })
            })
    }
    

}