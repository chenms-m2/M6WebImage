//
//  Downloader.swift
//  Pods
//
//  Created by chenms on 16/9/7.
//
//

import Foundation

typealias DownloadProgressBlock = ProgressBlock
typealias DownloadCompletionBlock = ((_ image: UIImage?, _ imageData:Data?, _ error: NSError?) -> ())
typealias CallbackPair = (progressBlock: DownloadProgressBlock?, completionBlock: DownloadCompletionBlock?)

public let M6WebImageErrorDomain = M6WebImagePrefix + "M6WebImageErrorDomain"

public enum M6WebImageError: Int {
    case invalidStatusCode = 40001
}

let timeout = 15.0

private let instance = Downloader()

class Downloader: NSObject {
    
    var session: Foundation.URLSession!
    var taskInfos: [String : TaskInfo]!
    var taskInfoQueue: DispatchQueue!
    var processQueue: DispatchQueue!
    var callbackQueue: DispatchQueue!
    
    // singleton
    static func sharedInstance() -> Downloader {
        return instance
    }
    
    // init
    override init() {
        super.init()
        
        session = Foundation.URLSession(configuration: URLSessionConfiguration.ephemeral, delegate: self, delegateQueue: OperationQueue.main)
        taskInfos = [String : TaskInfo]()
        taskInfoQueue = DispatchQueue(label: "Downloader.taskInfoQueue", attributes: DispatchQueue.Attributes.concurrent)
        processQueue = DispatchQueue(label: "Downloader.processQueue", attributes: DispatchQueue.Attributes.concurrent)
        callbackQueue = DispatchQueue(label: "Downloader.callbackQueue", attributes: DispatchQueue.Attributes.concurrent)
    }
    
    func downloadImageForURL(_ url: URL,
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
extension Downloader: URLSessionDataDelegate { // TODO: 必须NSObject，why
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let statusCode = (response as? HTTPURLResponse)?.statusCode, let url = dataTask.originalRequest?.url , (statusCode < 200 && statusCode >= 300) {
            let error = NSError(domain: M6WebImageErrorDomain, code: M6WebImageError.invalidStatusCode.rawValue, userInfo: ["statusCode": statusCode, "localizedStringForStatusCode": HTTPURLResponse.localizedString(forStatusCode: statusCode)])
            callbackCompletionForURL(url, image: nil, imageData: nil, error: error)
            
            removeTaskInfoForURL(url)
            
            completionHandler(.cancel)
            
            return
        }
        
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let url = dataTask.originalRequest?.url {
            let taskInfo = taskInfoForURL(url)
            taskInfo?.responseData.append(data)
            callbackProgressForURL(url, receivedSize: Int64(data.count), expectedSize: dataTask.response?.expectedContentLength ?? 0)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let url = task.originalRequest?.url {
            let taskInfo = taskInfoForURL(url)
            let data = taskInfo?.responseData
            
            // fail
            if error != nil || data == nil {
                callbackCompletionForURL(url, image: nil, imageData: nil, error: error as NSError?)
                removeTaskInfoForURL(url)
                
                return
            }
            
            // success
            processQueue.async(execute: {
                let image = UIImage(data: data! as Data)
                self.callbackCompletionForURL(url, image: image, imageData: data as Data?, error: nil)
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
        var task: URLSessionTask
        
        init(task: URLSessionTask) {
            self.task = task
        }
    }
    
    func taskInfoForURL(_ url: URL) -> TaskInfo? {
        var taskInfo: TaskInfo?
        taskInfoQueue.sync {
            taskInfo = self.taskInfos[self.keyForURL(url)]
        }
 
        return taskInfo
    }
    
    // store
    func updateTaskInfoForURL(_ url: URL, uuid: String, callbackPair: CallbackPair) -> TaskInfo {
        var taskInfo: TaskInfo?
        taskInfoQueue.sync(flags: .barrier, execute: {
            taskInfo = self.taskInfos[self.keyForURL(url)]
            if taskInfo == nil {
                taskInfo = self.buildTaskInfoForURL(url)
            }
            
            taskInfo?.downloadTaskCount += 1
            taskInfo?.callbackPairs[uuid] = callbackPair
        }) 
        
        return taskInfo!
    }
    
    func buildTaskInfoForURL(_ url: URL) -> TaskInfo {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        
        let task = self.session.dataTask(with: request)
        
        let taskInfo = TaskInfo(task: task)
        self.taskInfos[self.keyForURL(url)] = taskInfo
        
        return taskInfo
    }
    
    // remove
    func removeTaskInfoForURL(_ url: URL) {
        taskInfoQueue.sync(flags: .barrier, execute: {
            _ = self.taskInfos.removeValue(forKey: self.keyForURL(url))
        }) 
    }
    
    // try cancel
    func tryCancelTaskForURL(_ url: URL, uuid: String) {
        taskInfoQueue.sync(flags: .barrier, execute: {
            let key = self.keyForURL(url)
            if let taskInfo = self.taskInfos[key] {
                taskInfo.downloadTaskCount -= 1
                taskInfo.callbackPairs.removeValue(forKey: uuid)
                if taskInfo.downloadTaskCount == 0 {
                    self.taskInfos.removeValue(forKey: key)
                }
            }
        }) 
    }
    
    // callback
    func callbackProgressForURL(_ url: URL, receivedSize: Int64, expectedSize: Int64) {
        taskInfoQueue.sync {
            if let taskInfo = self.taskInfos[self.keyForURL(url)] {
                for callbackPair in taskInfo.callbackPairs.values {
                    self.callbackQueue.async(execute: {
                        callbackPair .progressBlock?(receivedSize, expectedSize)
                    })
                }
            }
        }
    }
    
    func callbackCompletionForURL(_ url: URL, image: UIImage?, imageData: Data?, error: NSError?) {
        taskInfoQueue.sync {
            if let taskInfo = self.taskInfos[self.keyForURL(url)] {
                for callbackPair in taskInfo.callbackPairs.values {
                    self.callbackQueue.async(execute: {
                        callbackPair.completionBlock?(image, imageData, error)
                    })
                }
            }
        }
    }
    
    // helper
    func keyForURL(_ url: URL) -> String {
        return url.absoluteString
    }
    
    func callbackPairFromProgressBlock(_ progressBlock: DownloadProgressBlock?, completionBlock: DownloadCompletionBlock?) -> CallbackPair {
        var callbackPair: CallbackPair
        callbackPair.progressBlock = progressBlock
        callbackPair.completionBlock = completionBlock
        
        return callbackPair
    }
    
}

// MARK: - DownloadTask
class DownloadTask {
    let uuid = UUID().uuidString
    var task: URLSessionTask?
    weak var downloader: Downloader?
    
    func cancel() {
        task?.cancel()
        if let url = task?.originalRequest?.url {
            downloader?.tryCancelTaskForURL(url, uuid: uuid)
        }
    }
}



