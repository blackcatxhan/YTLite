#import "YTPPlayerVC.h"

@interface YTPPlayerVC ()

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UISlider *timeSlider;
@property (nonatomic, strong) UILabel *currentTimeLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIButton *speedButton;
@property (nonatomic, strong) id timeObserverToken;
@property (nonatomic, strong) NSTimer *hideControlsTimer;
@property (nonatomic, assign) BOOL isSeeking;
@property (nonatomic, assign) CGFloat currentSpeed;

@end

@implementation YTPPlayerVC

- (instancetype)initWithURL:(NSURL *)url title:(NSString *)title videoID:(NSString *)videoID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _videoURL = url;
        _videoTitle = title ?: @"Video";
        _videoID = videoID;
        _currentSpeed = 1.0;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    [self setupPlayer];
    [self setupUI];
    [self setupGestures];
    [self resumePlaybackProgress];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.playerLayer.frame = self.view.bounds;
    self.overlayView.frame = self.view.bounds;
}

- (void)setupPlayer {
    self.player = [AVPlayer playerWithURL:self.videoURL];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view.layer addSublayer:self.playerLayer];

    __weak typeof(self) weakSelf = self;
    self.timeObserverToken = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 2) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        [weakSelf updatePlaybackProgress:time];
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];

    [self.player play];
}

- (void)setupUI {
    self.overlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.overlayView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    [self.view addSubview:self.overlayView];

    // Close button
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeButton.frame = CGRectMake(20, 50, 40, 40);
    [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayView addSubview:self.closeButton];

    // Title label
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(70, 50, self.view.bounds.size.width - 140, 40)];
    self.titleLabel.text = self.videoTitle;
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.overlayView addSubview:self.titleLabel];

    // Play/Pause button
    self.playPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playPauseButton.frame = CGRectMake((self.view.bounds.size.width - 70) / 2, (self.view.bounds.size.height - 70) / 2, 70, 70);
    self.playPauseButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    self.playPauseButton.layer.cornerRadius = 35;
    [self.playPauseButton setTitle:@"⏸" forState:UIControlStateNormal];
    self.playPauseButton.titleLabel.font = [UIFont systemFontOfSize:28];
    [self.playPauseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayView addSubview:self.playPauseButton];

    // Bottom controls
    CGFloat bottomY = self.view.bounds.size.height - 90;

    self.currentTimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, bottomY + 5, 50, 20)];
    self.currentTimeLabel.textColor = [UIColor whiteColor];
    self.currentTimeLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.currentTimeLabel.text = @"00:00";
    [self.overlayView addSubview:self.currentTimeLabel];

    self.durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 120, bottomY + 5, 50, 20)];
    self.durationLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    self.durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.durationLabel.text = @"00:00";
    self.durationLabel.textAlignment = NSTextAlignmentRight;
    [self.overlayView addSubview:self.durationLabel];

    self.timeSlider = [[UISlider alloc] initWithFrame:CGRectMake(70, bottomY, self.view.bounds.size.width - 200, 30)];
    self.timeSlider.minimumTrackTintColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0];
    self.timeSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.4 alpha:0.6];
    [self.timeSlider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [self.timeSlider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.timeSlider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.overlayView addSubview:self.timeSlider];

    // Speed button
    self.speedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.speedButton.frame = CGRectMake(self.view.bounds.size.width - 60, bottomY, 50, 30);
    [self.speedButton setTitle:@"1.0x" forState:UIControlStateNormal];
    self.speedButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [self.speedButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.speedButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
    self.speedButton.layer.cornerRadius = 6;
    [self.speedButton addTarget:self action:@selector(speedTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayView addSubview:self.speedButton];

    [self resetHideControlsTimer];
}

- (void)setupGestures {
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap)];
    [self.view addGestureRecognizer:singleTap];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:doubleTap];

    [singleTap requireGestureRecognizerToFail:doubleTap];
}

- (void)handleSingleTap {
    BOOL isHidden = self.overlayView.alpha == 0;
    [UIView animateWithDuration:0.25 animations:^{
        self.overlayView.alpha = isHidden ? 1.0 : 0.0;
    }];
    if (isHidden) {
        [self resetHideControlsTimer];
    } else {
        [self.hideControlsTimer invalidate];
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.view];
    CGFloat width = self.view.bounds.size.width;
    CMTime currentTime = self.player.currentTime;
    CMTime offset = CMTimeMakeWithSeconds(10, 1);

    if (location.x < width / 2) {
        [self.player seekToTime:CMTimeSubtract(currentTime, offset)];
    } else {
        [self.player seekToTime:CMTimeAdd(currentTime, offset)];
    }
    [self resetHideControlsTimer];
}

- (void)resetHideControlsTimer {
    [self.hideControlsTimer invalidate];
    self.hideControlsTimer = [NSTimer scheduledTimerWithTimeInterval:3.5 target:self selector:@selector(hideControls) userInfo:nil repeats:NO];
}

- (void)hideControls {
    if (self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying && !self.isSeeking) {
        [UIView animateWithDuration:0.3 animations:^{
            self.overlayView.alpha = 0.0;
        }];
    }
}

