#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, APBDeviceRole) {
    APBDeviceRoleInput,
    APBDeviceRoleOutput,
};

/// `None` stands in wherever a category is optional: a device that declares
/// nothing usable, or a list that holds microphones.
typedef NS_ENUM(NSInteger, APBOutputCategory) {
    APBOutputCategoryNone,
    APBOutputCategorySpeaker,
    APBOutputCategoryHeadphone,
};

/// Which devices the menu bar icon shows.
typedef NS_ENUM(NSInteger, APBMenuBarDevices) {
    APBMenuBarDevicesOutputOnly,
    /// The microphone, then the output.
    APBMenuBarDevicesBoth,
    APBMenuBarDevicesBothLabeled,
};

/// `None` means no state at all, as for a device nobody monitors or one that
/// is disconnected.
typedef NS_ENUM(NSInteger, APBLinkState) {
    APBLinkStateNone,
    APBLinkStateUp,
    APBLinkStateDown,
    APBLinkStateUnknown,
    APBLinkStateMonitoringUnavailable,
    /// The dongle is being asked and has not answered yet. Bounded by the
    /// query timeout, so it never persists.
    APBLinkStateChecking,
};

FOUNDATION_EXPORT NSString *APBDeviceRoleName(APBDeviceRole role);
FOUNDATION_EXPORT APBDeviceRole APBDeviceRoleOther(APBDeviceRole role);
FOUNDATION_EXPORT NSString *_Nullable APBOutputCategoryName(APBOutputCategory category);
FOUNDATION_EXPORT APBOutputCategory APBOutputCategoryFromName(NSString *_Nullable name);
FOUNDATION_EXPORT NSString *APBMenuBarDevicesName(APBMenuBarDevices devices);
/// Unknown names read as `OutputOnly`.
FOUNDATION_EXPORT APBMenuBarDevices APBMenuBarDevicesFromName(NSString *_Nullable name);

@interface APBAudioDevice : NSObject <NSCopying>

@property (nonatomic, readonly) UInt32 platformID;
@property (nonatomic, readonly, copy) NSString *uid;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) APBDeviceRole role;
@property (nonatomic, readonly) BOOL isConnected;
/// Software routing device (Krisp, Zoom, a Multi-Output Device) rather than
/// a physical endpoint.
@property (nonatomic, readonly) BOOL isVirtual;
/// What the device says it is, from its audio terminal type. `None` when it
/// declares nothing usable, as aggregate and HDMI devices do.
@property (nonatomic, readonly) APBOutputCategory declaredCategory;
/// A monitor or TV reached over a video cable, from its transport type.
@property (nonatomic, readonly) BOOL isDisplayOutput;
/// CoreAudio's `kAudioDeviceTransportType*` value, used to pick an icon.
/// Zero when unknown, as it is for a disconnected device.
@property (nonatomic, readonly) UInt32 transportType;

/// `role:uid`, the identity a row keeps across refreshes.
@property (nonatomic, readonly) NSString *identifier;
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

/// A connected physical device with nothing declared.
- (instancetype)initWithPlatformID:(UInt32)platformID
                               uid:(NSString *)uid
                              name:(NSString *)name
                              role:(APBDeviceRole)role;

- (instancetype)init NS_UNAVAILABLE;

/// A copy that differs only in whether it is connected.
- (APBAudioDevice *)deviceWithConnected:(BOOL)isConnected;

@end

@interface APBStoredDevice : NSObject

@property (nonatomic, readonly, copy) NSString *uid;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) BOOL isInput;
@property (nonatomic, readonly) NSDate *lastSeen;
/// Remembered so a disconnected row keeps the category the hardware declared.
/// Optional, so settings written before this shipped still decode.
@property (nonatomic, readonly) APBOutputCategory declaredCategory;
@property (nonatomic, readonly) APBDeviceRole role;

- (instancetype)initWithUID:(NSString *)uid
                       name:(NSString *)name
                    isInput:(BOOL)isInput
                   lastSeen:(NSDate *)lastSeen
           declaredCategory:(APBOutputCategory)declaredCategory NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithDevice:(APBAudioDevice *)device lastSeen:(NSDate *)lastSeen;
- (instancetype)init NS_UNAVAILABLE;

- (APBAudioDevice *)disconnectedDevice;
- (NSString *)relativeLastSeen;
- (NSString *)relativeLastSeenTo:(NSDate *)now;

/// The shape the Swift app's `JSONEncoder` wrote, so saved devices survive the
/// move: dates as seconds since 2001, the category as its raw name.
- (NSDictionary<NSString *, id> *)JSONObject;
/// Nil when the object is not a valid stored device.
+ (nullable instancetype)deviceWithJSONObject:(id)object;

@end

NS_ASSUME_NONNULL_END
