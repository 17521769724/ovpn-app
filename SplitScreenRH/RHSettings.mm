//
//  RHSettings.mm
//  SplitScreenRH —— 内置设置界面
//
//  页面结构：
//    主页面：  功能总开关 / 分屏设置入口 / 应用管理入口 / 使用说明 / 重置
//    分屏设置：圆角大小、默认宽度、默认高度、触发边缘
//    应用管理：搜索、显示系统应用、逐个添加/移除分屏应用
//

#import "RHInternal.h"

#pragma mark - 圆角 / 百分比滑块单元格

@interface RHSliderCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UISlider *slider;
- (void)setTitle:(NSString *)title value:(CGFloat)value
             min:(CGFloat)min max:(CGFloat)max format:(NSString * (^)(CGFloat))format;
@end

@implementation RHSliderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        _titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
        [self.contentView addSubview:_titleLabel];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
        _valueLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_valueLabel];

        _slider = [[UISlider alloc] init];
        _slider.minimumTrackTintColor = [UIColor systemBlueColor];
        [self.contentView addSubview:_slider];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    _titleLabel.frame = CGRectMake(18.0, 10.0, width - 100.0, 22.0);
    _valueLabel.frame = CGRectMake(width - 96.0, 10.0, 80.0, 22.0);
    _slider.frame = CGRectMake(14.0, 40.0, width - 28.0, 28.0);
}

- (void)setTitle:(NSString *)title value:(CGFloat)value
             min:(CGFloat)min max:(CGFloat)max format:(NSString * (^)(CGFloat))format {
    _titleLabel.text = title;
    _slider.minimumValue = min;
    _slider.maximumValue = max;
    _slider.value = value;
    _valueLabel.text = format ? format(value) : [NSString stringWithFormat:@"%.0f", value];
}
@end

#pragma mark - 分屏设置页

@interface RHSplitSettingsVC : UITableViewController
@end

@implementation RHSplitSettingsVC {
    RHSliderCell *_radiusCell;
    RHSliderCell *_widthCell;
    RHSliderCell *_heightCell;
    UISegmentedControl *_edgeControl;
    NSTimer *_saveTimer;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"分屏设置";
    self.view.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    _radiusCell = [[RHSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [_radiusCell.slider addTarget:self action:@selector(radiusChanged) forControlEvents:UIControlEventValueChanged];

    _widthCell = [[RHSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [_widthCell.slider addTarget:self action:@selector(widthChanged) forControlEvents:UIControlEventValueChanged];

    _heightCell = [[RHSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [_heightCell.slider addTarget:self action:@selector(heightChanged) forControlEvents:UIControlEventValueChanged];

    _edgeControl = [[UISegmentedControl alloc] initWithItems:@[@"左侧", @"右侧", @"双侧"]];
    _edgeControl.selectedSegmentIndex = (NSInteger)RHTriggerEdge();
    [_edgeControl addTarget:self action:@selector(edgeChanged) forControlEvents:UIControlEventValueChanged];

    [self reloadValues];
}

- (void)reloadValues {
    [_radiusCell setTitle:@"小窗圆角大小" value:(CGFloat)RHCornerRadius() min:0 max:44
                   format:^NSString *(CGFloat v) { return [NSString stringWithFormat:@"%.0f pt", v]; }];
    [_widthCell setTitle:@"小窗默认宽度" value:(CGFloat)(RHWidthPercent() * 100.0) min:30 max:95
                  format:^NSString *(CGFloat v) { return [NSString stringWithFormat:@"%.0f%%", v]; }];
    [_heightCell setTitle:@"小窗默认高度" value:(CGFloat)(RHHeightPercent() * 100.0) min:30 max:95
                   format:^NSString *(CGFloat v) { return [NSString stringWithFormat:@"%.0f%%", v]; }];
    _edgeControl.selectedSegmentIndex = (NSInteger)RHTriggerEdge();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"小窗外观";
    return @"唤出手势";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return @"从所选屏幕边缘向内滑动即可唤出应用面板；小窗打开后，拖动边缘可缩放、点击小窗下方 ✕ 可关闭并保留应用后台。";
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return 76.0;
    return 86.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 0) return _radiusCell;
        if (indexPath.row == 1) return _widthCell;
        return _heightCell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    _edgeControl.frame = CGRectMake(16.0, 44.0, tableView.bounds.size.width - 64.0, 32.0);
    [cell.contentView addSubview:_edgeControl];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 10.0, 240.0, 22.0)];
    label.text = @"触发边缘";
    label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    label.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    [cell.contentView addSubview:label];
    return cell;
}

#pragma mark - 值变化（0.25s 防抖写盘）

- (void)scheduleSave {
    [_saveTimer invalidate];
    _saveTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self
                                                selector:@selector(commitSave) userInfo:nil repeats:NO];
}

- (void)commitSave {
    RHSetCornerRadius((CGFloat)_radiusCell.slider.value);
    RHSetWidthPercent((CGFloat)(_widthCell.slider.value / 100.0));
    RHSetHeightPercent((CGFloat)(_heightCell.slider.value / 100.0));
    RHSetTriggerEdge((RHEdgeMode)_edgeControl.selectedSegmentIndex);
    RHPostNotify(RHNotifySettingsChanged, nil);
}

- (void)radiusChanged {
    CGFloat v = (CGFloat)_radiusCell.slider.value;
    _radiusCell.valueLabel.text = [NSString stringWithFormat:@"%.0f pt", v];
    [self scheduleSave];
}

- (void)widthChanged {
    CGFloat v = (CGFloat)_widthCell.slider.value;
    _widthCell.valueLabel.text = [NSString stringWithFormat:@"%.0f%%", v];
    [self scheduleSave];
}

- (void)heightChanged {
    CGFloat v = (CGFloat)_heightCell.slider.value;
    _heightCell.valueLabel.text = [NSString stringWithFormat:@"%.0f%%", v];
    [self scheduleSave];
}

- (void)edgeChanged {
    [self commitSave];
}

@end

#pragma mark - 应用管理页

@interface RHAppManageVC : UITableViewController <UISearchBarDelegate>
@end

@implementation RHAppManageVC {
    NSArray<NSDictionary *> *_allApps;
    NSMutableArray<NSDictionary *> *_filteredApps;
    NSMutableSet<NSString *> *_selected;
    UISearchBar *_searchBar;
    BOOL _showSystem;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"应用管理";
    self.view.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    _selected = [NSMutableSet setWithArray:RHAddedApps()];

    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 44.0)];
    _searchBar.delegate = self;
    _searchBar.placeholder = @"搜索应用名称";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.tintColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    self.tableView.tableHeaderView = _searchBar;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSDictionary *> *apps = RHInstalledApps(YES);
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_allApps = apps;
            [self applyFilter];
        });
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveSelection];
}

