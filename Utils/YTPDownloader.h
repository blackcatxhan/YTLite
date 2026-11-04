#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTPDownloadItem : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *author;
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy, nullable) NSString *videoID;
@property (nonatomic, assign) BOOL isAudioOnly;
@property (nonatomic, assign) int64_t fileSize;
@property (nonatomic, strong) NSDate *dateAdded;

- (NSDictionary *)toDictionary;
+ (nullable instancetype)fromDictionary:(NSDictionary *)dict;

@end

@interface YTPDownloader : NSObject <NSURLSessionDownloadDelegate>

+ (instancetype)sharedDownloader;

@property (nonatomic, strong, readonly) NSMutableArray<YTPDownloadItem *> *downloadedItems;

- (void)startDownloadWithURL:(NSURL *)url
                       title:(NSString *)title
                      author:(nullable NSString *)author
                     videoID:(nullable NSString *)videoID
                     isAudio:(BOOL)isAudio
                    progress:(nullable void (^)(float progress))progressBlock
                  completion:(nullable void (^)(BOOL success, NSError * _Nullable error))completionBlock;

- (void)deleteItem:(YTPDownloadItem *)item;
- (void)saveItemToPhotos:(YTPDownloadItem *)item completion:(void (^)(BOOL success, NSString *message))completion;
- (void)updateItem:(YTPDownloadItem *)item newTitle:(NSString *)newTitle;

@end

NS_ASSUME_NONNULL_END
