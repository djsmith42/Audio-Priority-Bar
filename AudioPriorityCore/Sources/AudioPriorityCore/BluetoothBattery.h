#import <Foundation/Foundation.h>
#import "Models.h"

NS_ASSUME_NONNULL_BEGIN

/// One battery shown on a device row: the earbuds, the case, or a single
/// battery.
@interface APBBatteryBadge : NSObject

/// At or below this level a badge is flagged as low.
@property (class, nonatomic, readonly) NSInteger lowLevel;

@property (nonatomic, readonly, copy) NSString *icon;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSString *spokenText;
@property (nonatomic, readonly) BOOL isLow;

- (instancetype)initWithIcon:(NSString *)icon
                        text:(NSString *)text
                  spokenText:(NSString *)spokenText
                       level:(NSInteger)level;

@end

/// Battery percentages one Bluetooth device reports, each nil while it
/// reports nothing for that part, as for a pod sitting in a closed case.
@interface APBBatteryLevels : NSObject <NSCopying>

@property (nonatomic, nullable) NSNumber *left;
@property (nonatomic, nullable) NSNumber *right;
@property (nonatomic, nullable) NSNumber *caseLevel;
/// Headphones with one battery, such as AirPods Max.
@property (nonatomic, nullable) NSNumber *main;
/// A headset other than AirPods, such as a Jabra behind its Link dongle.
@property (nonatomic, nullable) NSNumber *headset;

+ (instancetype)levelsWithLeft:(nullable NSNumber *)left
                         right:(nullable NSNumber *)right
                     caseLevel:(nullable NSNumber *)caseLevel
                          main:(nullable NSNumber *)main
                       headset:(nullable NSNumber *)headset;

@property (nonatomic, readonly) BOOL isEmpty;

/// Earbuds first, then the case, each only while it reports a level. The
/// earbuds share a badge, one number when they match and named by side
/// otherwise, flagged low when either is.
@property (nonatomic, readonly) NSArray<APBBatteryBadge *> *badges;

@end

@interface APBBluetoothBatteryReport : NSObject

/// Keyed by address, uppercased hex digits with separators removed.
@property (nonatomic, copy) NSDictionary<NSString *, APBBatteryLevels *> *byAddress;
@property (nonatomic, copy) NSDictionary<NSString *, APBBatteryLevels *> *byName;

/// Levels for an audio device. CoreAudio gives a Bluetooth device a UID
/// built from its address, such as `70-AE-2A-5E-21-CD:output`; the name is a
/// fallback for a UID in some other shape.
- (nullable APBBatteryLevels *)levelsForDevice:(APBAudioDevice *)device;

@end

@interface APBBluetoothBattery : NSObject

+ (NSString *)normalizedAddress:(NSString *)text;

/// Parses `system_profiler -json SPBluetoothDataType`, keeping connected
/// Apple headphones that report at least one level.
+ (APBBluetoothBatteryReport *)parse:(NSData *)data;

@end

/// Hands the read data, or nil, to `completion` on any thread.
typedef void (^APBBatteryRead)(void (^completion)(NSData *_Nullable data));

/// Reads AirPods battery levels from `system_profiler`, which needs no
/// Bluetooth permission. Each read takes a few hundred milliseconds, so it
/// runs off the main thread and only when asked.
@interface APBBluetoothBatteryMonitor : NSObject

@property (nonatomic, readonly) APBBluetoothBatteryReport *report;
/// Called on the main thread after `report` changes.
@property (nonatomic, copy, nullable) void (^onChange)(void);

/// Runs `system_profiler`.
- (instancetype)init;
- (instancetype)initWithRead:(APBBatteryRead)read NS_DESIGNATED_INITIALIZER;

+ (APBBatteryRead)systemProfiler;

- (nullable APBBatteryLevels *)levelsForDevice:(APBAudioDevice *)device;

/// Starts a read, or queues one more if a read is already running so a
/// change made during it is not missed.
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
