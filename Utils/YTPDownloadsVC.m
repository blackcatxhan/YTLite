#import "YTPDownloadsVC.h"
#import "YTPDownloader.h"
#import "YTPPlayerVC.h"

@interface YTPDownloadsVC ()

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<YTPDownloadItem *> *filteredItems;

@end

@implementation YTPDownloadsVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Downloads";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self setupNavButtons];
    [self setupSegmentedControl];
    [self setupTableView];
    [self reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadData];
}

- (void)setupNavButtons {
    UIBarButtonItem *closeBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem = closeBtn;
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)setupSegmentedControl {
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Videos", @"Audio"]];
    self.segmentedControl.selectedSegmentIndex = 0;
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segmentedControl;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 150, self.view.bounds.size.width - 40, 60)];
    self.emptyLabel.text = @"No downloads yet.\nDownloaded media will appear here.";
    self.emptyLabel.numberOfLines = 2;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    [self.view addSubview:self.emptyLabel];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    [self reloadData];
}

- (void)reloadData {
    NSArray<YTPDownloadItem *> *allItems = [YTPDownloader sharedDownloader].downloadedItems;
    NSInteger segment = self.segmentedControl.selectedSegmentIndex;

    if (segment == 1) { // Videos
        NSPredicate *p = [NSPredicate predicateWithFormat:@"isAudioOnly == NO"];
        self.filteredItems = [allItems filteredArrayUsingPredicate:p];
    } else if (segment == 2) { // Audio
        NSPredicate *p = [NSPredicate predicateWithFormat:@"isAudioOnly == YES"];
        self.filteredItems = [allItems filteredArrayUsingPredicate:p];
    } else {
        self.filteredItems = allItems;
    }

    self.emptyLabel.hidden = self.filteredItems.count > 0;
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"YTPDownloadCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    YTPDownloadItem *item = self.filteredItems[indexPath.row];
    cell.textLabel.text = item.title;
    cell.textLabel.numberOfLines = 2;
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];

    NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:item.fileSize countStyle:NSByteCountFormatterCountStyleFile];
    NSString *typeStr = item.isAudioOnly ? @"🎵 Audio" : @"🎬 Video";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", typeStr, sizeStr];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    YTPDownloadItem *item = self.filteredItems[indexPath.row];
    if (item.filePath && [[NSFileManager defaultManager] fileExistsAtPath:item.filePath]) {
        NSURL *fileURL = [NSURL fileURLWithPath:item.filePath];
        YTPPlayerVC *player = [[YTPPlayerVC alloc] initWithURL:fileURL title:item.title videoID:item.videoID];
        [self presentViewController:player animated:YES completion:nil];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    YTPDownloadItem *item = self.filteredItems[indexPath.row];

    // Delete action
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [[YTPDownloader sharedDownloader] deleteItem:item];
        [self reloadData];
        completionHandler(YES);
    }];

    // Share action
    UIContextualAction *shareAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Share" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        if (item.filePath) {
            UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:item.filePath]] applicationActivities:nil];
            [self presentViewController:avc animated:YES completion:nil];
        }
        completionHandler(YES);
    }];
    shareAction.backgroundColor = [UIColor systemBlueColor];

    // Save to Photos (video only)
    if (!item.isAudioOnly) {
        UIContextualAction *photosAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Photos" handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            [[YTPDownloader sharedDownloader] saveItemToPhotos:item completion:^(BOOL success, NSString *message) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save to Photos" message:message preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }];
            completionHandler(YES);
        }];
        photosAction.backgroundColor = [UIColor systemGreenColor];
        return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, shareAction, photosAction]];
    }

    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, shareAction]];
}

@end
