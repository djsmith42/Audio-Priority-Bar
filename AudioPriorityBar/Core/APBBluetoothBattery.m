#import "APBBluetoothBattery.h"

const NSInteger APBBatteryLevelNone = NSIntegerMin;

NSNotificationName const APBBluetoothBatteryDidChangeNotification = @"APBBluetoothBatteryDidChange";

@implementation APBBatteryLevels

- (instancetype)initWithLeft:(NSInteger)left right:(NSInteger)right caseLevel:(NSInteger)caseLevel main:(NSInteger)main {
    self = [super init];
    if (self) {
        _left = left;
        _right = right;
        _caseLevel = caseLevel;
        _main = main;
    }
    return self;
}

- (BOOL)isEmpty {
    return _left == APBBatteryLevelNone && _right == APBBatteryLevelNone
        && _caseLevel == APBBatteryLevelNone && _main == APBBatteryLevelNone;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBBatteryLevels.class]) return NO;
    APBBatteryLevels *other = object;
    return _left == other->_left && _right == other->_right
        && _caseLevel == other->_caseLevel && _main == other->_main;
}

- (NSUInteger)hash {
    return (NSUInteger)(_left ^ (_right << 8) ^ (_caseLevel << 16) ^ (_main << 24));
}

@end

@implementation APBBatteryBadge

+ (NSInteger)lowLevel {
    return 20;
}

- (instancetype)initWithIcon:(NSString *)icon text:(NSString *)text spokenText:(NSString *)spokenText level:(NSInteger)level {
    self = [super init];
    if (self) {
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
    return [_icon isEqualToString:other->_icon] && [_text isEqualToString:other->_text]
        && [_spokenText isEqualToString:other->_spokenText] && _isLow == other->_isLow;
}

- (NSUInteger)hash {
    return _text.hash;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<APBBatteryBadge %@ \"%@\" \"%@\"%@>",
            _icon, _text, _spokenText, _isLow ? @" low" : @""];
}

@end

@implementation APBBatteryLevels (Badges)

- (NSArray<APBBatteryBadge *> *)badges {
    NSMutableArray *result = [NSMutableArray array];
    if (self.main != APBBatteryLevelNone) {
        [result addObject:[[APBBatteryBadge alloc]
            initWithIcon:@"airpodsmax"
                    text:[NSString stringWithFormat:@"%ld%%", (long)self.main]
              spokenText:[NSString stringWithFormat:@"Battery %ld%%", (long)self.main]
                   level:self.main]];
    }
    NSMutableArray *shorts = [NSMutableArray array];
    NSMutableArray *longs = [NSMutableArray array];
    NSInteger lowest = NSIntegerMax;
    NSArray *sides = @[ @[ @"L", @"Left", @(self.left) ], @[ @"R", @"Right", @(self.right) ] ];
    for (NSArray *side in sides) {
        NSInteger level = [side[2] integerValue];
        if (level == APBBatteryLevelNone) continue;
        [shorts addObject:[NSString stringWithFormat:@"%@ %ld%%", side[0], (long)level]];
        [longs addObject:[NSString stringWithFormat:@"%@ earbud %ld%%", side[1], (long)level]];
        lowest = MIN(lowest, level);
    }
    if (self.left != APBBatteryLevelNone && self.left == self.right) {
        [result addObject:[[APBBatteryBadge alloc]
            initWithIcon:@"airpods"
                    text:[NSString stringWithFormat:@"%ld%%", (long)self.left]
              spokenText:[NSString stringWithFormat:@"Earbuds %ld%%", (long)self.left]
                   level:self.left]];
    } else if (shorts.count > 0) {
        [result addObject:[[APBBatteryBadge alloc]
            initWithIcon:@"airpods"
                    text:[shorts componentsJoinedByString:@" "]
              spokenText:[longs componentsJoinedByString:@", "]
                   level:lowest]];
    }
    if (self.caseLevel != APBBatteryLevelNone) {
        [result addObject:[[APBBatteryBadge alloc]
            initWithIcon:@"airpods.chargingcase"
                    text:[NSString stringWithFormat:@"%ld%%", (long)self.caseLevel]
              spokenText:[NSString stringWithFormat:@"Case %ld%%", (long)self.caseLevel]
                   level:self.caseLevel]];
    }
    return result;
}

