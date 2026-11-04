#import "YTPDownloader.h"

@implementation YTPDownloadItem

- (NSDictionary *)toDictionary {
    return @{
        @"identifier": self.identifier ?: @"",
        @"title": self.title ?: @"",
        @"author": self.author ?: @"",
        @"filePath": self.filePath ?: @"",
        @"videoID": self.videoID ?: @"",
        @"isAudioOnly": @(self.isAudioOnly),
        @"fileSize": @(self.fileSize),
        @"dateAdded": @([self.dateAdded timeIntervalSince1970])
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (!dict) return nil;
    YTPDownloadItem *item = [[YTPDownloadItem alloc] init];
    item.identifier = dict[@"identifier"];
    item.title = dict[@"title"];
    item.author = dict[@"author"];
    item.filePath = dict[@"filePath"];
    item.videoID = dict[@"videoID"];
    item.isAudioOnly = [dict[@"isAudioOnly"] boolValue];
    item.fileSize = [dict[@"fileSize"] longLongValue];
    item.dateAdded = [NSDate dateWithTimeIntervalSince1970:[dict[@"dateAdded"] doubleValue]];
    return item;
}

@end

@interface YTPDownloader ()

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableDictionary<NSString *, void (^)(float)> *progressHandlers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, void (^)(BOOL, NSError *)> *completionHandlers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, YTPDownloadItem *> *pendingItems;
@property (nonatomic, strong) NSMutableArray<YTPDownloadItem *> *internalDownloadedItems;

@end

@implementation YTPDownloader

+ (instancetype)sharedDownloader {
    static YTPDownloader *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[YTPDownloader alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _progressHandlers = [NSMutableDictionary dictionary];
        _completionHandlers = [NSMutableDictionary dictionary];
        _pendingItems = [NSMutableDictionary dictionary];
        _internalDownloadedItems = [NSMutableArray array];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];

        [self createDownloadDirectory];
        [self loadPersistedItems];
    }
    return self;
}

- (NSArray<YTPDownloadItem *> *)downloadedItems {
    return [self.internalDownloadedItems copy];
}

- (NSString *)downloadDirectoryPath {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"YTPDownloads"];
}

- (void)createDownloadDirectory {
    NSString *dir = [self downloadDirectoryPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (NSString *)metadataPlistPath {
    return [[self downloadDirectoryPath] stringByAppendingPathComponent:@"YTPDownloads.plist"];
}

- (void)loadPersistedItems {
    NSString *plist = [self metadataPlistPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:plist]) {
        NSArray *rawArray = [NSArray arrayWithContentsOfFile:plist];
        for (NSDictionary *d in rawArray) {
            YTPDownloadItem *item = [YTPDownloadItem fromDictionary:d];
            if (item && [[NSFileManager defaultManager] fileExistsAtPath:item.filePath]) {
                [self.internalDownloadedItems addObject:item];
            }
        }
    }
}

- (void)persistItems {
    NSMutableArray *rawArray = [NSMutableArray array];
    for (YTPDownloadItem *item in self.internalDownloadedItems) {
        [rawArray addObject:[item toDictionary]];
    }
    [rawArray writeToFile:[self metadataPlistPath] atomically:YES];
}

- (void)startDownloadWithURL:(NSURL *)url
                       title:(NSString *)title
                      author:(NSString *)author
                     videoID:(NSString *)videoID
                     isAudio:(BOOL)isAudio
                    progress:(void (^)(float))progressBlock
                  completion:(void (^)(BOOL, NSError *))completionBlock {
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:url];
    NSString *taskKey = @(task.taskIdentifier).stringValue;

    YTPDownloadItem *item = [[YTPDownloadItem alloc] init];
    item.identifier = [[NSUUID UUID] UUIDString];
    item.title = title;
    item.author = author;
    item.videoID = videoID;
    item.isAudioOnly = isAudio;
    item.dateAdded = [NSDate date];

    if (progressBlock) self.progressHandlers[taskKey] = [progressBlock copy];
    if (completionBlock) self.completionHandlers[taskKey] = [completionBlock copy];
    self.pendingItems[taskKey] = item;

    [task resume];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    NSString *taskKey = @(downloadTask.taskIdentifier).stringValue;
    void (^progressBlock)(float) = self.progressHandlers[taskKey];
    if (progressBlock && totalBytesExpectedToWrite > 0) {
        float progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
        dispatch_async(dispatch_get_main_queue(), ^{
            progressBlock(progress);
        });
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    NSString *taskKey = @(downloadTask.taskIdentifier).stringValue;
    YTPDownloadItem *item = self.pendingItems[taskKey];
    void (^completionBlock)(BOOL, NSError *) = self.completionHandlers[taskKey];

    if (!item) return;

    NSString *extension = item.isAudioOnly ? @"m4a" : @"mp4";
    // Sanitize filename
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\?%*:\":|<>"];
    NSString *cleanTitle = [[item.title componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@"_"];
    NSString *fileName = [NSString stringWithFormat:@"%@_%@.%@", cleanTitle, [item.identifier substringToIndex:6], extension];
    NSString *destPath = [[self downloadDirectoryPath] stringByAppendingPathComponent:fileName];

    NSError *fileError = nil;
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:destPath] error:&fileError];

    if (!fileError) {
        item.filePath = destPath;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:destPath error:nil];
        item.fileSize = [attrs fileSize];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.internalDownloadedItems insertObject:item atIndex:0];
            [self persistItems];
            if (completionBlock) completionBlock(YES, nil);
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) completionBlock(NO, fileError);
        });
    }

    [self.progressHandlers removeObjectForKey:taskKey];
    [self.completionHandlers removeObjectForKey:taskKey];
    [self.pendingItems removeObjectForKey:taskKey];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        NSString *taskKey = @(task.taskIdentifier).stringValue;
        void (^completionBlock)(BOOL, NSError *) = self.completionHandlers[taskKey];
        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(NO, error);
            });
        }
        [self.progressHandlers removeObjectForKey:taskKey];
        [self.completionHandlers removeObjectForKey:taskKey];
        [self.pendingItems removeObjectForKey:taskKey];
    }
}

#pragma mark - Management

- (void)deleteItem:(YTPDownloadItem *)item {
    if (item.filePath && [[NSFileManager defaultManager] fileExistsAtPath:item.filePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:item.filePath error:nil];
    }
    [self.internalDownloadedItems removeObject:item];
    [self persistItems];
}

- (void)updateItem:(YTPDownloadItem *)item newTitle:(NSString *)newTitle {
    item.title = newTitle;
    [self persistItems];
}

- (void)saveItemToPhotos:(YTPDownloadItem *)item completion:(void (^)(BOOL, NSString *))completion {
    if (!item.filePath || ![[NSFileManager defaultManager] fileExistsAtPath:item.filePath]) {
        if (completion) completion(NO, @"File not found");
        return;
    }

    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, @"Photos permission denied");
            });
            return;
        }

        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:item.filePath]];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    if (completion) completion(YES, @"Saved to Photos successfully");
                } else {
                    if (completion) completion(NO, error.localizedDescription ?: @"Failed to save to Photos");
                }
            });
        }];
    }];
}

@end
