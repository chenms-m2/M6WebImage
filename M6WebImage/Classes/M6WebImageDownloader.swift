//
//  M6WebImageDownloader.swift
//  Pods
//
//  Created by chenms on 16/9/7.
//
//

import Foundation

typealias DownloadProgressBlock = ProgressBlock
typealias DownloadCompletionBlock = ((imageData:NSData?, error: NSError?) -> ())
typealias CallbackPair = (progressBlock: DownloadProgressBlock?, completionBlock: DownloadCompletionBlock?)

let timeout = 15.0

private let instance = M6WebImageDownloader()

class M6WebImageDownloader: NSObject {
    
    var session: NSURLSession!
    var taskInfos: [String : TaskInfo]!
    
    // singleton
    static func sharedInstance() -> M6WebImageDownloader {
        return instance
    }
    
    // init
    override init() {
        super.init()
        
        session = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration(), delegate: self, delegateQueue: NSOperationQueue.mainQueue())
        taskInfos = [String : TaskInfo]()
    }
    
    func downloadImageForURL(url: NSURL,
                             progressBlock: DownloadProgressBlock? = nil,
                             completionBlock: DownloadCompletionBlock? = nil) {
        
        let callbackPair = callbackPairFromProgressBlock(progressBlock, completionBlock: completionBlock)
        
        if let _ = taskInfos[keyForURL(url)] {
            updateTaskInfoWithCallbackPair(callbackPair, url: url)
        } else {
            updateTaskInfoWithCallbackPair(callbackPair, url: url)
            // task
            let request = NSMutableURLRequest(URL: url, cachePolicy: .ReloadIgnoringLocalCacheData, timeoutInterval: timeout)
            let task = session.dataTaskWithRequest(request)
            task.resume()
        }
    }
    
}

// MARK: - NSURLSessionDataDelegate
extension M6WebImageDownloader: NSURLSessionDataDelegate { // TODO: 必须NSObject，why
    func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
        
    }
    
    func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
        
    }
    
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
        
    }
}

// MARK: - TaskInfo
extension M6WebImageDownloader {
    // TaskInfo
    class TaskInfo {
        var callbackPairs = [CallbackPair]()
        var responseData = NSMutableData()
        var downloadTaskCount = 0
    }
    
    
    // store
    func updateTaskInfoWithCallbackPair(callbackPair: CallbackPair, url: NSURL) {
        if let taskInfo = taskInfos[keyForURL(url)] {
            taskInfo.downloadTaskCount += 1
            taskInfo.callbackPairs.append(callbackPair)
        } else {
            let taskInfo = TaskInfo()
            taskInfo.downloadTaskCount = 1
            taskInfo.callbackPairs.append(callbackPair)
            taskInfos[keyForURL(url)] = taskInfo
        }
    }
    
    // remove
    func removeCallbackPairForURL(url: NSURL) {
        taskInfos[keyForURL(url)] = nil
    }
    
    // callback
    func callbackProgressForURL(url: NSURL, receivedSize: Int64, expectedSize: Int64) {
        if let taskInfo = taskInfos[keyForURL(url)] {
            for callbackPair in taskInfo.callbackPairs {
                callbackPair.progressBlock?(receivedSize: receivedSize, expectedSize: expectedSize)
            }
        }
    }
    
    func callbackCompletionForURL(url: NSURL, imageData: NSData?, error: NSError?) {
        if let taskInfo = taskInfos[keyForURL(url)] {
            for callbackPair in taskInfo.callbackPairs {
                callbackPair.completionBlock?(imageData: imageData, error: error)
            }
        }
    }
    
    // helper
    func keyForURL(url: NSURL) -> String {
        return url.absoluteString
    }
    
    func callbackPairFromProgressBlock(progressBlock: DownloadProgressBlock?, completionBlock: DownloadCompletionBlock?) -> CallbackPair {
        var callbackPair: CallbackPair
        callbackPair.progressBlock = progressBlock
        callbackPair.completionBlock = completionBlock
        
        return callbackPair
    }
}