@end

@implementation APBBluetoothBatteryReport

- (instancetype)init {
    return [self initWithByAddress:@{} byName:@{}];
}

- (instancetype)initWithByAddress:(NSDictionary<NSString *, APBBatteryLevels *> *)byAddress
                           byName:(NSDictionary<NSString *, APBBatteryLevels *> *)byName {
    self = [super init];
    if (self) {
        _byAddress = [byAddress copy];
        _byName = [byName copy];
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
    return [_byAddress isEqualToDictionary:other->_byAddress] && [_byName isEqualToDictionary:other->_byName];
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
    NSString *upper = text.uppercaseString;
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < upper.length; index++) {
        unichar character = [upper characterAtIndex:index];
        if ([hex characterIsMember:character]) [result appendFormat:@"%C", character];
    }
    return result;
}

+ (NSInteger)percent:(id)value {
    if (![value isKindOfClass:NSString.class]) return APBBatteryLevelNone;
    NSString *text = [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"% "]];
    NSScanner *scanner = [NSScanner scannerWithString:text];
    NSInteger level;
    if (text.length == 0 || ![scanner scanInteger:&level] || !scanner.isAtEnd) return APBBatteryLevelNone;
    return level;
}

+ (APBBluetoothBatteryReport *)parse:(NSData *)data {
    NSMutableDictionary *byAddress = [NSMutableDictionary dictionary];
    NSMutableDictionary *byName = [NSMutableDictionary dictionary];
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *controllers = [root isKindOfClass:NSDictionary.class] ? root[@"SPBluetoothDataType"] : nil;
    if (![controllers isKindOfClass:NSArray.class]) return [[APBBluetoothBatteryReport alloc] init];
    for (NSDictionary *controller in controllers) {
        if (![controller isKindOfClass:NSDictionary.class]) continue;
        NSArray *connected = controller[@"device_connected"];
        if (![connected isKindOfClass:NSArray.class]) continue;
        for (NSDictionary *entry in connected) {
            if (![entry isKindOfClass:NSDictionary.class]) continue;
            for (NSString *name in entry) {
                NSDictionary *info = entry[name];
                if (![info isKindOfClass:NSDictionary.class]) continue;
                NSString *vendor = info[@"device_vendorID"];
                if (![vendor isKindOfClass:NSString.class]
                    || ![vendor.uppercaseString isEqualToString:AppleVendorID.uppercaseString]) {
                    continue;
                }
                APBBatteryLevels *levels = [[APBBatteryLevels alloc]
                    initWithLeft:[self percent:info[@"device_batteryLevelLeft"]]
                           right:[self percent:info[@"device_batteryLevelRight"]]
                       caseLevel:[self percent:info[@"device_batteryLevelCase"]]
                            main:[self percent:info[@"device_batteryLevelMain"]]];
                if (levels.isEmpty) continue;
                NSString *address = info[@"device_address"];
                if ([address isKindOfClass:NSString.class]) {
                    byAddress[[self normalizedAddress:address]] = levels;
                }
                byName[name] = levels;
            }
        }
    }
    return [[APBBluetoothBatteryReport alloc] initWithByAddress:byAddress byName:byName];
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
    self = [super init];
    if (self) {
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
            [NSNotificationCenter.defaultCenter postNotificationName:APBBluetoothBatteryDidChangeNotification object:self];
        }
    }
    _isReading = NO;
    if (_isReadPending) {
        _isReadPending = NO;
        [self refresh];
    }
}

+ (APBBatteryRead)systemProfiler {
    return ^(APBBatteryReadCompletion completion) {
        NSTask *process = [[NSTask alloc] init];
        NSPipe *pipe = [NSPipe pipe];
        process.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/system_profiler"];
        process.arguments = @[ @"-json", @"SPBluetoothDataType" ];
        process.standardOutput = pipe;
        process.standardError = NSFileHandle.fileHandleWithNullDevice;
        if (![process launchAndReturnError:nil]) {
            completion(nil);
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
            [process waitUntilExit];
            completion(process.terminationStatus == 0 ? data : nil);
        });
    };
}

@end
