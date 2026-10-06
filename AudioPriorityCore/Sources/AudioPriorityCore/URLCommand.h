#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// An `audioprioritybar://` URL, as opened by Shortcuts, Raycast or a Stream
/// Deck. Any app or web page can open one, so only these exact forms are
/// accepted: no path, query, fragment, user or port.
typedef NS_ENUM(NSInteger, APBURLCommand) {
    APBURLCommandNone = 0,
    APBURLCommandToggleMicMute,
    APBURLCommandMuteMic,
    APBURLCommandUnmuteMic,
};

FOUNDATION_EXPORT NSString *const APBURLCommandScheme;

/// Every command, in declaration order.
FOUNDATION_EXPORT NSArray<NSNumber *> *APBURLCommandAllCases(void);
/// The host that names the command, like "toggle-mic-mute".
FOUNDATION_EXPORT NSString *_Nullable APBURLCommandRawValue(APBURLCommand command);
FOUNDATION_EXPORT APBURLCommand APBURLCommandFromRawValue(NSString *_Nullable rawValue);
/// `APBURLCommandNone` for anything but an exact command URL.
FOUNDATION_EXPORT APBURLCommand APBURLCommandFromURL(NSURL *url);

NS_ASSUME_NONNULL_END