- (void)saveSelection {
    RHSetAddedApps([_selected.allObjects sortedArrayUsingSelector:@selector(compare:)]);
    RHPostNotify(RHNotifySettingsChanged, nil);
}

- (void)applyFilter {
    NSString *keyword = _searchBar.text ?: @"";
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *app in _allApps) {
        BOOL isSystem = [app[@"system"] boolValue];
        if (isSystem && !_showSystem) continue;
        NSString *name = app[@"name"];
        NSString *bundleID = app[@"bundleID"];
        if (keyword.length == 0 ||
            [name localizedCaseInsensitiveContainsString:keyword] ||
            [bundleID localizedCaseInsensitiveContainsString:keyword]) {
            [list addObject:app];
        }
    }
    // 已添加的排在前面，方便查看
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL aSel = [self->_selected containsObject:a[@"bundleID"]];
        BOOL bSel = [self->_selected containsObject:b[@"bundleID"]];
        if (aSel != bSel) return aSel ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    _filteredApps = list;
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : (NSInteger)_filteredApps.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"选项" : [NSString stringWithFormat:@"应用列表（已添加 %lu 个）", (unsigned long)_selected.count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 56.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    cell.textLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == 0) {
        cell.textLabel.text = @"显示系统应用";
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = _showSystem;
        [toggle addTarget:self action:@selector(systemToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.detailTextLabel.text = @"默认仅显示第三方应用";
        return cell;
    }

    NSDictionary *app = _filteredApps[(NSUInteger)indexPath.row];
    NSString *bundleID = app[@"bundleID"];
    cell.textLabel.text = app[@"name"];
    cell.detailTextLabel.text = bundleID;

    UIImage *icon = RHIconForBundle(bundleID, 28.0);
    if (icon) {
        cell.imageView.image = [[UIImage alloc] initWithCGImage:icon.CGImage
                                                          scale:[UIScreen mainScreen].scale
                                                    orientation:UIImageOrientationUp];
        cell.imageView.layer.cornerRadius = 6.0;
        cell.imageView.clipsToBounds = YES;
    }

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = [_selected containsObject:bundleID];
    toggle.tag = (NSInteger)indexPath.row;
    [toggle addTarget:self action:@selector(appToggled:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (void)systemToggled:(UISwitch *)toggle {
    _showSystem = toggle.on;
    [self applyFilter];
}

- (void)appToggled:(UISwitch *)toggle {
    if (toggle.tag < 0 || toggle.tag >= (NSInteger)_filteredApps.count) return;
    NSDictionary *app = _filteredApps[(NSUInteger)toggle.tag];
    NSString *bundleID = app[@"bundleID"];
    if (toggle.on) {
        [_selected addObject:bundleID];
    } else {
        [_selected removeObject:bundleID];
    }
    [self saveSelection];
    [self applyFilter];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self applyFilter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

@end

#pragma mark - 文本说明页

@interface RHTextVC : UIViewController
@property (nonatomic, copy) NSString *content;
@end

@implementation RHTextVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
    textView.textColor = [UIColor colorWithWhite:1.0 alpha:0.88];
    textView.font = [UIFont systemFontOfSize:15];
    textView.editable = NO;
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.text = self.content;
    textView.textContainerInset = UIEdgeInsetsMake(18, 16, 18, 16);
    [self.view addSubview:textView];
}
@end

#pragma mark - 设置主页面

@interface RHSettingsRootVC ()
@property (nonatomic, strong) UISwitch *masterSwitch;
@end

@implementation RHSettingsRootVC

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"小窗分屏";
    self.view.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.tintColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(doneTapped)];
}

- (void)doneTapped {
    if (self.onClose) self.onClose();
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 2;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"总开关";
    if (section == 1) return @"设置";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"关闭后边缘手势与已打开的小窗都会失效。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    cell.textLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.42];

    if (indexPath.section == 0) {
        cell.textLabel.text = @"启用小窗分屏";
        cell.detailTextLabel.text = @"从屏幕边缘滑动唤出应用面板";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = RHIsEnabled();
        [toggle addTarget:self action:@selector(masterToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        self.masterSwitch = toggle;
        return cell;
    }

    if (indexPath.section == 1) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"分屏设置";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"圆角 %.0f pt · 宽 %.0f%% · 高 %.0f%%",
                                         RHCornerRadius(), RHWidthPercent() * 100.0, RHHeightPercent() * 100.0];
        } else {
            cell.textLabel.text = @"应用管理";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"已添加 %lu 个应用",
                                         (unsigned long)RHAddedApps().count];
        }
        return cell;
    }

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (indexPath.row == 0) {
        cell.textLabel.text = @"使用说明";
        cell.detailTextLabel.text = @"手势与小窗操作方式";
    } else {
        cell.textLabel.text = @"重置所有设置";
        cell.detailTextLabel.text = nil;
        cell.textLabel.textColor = [UIColor systemRedColor];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            [self.navigationController pushViewController:[[RHSplitSettingsVC alloc] init] animated:YES];
        } else {
            [self.navigationController pushViewController:[[RHAppManageVC alloc] init] animated:YES];
        }
        return;
    }
    if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            RHTextVC *textVC = [[RHTextVC alloc] init];
            textVC.title = @"使用说明";
            textVC.content =
                @"1. 先在「应用管理」中添加需要以小窗打开的应用。\n\n"
                 "2. 在任意界面（桌面或应用内），从所选屏幕边缘向内滑动，唤出表盘式应用面板。\n\n"
                 "3. 点击面板中的图标，应用会以小窗形式打开；小窗背后会显示原界面快照，原应用状态完整保留，不会与小窗冲突。\n\n"
                 "4. 拖动小窗的边缘或四角可以放大缩小；拖动顶部小条可以移动小窗。\n\n"
                 "5. 点击小窗下方的 ✕（或点击小窗外部任意位置）即可关闭小窗；被关闭的应用会保留在后台，随时可从多任务切换器回到它。\n\n"
                 "6. 关闭小窗后会自动回到打开小窗前的应用。\n\n"
                 "提示：如果边缘手势与应用自身的侧滑返回冲突，可在「分屏设置 - 触发边缘」中改为仅右侧触发。";
            [self.navigationController pushViewController:textVC animated:YES];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置所有设置"
                                                                          message:@"将恢复默认开关、圆角与尺寸，已添加的应用列表保留。"
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            __weak typeof(self) wself = self;
            [alert addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                RHResetDefaults();
                RHPostNotify(RHNotifySettingsChanged, nil);
                [wself.tableView reloadData];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

- (void)masterToggled:(UISwitch *)toggle {
    RHSetEnabled(toggle.on);
    RHPostNotify(RHNotifySettingsChanged, nil);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

@end