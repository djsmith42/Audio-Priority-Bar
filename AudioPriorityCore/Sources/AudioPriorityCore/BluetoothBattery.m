#import "BluetoothBattery.h"

static BOOL Same(id left, id right) {
    return left == right || [left isEqual:right];
}

@implementation APBBatteryBadge

+ (NSInteger)lowLevel {
    return 20;
}

- (instancetype)initWithIcon:(NSString *)icon
                        text:(NSString *)text
                  spokenText:(NSString *)spokenText
                       level:(NSInteger)level {
    if ((self = [super init])) {
        _icon = [icon copy];
        _text = [text copy];
        _spokenText = [spokenText copy];
        _isLow = level <= APBBatteryBadge.lowLevel;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBBatteryBadge.class]) return NO;
    APBBatteryBadge *other = object;
    return [_icon isEqualToString:other.icon] && [_text isEqualToString:other.text]
        && [_spokenText isEqualToString:other.spokenText] && _isLow == other.isLow;
}

- (NSUInteger)hash {
    return _text.hash;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<badge %@ \"%@\" \"%@\"%@>",
            _icon, _text, _spokenText, _isLow ? @" low" : @""];
}

@end

@implementation APBBatteryLevels

+ (instancetype)levelsWithLeft:(NSNumber *)left
                         right:(NSNumber *)right
                     caseLevel:(NSNumber *)caseLevel
                          main:(NSNumber *)main
                       headset:(NSNumber *)headset {
    APBBatteryLevels *levels = [[self alloc] init];
    levels.left = left;
    levels.right = right;
    levels.caseLevel = caseLevel;
    levels.main = main;
    levels.headset = headset;
    return levels;
}

- (id)copyWithZone:(NSZone *)zone {
    return [APBBatteryLevels levelsWithLeft:_left right:_right caseLevel:_caseLevel
                                       main:_main headset:_headset];
}

- (BOOL)isEmpty {
    return !_left && !_right && !_caseLevel && !_main && !_headset;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBBatteryLevels.class]) return NO;
    APBBatteryLevels *other = object;
    return Same(_left, other.left) && Same(_right, other.right)
        && Same(_caseLevel, other.caseLevel) && Same(_main, other.main)
        && Same(_headset, other.headset);
}

- (NSUInteger)hash {
    return _left.hash ^ _right.hash ^ _caseLevel.hash ^ _main.hash ^ _headset.hash;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<levels L %@ R %@ case %@ main %@ headset %@>",
            _left, _right, _caseLevel, _main, _headset];
}

- (NSArray<APBBatteryBadge *> *)badges {
    NSMutableArray<APBBatteryBadge *> *result = [NSMutableArray array];
    if (_main) {
        NSInteger main = _main.integerValue;
        [result addObject:[[APBBatteryBadge alloc]
            initWithIcon:@"airpodsmax"
                    text:[NSString stringWithFormat:@"%ld%%", (long)main]
              spokenText:[NSString stringWithFormat:@"Battery %ld%%", (long)main]
                   level:main]];
    }
    if (_headset) {
        NSInteger headset = _headset.integerValue;
        [result addObject:[[APBBatteryBadge alloc]
            initWithIcon:@"headphones"
                    text:[NSString stringWithFormat:@"%ld%%", (long)headset]
              spokenText:[NSString stringWithFormat:@"Battery %ld%%", (long)headset]
                   level:headset]];
    }
    if (_left && [_left isEqual:_right]) {
        NSInteger left = _left.integerValue;
        [result addObject:[[APBBatteryBadge alloc]
            initWithIcon:@"airpods"
                    text:[NSString stringWithFormat:@"%ld%%", (long)left]
              spokenText:[NSString stringWithFormat:@"Earbuds %ld%%", (long)left]
                   level:left]];
    } else if (_left || _right) {
        NSMutableArray *texts = [NSMutableArray array], *spoken = [NSMutableArray array];
        NSInteger lowest = NSIntegerMax;
        NSArray *sides = @[
            @[@"L", @"Left", _left ?: NSNull.null],
            @[@"R", @"Right", _right ?: NSNull.null],
        ];
        for (NSArray *side in sides) {
            if (side[2] == NSNull.null) continue;
            NSInteger level = [side[2] integerValue];
            [texts addObject:[NSString stringWithFormat:@"%@ %ld%%", side[0], (long)level]];
            [spoken addObject:[NSString stringWithFormat:@"%@ earbud %ld%%", side[1], (long)level]];
            lowest = MIN(lowest, level);
        }
        [result addObject:[[APBBatteryBadge alloc]
            initWithIcon:@"airpods"
                    text:[texts componentsJoinedByString:@" "]
              spokenText:[spoken componentsJoinedByString:@", "]
                   level:lowest]];
    }
    if (_caseLevel) {
        NSInteger level = _caseLevel.integerValue;
        [result addObject:[[APBBatteryBadge alloc]
            initWithIcon:@"airpods.chargingcase"
                    text:[NSString stringWithFormat:@"%ld%%", (long)level]
              spokenText:[NSString stringWithFormat:@"Case %ld%%", (long)level]
                   level:level]];
    }
    return result;
}

@end

@implementation APBBluetoothBatteryReport

- (instancetype)init {
    if ((self = [super init])) {
        _byAddress = @{};
        _byName = @{};
    }
    return self;
}

