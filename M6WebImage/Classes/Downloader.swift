//
//  Downloader.swift
//  Pods
//
//  Created by chenms on 16/9/7.
//
//

import Foundation

typealias DownloadProgressBlock = ProgressBlock
typealias DownloadCompletionBlock = ((image: UIImage?, imageData:NSData?, error: NSError?) -> ())
typealias CallbackPair = (progressBlock: DownloadProgressBlock?, completionBlock: DownloadCompletionBlock?)

public let M6WebImageErrorDomain = M6WebImagePrefix + "M6WebImageErrorDomain"

public enum M6WebImageError: Int {
    case InvalidStatusCode = 40001
}

let timeout = 15.0

private let instance = Downloader()

class Downloader: NSObject {
    
    var session: NSURLSession!
    var taskInfos: [String : TaskInfo]!
    var taskInfoQueue: dispatch_queue_t!
    var processQueue: dispatch_queue_t!
    var callbackQueue: dispatch_queue_t!
    
    // singleton
    static func sharedInstance() -> Downloader {
        return instance
    }
    
    // init
    override init() {
        super.init()
        
        session = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration(), delegate: self, delegateQueue: NSOperationQueue.mainQueue())
        taskInfos = [String : TaskInfo]()
        taskInfoQueue = dispatch_queue_create("Downloader.taskInfoQueue", DISPATCH_QUEUE_CONCURRENT)
        processQueue = dispatch_queue_create("Downloader.processQueue", DISPATCH_QUEUE_CONCURRENT)
        callbackQueue = dispatch_queue_create("Downloader.callbackQueue", DISPATCH_QUEUE_CONCURRENT)
    }
    
    func downloadImageForURL(url: NSURL,
                             progressBlock: DownloadProgressBlock? = nil,
                             completionBlock: DownloadCompletionBlock? = nil) -> DownloadTask {
        
        let downloadTask = DownloadTask()
        let callbackPair = callbackPairFromProgressBlock(progressBlock, completionBlock: completionBlock)
        let taskInfo = updateTaskInfoForURL(url, uuid: downloadTask.uuid, callbackPair: callbackPair)
        
        downloadTask.task = taskInfo.task
        downloadTask.downloader = self
        
        return downloadTask
    }

}

// MARK: - NSURLSessionDataDelegate
extension Downloader: NSURLSessionDataDelegate { // TODO: 必须NSObject，why
    func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
        if let statusCode = (response as? NSHTTPURLResponse)?.statusCode, let url = dataTask.originalRequest?.URL where (statusCode < 200 && statusCode >= 300) {
            let error = NSError(domain: M6WebImageErrorDomain, code: M6WebImageError.InvalidStatusCode.rawValue, userInfo: ["statusCode": statusCode, "localizedStringForStatusCode": NSHTTPURLResponse.localizedStringForStatusCode(statusCode)])
            callbackCompletionForURL(url, image: nil, imageData: nil, error: error)
            
            removeTaskInfoForURL(url)
            
            completionHandler(.Cancel)
            
            return
        }
        
        completionHandler(.Allow)
    }
    
    func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
        if let url = dataTask.originalRequest?.URL {
            let taskInfo = taskInfoForURL(url)
            taskInfo?.responseData.appendData(data)
            callbackProgressForURL(url, receivedSize: Int64(data.length), expectedSize: dataTask.response?.expectedContentLength ?? 0)
        }
    }
    
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
        if let url = task.originalRequest?.URL {
            let taskInfo = taskInfoForURL(url)
            let data = taskInfo?.responseData
            
            // fail
            if error != nil || data == nil {
                callbackCompletionForURL(url, image: nil, imageData: nil, error: error)
                removeTaskInfoForURL(url)
                
                return
            }
            
            // success
            dispatch_async(processQueue, {
                let image = UIImage(data: data!)
                self.callbackCompletionForURL(url, image: image, imageData: data, error: nil)
                self.removeTaskInfoForURL(url)
            })
        }
    }
}

// MARK: - TaskInfo
extension Downloader {
    // TaskInfo
    class TaskInfo {
        var callbackPairs = [String : CallbackPair]()
        var responseData = NSMutableData()
        var downloadTaskCount = 0
        var task: NSURLSessionTask
        
        init(task: NSURLSessionTask) {
            self.task = task
        }
    }
    
    func taskInfoForURL(url: NSURL) -> TaskInfo? {
        var taskInfo: TaskInfo?
        dispatch_sync(taskInfoQueue) {
            taskInfo = self.taskInfos[self.keyForURL(url)]
        }
 
        return taskInfo
    }
    
    // store
    func updateTaskInfoForURL(url: NSURL, uuid: String, callbackPair: CallbackPair) -> TaskInfo {
        var taskInfo: TaskInfo?
        dispatch_barrier_sync(taskInfoQueue) {
            taskInfo = self.taskInfos[self.keyForURL(url)]
            if taskInfo == nil {
                self.buildTaskInfoForURL(url)
            }
            
            taskInfo?.downloadTaskCount += 1
            taskInfo?.callbackPairs[uuid] = callbackPair
        }
        
        return taskInfo!
    }
    
    func buildTaskInfoForURL(url: NSURL) -> TaskInfo {
        let request = NSMutableURLRequest(URL: url, cachePolicy: .ReloadIgnoringLocalCacheData, timeoutInterval: timeout)
        let task = self.session.dataTaskWithRequest(request)
        
        let taskInfo = TaskInfo(task: task)
        self.taskInfos[self.keyForURL(url)] = taskInfo
        
        return taskInfo
    }
    
    // remove
    func removeTaskInfoForURL(url: NSURL) {
        dispatch_barrier_sync(taskInfoQueue) {
            self.taskInfos.removeValueForKey(self.keyForURL(url))
        }
    }
    
    // try cancel
    func tryCancelTaskForURL(url: NSURL, uuid: String) {
        dispatch_barrier_sync(taskInfoQueue) {
            let key = self.keyForURL(url)
            if let taskInfo = self.taskInfos[key] {
                taskInfo.downloadTaskCount -= 1
                taskInfo.callbackPairs.removeValueForKey(uuid)
                if taskInfo.downloadTaskCount == 0 {
                    self.taskInfos.removeValueForKey(key)
                }
            }
        }
    }
    
    // callback
    func callbackProgressForURL(url: NSURL, receivedSize: Int64, expectedSize: Int64) {
        dispatch_sync(taskInfoQueue) {
            if let taskInfo = self.taskInfos[self.keyForURL(url)] {
                for callbackPair in taskInfo.callbackPairs.values {
                    dispatch_async(self.callbackQueue, {
                        callbackPair .progressBlock?(receivedSize: receivedSize, expectedSize: expectedSize)
                    })
                }
            }
        }
    }
    
    func callbackCompletionForURL(url: NSURL, image: UIImage?, imageData: NSData?, error: NSError?) {
        dispatch_sync(taskInfoQueue) {
            if let taskInfo = self.taskInfos[self.keyForURL(url)] {
                for callbackPair in taskInfo.callbackPairs.values {
                    dispatch_async(self.callbackQueue, {
                        callbackPair.completionBlock?(image: image, imageData: imageData, error: error)
                    })
                }
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

// MARK: - DownloadTask
class DownloadTask {
    let uuid = NSUUID().UUIDString
    var task: NSURLSessionTask?
    weak var downloader: Downloader?
    
    func cancel() {
        task?.cancel()
        if let url = task?.originalRequest?.URL {
            downloader?.tryCancelTaskForURL(url, uuid: uuid)
        }
    }
}



