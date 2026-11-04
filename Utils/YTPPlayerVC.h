#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YTPPlayerVC : UIViewController

@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic, copy, nullable) NSString *videoTitle;
@property (nonatomic, copy, nullable) NSString *videoID;

- (instancetype)initWithURL:(NSURL *)url title:(nullable NSString *)title videoID:(nullable NSString *)videoID;

@end

NS_ASSUME_NONNULL_END