- (void)playPauseTapped {
    if (self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying) {
        [self.player pause];
        [self.playPauseButton setTitle:@"▶" forState:UIControlStateNormal];
    } else {
        [self.player play];
        self.player.rate = self.currentSpeed;
        [self.playPauseButton setTitle:@"⏸" forState:UIControlStateNormal];
    }
    [self resetHideControlsTimer];
}

- (void)closeTapped {
    [self savePlaybackProgress];
    [self.player pause];
    [self.hideControlsTimer invalidate];
    if (self.timeObserverToken) {
        [self.player removeTimeObserver:self.timeObserverToken];
        self.timeObserverToken = nil;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)speedTapped {
    NSArray *speeds = @[@1.0, @1.25, @1.5, @1.75, @2.0, @0.5, @0.75];
    NSUInteger currentIndex = [speeds indexOfObject:@(self.currentSpeed)];
    NSUInteger nextIndex = (currentIndex == NSNotFound || currentIndex == speeds.count - 1) ? 0 : currentIndex + 1;
    self.currentSpeed = [speeds[nextIndex] floatValue];

    [self.speedButton setTitle:[NSString stringWithFormat:@"%.2gx", self.currentSpeed] forState:UIControlStateNormal];
    if (self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying) {
        self.player.rate = self.currentSpeed;
    }
    [self resetHideControlsTimer];
}

- (void)sliderTouchDown {
    self.isSeeking = YES;
    [self.hideControlsTimer invalidate];
}

- (void)sliderValueChanged:(UISlider *)slider {
    Float64 duration = CMTimeGetSeconds(self.player.currentItem.duration);
    if (!isnan(duration) && duration > 0) {
        Float64 targetSeconds = duration * slider.value;
        self.currentTimeLabel.text = [self formatSeconds:targetSeconds];
    }
}

- (void)sliderTouchUp {
    Float64 duration = CMTimeGetSeconds(self.player.currentItem.duration);
    if (!isnan(duration) && duration > 0) {
        Float64 targetSeconds = duration * self.timeSlider.value;
        CMTime targetTime = CMTimeMakeWithSeconds(targetSeconds, NSEC_PER_SEC);
        __weak typeof(self) weakSelf = self;
        [self.player seekToTime:targetTime completionHandler:^(BOOL finished) {
            weakSelf.isSeeking = NO;
            [weakSelf resetHideControlsTimer];
        }];
    } else {
        self.isSeeking = NO;
        [self resetHideControlsTimer];
    }
}

- (void)updatePlaybackProgress:(CMTime)time {
    if (self.isSeeking) return;

    Float64 current = CMTimeGetSeconds(time);
    Float64 duration = CMTimeGetSeconds(self.player.currentItem.duration);

    if (!isnan(current) && !isnan(duration) && duration > 0) {
        self.timeSlider.value = (float)(current / duration);
        self.currentTimeLabel.text = [self formatSeconds:current];
        self.durationLabel.text = [self formatSeconds:duration];
    }
}

- (void)playerDidFinishPlaying:(NSNotification *)notification {
    [self.playPauseButton setTitle:@"▶" forState:UIControlStateNormal];
    self.overlayView.alpha = 1.0;
    // Clear progress when video completes
    NSString *key = [self progressKey];
    if (key) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    }
}

- (NSString *)progressKey {
    NSString *idOrTitle = self.videoID ?: self.videoTitle;
    if (idOrTitle.length == 0) return nil;
    return [NSString stringWithFormat:@"YTP_Progress_%@", idOrTitle];
}

- (void)savePlaybackProgress {
    NSString *key = [self progressKey];
    Float64 current = CMTimeGetSeconds(self.player.currentTime);
    Float64 duration = CMTimeGetSeconds(self.player.currentItem.duration);

    if (key && !isnan(current) && !isnan(duration) && current > 5.0 && current < (duration - 5.0)) {
        [[NSUserDefaults standardUserDefaults] setDouble:current forKey:key];
    }
}

- (void)resumePlaybackProgress {
    NSString *key = [self progressKey];
    if (!key) return;

    double savedProgress = [[NSUserDefaults standardUserDefaults] doubleForKey:key];
    if (savedProgress > 5.0) {
        CMTime target = CMTimeMakeWithSeconds(savedProgress, NSEC_PER_SEC);
        [self.player seekToTime:target];
    }
}

- (NSString *)formatSeconds:(Float64)totalSeconds {
    if (isnan(totalSeconds) || totalSeconds < 0) return @"00:00";
    NSInteger hours = (NSInteger)(totalSeconds / 3600);
    NSInteger minutes = (NSInteger)((totalSeconds - (hours * 3600)) / 60);
    NSInteger seconds = (NSInteger)(totalSeconds - (hours * 3600) - (minutes * 60));

    if (hours > 0) {
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    } else {
        return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
    }
}

- (void)dealloc {
    [self.hideControlsTimer invalidate];
    if (self.timeObserverToken) {
        [self.player removeTimeObserver:self.timeObserverToken];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