- (APBBatteryLevels *)levelsForDevice:(APBAudioDevice *)device {
    NSString *uid = [APBBluetoothBattery normalizedAddress:device.uid];
    for (NSString *address in _byAddress) {
        if ([uid hasPrefix:address]) return _byAddress[address];
    }
    return _byName[device.name];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBBluetoothBatteryReport.class]) return NO;
    APBBluetoothBatteryReport *other = object;
    return [_byAddress isEqualToDictionary:other.byAddress]
        && [_byName isEqualToDictionary:other.byName];
}

- (NSUInteger)hash {
    return _byAddress.count ^ (_byName.count << 8);
}

@end

/// Apple's Bluetooth vendor ID, carried by AirPods and Beats.
static NSString *const AppleVendorID = @"0x004C";

@implementation APBBluetoothBattery

+ (NSString *)normalizedAddress:(NSString *)text {
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"];
    NSMutableString *result = [NSMutableString string];
    NSString *upper = text.uppercaseString;
    for (NSUInteger index = 0; index < upper.length; index++) {
        unichar character = [upper characterAtIndex:index];
        if ([hex characterIsMember:character]) [result appendFormat:@"%C", character];
    }
    return result;
}

+ (NSNumber *)percent:(id)value {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:
                         [NSCharacterSet characterSetWithCharactersInString:@"% "]];
    // Swift's Int(_:) accepts only an optional sign and digits.
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    scanner.charactersToBeSkipped = nil;
    NSInteger number = 0;
    if (trimmed.length == 0 || ![scanner scanInteger:&number] || !scanner.isAtEnd) return nil;
    return @(number);
}

+ (APBBluetoothBatteryReport *)parse:(NSData *)data {
    APBBluetoothBatteryReport *report = [[APBBluetoothBatteryReport alloc] init];
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![root isKindOfClass:NSDictionary.class]) return report;
    id controllers = root[@"SPBluetoothDataType"];
    if (![controllers isKindOfClass:NSArray.class]) return report;
    NSMutableDictionary *byAddress = [NSMutableDictionary dictionary];
    NSMutableDictionary *byName = [NSMutableDictionary dictionary];
    for (id controller in controllers) {
        if (![controller isKindOfClass:NSDictionary.class]) return report;
        id entries = controller[@"device_connected"];
        if (![entries isKindOfClass:NSArray.class]) continue;
        for (id entry in entries) {
            if (![entry isKindOfClass:NSDictionary.class]) continue;
            for (NSString *name in entry) {
                NSDictionary *info = entry[name];
                if (![info isKindOfClass:NSDictionary.class]) continue;
                id vendor = info[@"device_vendorID"];
                if (![vendor isKindOfClass:NSString.class]
                    || ![[vendor uppercaseString] isEqualToString:AppleVendorID.uppercaseString]) {
                    continue;
                }
                APBBatteryLevels *levels = [APBBatteryLevels
                    levelsWithLeft:[self percent:info[@"device_batteryLevelLeft"]]
                             right:[self percent:info[@"device_batteryLevelRight"]]
                         caseLevel:[self percent:info[@"device_batteryLevelCase"]]
                              main:[self percent:info[@"device_batteryLevelMain"]]
                           headset:nil];
                if (levels.isEmpty) continue;
                id address = info[@"device_address"];
                if ([address isKindOfClass:NSString.class]) {
                    byAddress[[self normalizedAddress:address]] = levels;
                }
                byName[name] = levels;
            }
        }
    }
    report.byAddress = byAddress;
    report.byName = byName;
    return report;
}

@end

@implementation APBBluetoothBatteryMonitor {
    APBBatteryRead _read;
    BOOL _isReading;
    BOOL _isReadPending;
}

- (instancetype)init {
    return [self initWithRead:APBBluetoothBatteryMonitor.systemProfiler];
}

- (instancetype)initWithRead:(APBBatteryRead)read {
    if ((self = [super init])) {
        _read = [read copy];
        _report = [[APBBluetoothBatteryReport alloc] init];
    }
    return self;
}

- (APBBatteryLevels *)levelsForDevice:(APBAudioDevice *)device {
    return device.isConnected ? [_report levelsForDevice:device] : nil;
}

- (void)refresh {
    if (_isReading) {
        _isReadPending = YES;
        return;
    }
    _isReading = YES;
    __weak typeof(self) weakSelf = self;
    _read(^(NSData *data) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf finishReadWithData:data];
        });
    });
}

- (void)finishReadWithData:(NSData *)data {
    if (data) {
        APBBluetoothBatteryReport *report = [APBBluetoothBattery parse:data];
        if (![report isEqual:_report]) {
            _report = report;
            if (_onChange) _onChange();
        }
    }
    _isReading = NO;
    if (_isReadPending) {
        _isReadPending = NO;
        [self refresh];
    }
}

+ (APBBatteryRead)systemProfiler {
    return ^(void (^completion)(NSData *)) {
        NSTask *task = [[NSTask alloc] init];
        NSPipe *pipe = [NSPipe pipe];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/system_profiler"];
        task.arguments = @[@"-json", @"SPBluetoothDataType"];
        task.standardOutput = pipe;
        task.standardError = NSFileHandle.fileHandleWithNullDevice;
        if (![task launchAndReturnError:NULL]) {
            completion(nil);
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
            [task waitUntilExit];
            completion(task.terminationStatus == 0 ? data : nil);
        });
    };
}

@end
