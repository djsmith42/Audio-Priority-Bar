#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, APBDeviceRole) {
    APBDeviceRoleInput,
    APBDeviceRoleOutput,
};

/// "input" or "output", the raw value persisted and used in identifiers.
FOUNDATION_EXPORT NSString *APBDeviceRoleName(APBDeviceRole role);

/// `APBOutputCategoryNone` stands for "no category", where Swift used nil.
typedef NS_ENUM(NSInteger, APBOutputCategory) {
    APBOutputCategoryNone = 0,
    APBOutputCategorySpeaker,
    APBOutputCategoryHeadphone,
};

/// "speaker" or "headphone", or nil for `APBOutputCategoryNone`.
FOUNDATION_EXPORT NSString *_Nullable APBOutputCategoryName(APBOutputCategory category);
/// Parses a persisted raw value, returning `APBOutputCategoryNone` when it is
/// not one.
FOUNDATION_EXPORT APBOutputCategory APBOutputCategoryFromName(NSString *_Nullable name);

/// Which devices the menu bar icon shows.
typedef NS_ENUM(NSInteger, APBMenuBarDevices) {
    APBMenuBarDevicesOutputOnly,
    /// The microphone, then the output.
    APBMenuBarDevicesBoth,
    APBMenuBarDevicesBothLabeled,
};

FOUNDATION_EXPORT NSString *APBMenuBarDevicesName(APBMenuBarDevices devices);
/// Returns NO when `name` is not a known raw value.
FOUNDATION_EXPORT BOOL APBMenuBarDevicesFromName(NSString *_Nullable name, APBMenuBarDevices *result);

/// `APBLinkStateNone` stands for "no state", where Swift used nil.
typedef NS_ENUM(NSInteger, APBLinkState) {
    APBLinkStateNone = 0,
    APBLinkStateUp,
    APBLinkStateDown,
    APBLinkStateUnknown,
    APBLinkStateMonitoringUnavailable,
    /// The dongle is being asked and has not answered yet. Bounded by the
    /// query timeout, so it never persists.
    APBLinkStateChecking,
};

/// One input or output endpoint. Compared by value, like the Swift struct it
/// replaces, so copies are interchangeable.
@interface APBAudioDevice : NSObject <NSCopying>

@property (nonatomic) UInt32 platformID;
@property (nonatomic, copy) NSString *uid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) APBDeviceRole role;
@property (nonatomic) BOOL isConnected;
/// Software routing device (Krisp, Zoom, a Multi-Output Device) rather than
/// a physical endpoint.
@property (nonatomic) BOOL isVirtual;
/// What the device says it is, from its audio terminal type. `None` when it
/// declares nothing usable, as aggregate and HDMI devices do.
@property (nonatomic) APBOutputCategory declaredCategory;
/// A monitor or TV reached over a video cable, from its transport type.
@property (nonatomic) BOOL isDisplayOutput;
/// CoreAudio's `kAudioDeviceTransportType*` value, used to pick an icon.
/// Zero when unknown, as it is for a disconnected device.
@property (nonatomic) UInt32 transportType;

/// The stable identity used by lists, "role:uid".
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *roleIdentifier;
@property (nonatomic, readonly) NSString *pairingKey;

- (instancetype)initWithPlatformID:(UInt32)platformID
                               uid:(NSString *)uid
                              name:(NSString *)name
                              role:(APBDeviceRole)role
                       isConnected:(BOOL)isConnected
                         isVirtual:(BOOL)isVirtual
                  declaredCategory:(APBOutputCategory)declaredCategory
                   isDisplayOutput:(BOOL)isDisplayOutput
                     transportType:(UInt32)transportType NS_DESIGNATED_INITIALIZER;

/// A connected, physical device with nothing declared.
- (instancetype)initWithPlatformID:(UInt32)platformID
                               uid:(NSString *)uid
                              name:(NSString *)name
                              role:(APBDeviceRole)role;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface APBStoredDevice : NSObject <NSCopying>

@property (nonatomic, readonly, copy) NSString *uid;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) BOOL isInput;
@property (nonatomic, copy) NSDate *lastSeen;
/// Remembered so a disconnected row keeps the category the hardware
/// declared. Optional, so settings written before this shipped still decode.
@property (nonatomic) APBOutputCategory declaredCategory;

@property (nonatomic, readonly) APBDeviceRole role;

- (instancetype)initWithUID:(NSString *)uid
                       name:(NSString *)name
                    isInput:(BOOL)isInput
                   lastSeen:(NSDate *)lastSeen
           declaredCategory:(APBOutputCategory)declaredCategory NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithDevice:(APBAudioDevice *)device lastSeen:(NSDate *)lastSeen;
- (instancetype)init NS_UNAVAILABLE;

- (APBAudioDevice *)disconnectedDevice;
- (NSString *)relativeLastSeenTo:(NSDate *)now;
- (NSString *)relativeLastSeen;

/// The JSON object written to defaults, matching the Swift `Codable` shape so
/// settings carry over in both directions.
- (NSDictionary<NSString *, id> *)JSONObject;
/// Nil when the object is not a valid stored device.
+ (nullable instancetype)deviceWithJSONObject:(id)object;

@end

NS_ASSUME_NONNULL_END
