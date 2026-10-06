#import <Foundation/Foundation.h>
#import "Models.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, APBJabraProfileID) {
    APBJabraProfileIDNone = 0,
    APBJabraProfileIDLink380,
    APBJabraProfileIDLink390,
};

typedef NS_ENUM(NSInteger, APBJabraSignalKind) {
    /// A HID element whose value equals `linkedValue` while linked.
    APBJabraSignalKindElement,
    /// A bit in an input report.
    APBJabraSignalKindReport,
};

/// Where a dongle model publishes its legacy telephony link bit.
@interface APBJabraSignal : NSObject

@property (nonatomic, readonly) APBJabraSignalKind kind;
// Element signals.
@property (nonatomic, readonly) NSInteger page;
@property (nonatomic, readonly) NSInteger usage;
@property (nonatomic, readonly) NSInteger linkedValue;
// Report signals.
@property (nonatomic, readonly) NSInteger reportID;
@property (nonatomic, readonly) NSInteger byteIndex;
@property (nonatomic, readonly) uint8_t bitMask;

+ (instancetype)elementWithPage:(NSInteger)page usage:(NSInteger)usage linkedValue:(NSInteger)linkedValue;
+ (instancetype)reportWithID:(NSInteger)reportID byteIndex:(NSInteger)byteIndex bitMask:(uint8_t)bitMask;

@end

@interface APBJabraProfile : NSObject

@property (nonatomic, readonly) APBJabraProfileID identifier;
@property (nonatomic, readonly, copy) NSString *product;
@property (nonatomic, readonly) APBJabraSignal *signal;

- (instancetype)initWithIdentifier:(APBJabraProfileID)identifier
                           product:(NSString *)product
                            signal:(APBJabraSignal *)signal;

@end

@interface APBJabraLink : NSObject

@property (class, nonatomic, readonly) NSInteger vendorID;
@property (class, nonatomic, readonly) NSArray<APBJabraProfile *> *profiles;

+ (nullable APBJabraProfile *)profileMatching:(NSString *)name;

/// Only a Link dongle can publish an audio device whose headset is absent.
/// A Jabra headset or speakerphone plugged in directly is present whenever
/// macOS lists it, yet it may expose the same management collection, so
/// monitoring one would let an empty pairing list report it as off.
+ (BOOL)isDongleProduct:(NSString *)name;

/// USB serial embedded in a CoreAudio device UID, used to bind an audio
/// device to one physical dongle instead of to every dongle of its model.
/// Example UID:
/// `AppleUSBAudioEngine:Unknown Manufacturer:Jabra Link 380:50C275445423:1`
+ (nullable NSString *)serialFromAudioUID:(NSString *)uid;
+ (BOOL)serial:(NSString *)left matches:(NSString *)right;

+ (BOOL)decodeElementValue:(NSInteger)value linkedValue:(NSInteger)linkedValue;
/// Nil when `timestamp` is zero, meaning the element was never read.
+ (nullable NSNumber *)snapshotValue:(NSInteger)value
                           timestamp:(uint64_t)timestamp
                         linkedValue:(NSInteger)linkedValue;
+ (nullable NSNumber *)decodeReportID:(NSInteger)reportID
                           expectedID:(NSInteger)expectedID
                                bytes:(NSData *)bytes
                            byteIndex:(NSInteger)byteIndex
                              bitMask:(uint8_t)bitMask;

+ (BOOL)allowsSelectionIsSupported:(BOOL)isSupported state:(APBLinkState)state;

@end

typedef NS_ENUM(NSInteger, APBLinkTransition) {
    APBLinkTransitionUnchanged,
    APBLinkTransitionChanged,
    APBLinkTransitionScheduleDown,
    APBLinkTransitionCancelDown,
};

/// The legacy link bit with a delayed "down", since the bit flickers. Each
/// value is nil until known.
@interface APBDebouncedLinkState : NSObject <NSCopying>

@property (nonatomic, readonly, nullable) NSNumber *observed;
@property (nonatomic, readonly, nullable) NSNumber *effective;

- (instancetype)init;
- (instancetype)initWithObserved:(nullable NSNumber *)observed
                       effective:(nullable NSNumber *)effective NS_DESIGNATED_INITIALIZER;

- (BOOL)seed:(BOOL)linked;
- (APBLinkTransition)observe:(BOOL)linked;
- (BOOL)commitDown;

@end

NS_ASSUME_NONNULL_END
