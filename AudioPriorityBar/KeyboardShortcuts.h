#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The microphone mute shortcut's storage name.
FOUNDATION_EXPORT NSString *const APBToggleMicrophoneMuteShortcut;
/// Posted after a stored shortcut changes, with the name as the object.
FOUNDATION_EXPORT NSNotificationName const APBShortcutDidChangeNotification;

/// A global keyboard shortcut: a physical key and its modifiers, both in
/// Carbon's encoding.
@interface APBShortcut : NSObject <NSCopying>

@property (nonatomic, readonly) NSInteger carbonKeyCode;
@property (nonatomic, readonly) NSInteger carbonModifiers;
@property (nonatomic, readonly) NSEventModifierFlags modifierFlags;

- (instancetype)initWithCarbonKeyCode:(NSInteger)keyCode carbonModifiers:(NSInteger)modifiers;
- (instancetype)initWithKeyCode:(NSInteger)keyCode modifierFlags:(NSEventModifierFlags)flags;
/// Nil for anything but a key event.
+ (nullable instancetype)shortcutWithEvent:(NSEvent *)event;

/// Shortcuts store a physical key, so this looks up the key that types M on
/// the current layout, a different key on AZERTY than on QWERTY. Starts as
/// the default mute shortcut, which no call app uses for its own mute.
+ (nullable instancetype)optionShiftM;

/// Like "⌥⇧M", the way macOS menus show shortcuts.
@property (nonatomic, readonly) NSString *displayString;
/// A key that works as a shortcut without modifiers, like F5.
@property (nonatomic, readonly) BOOL isFunctionKey;

/// The JSON stored in defaults, the same as the KeyboardShortcuts library
/// wrote, so a shortcut set before the port keeps working.
@property (nonatomic, readonly) NSString *storageString;
+ (nullable instancetype)shortcutWithStorageString:(NSString *)string;

@end

/// Stores shortcuts in the standard defaults under
/// "KeyboardShortcuts_<name>", and registers them as Carbon hot keys.
@interface APBKeyboardShortcuts : NSObject

/// Stores `shortcut` unless the user has already set or cleared one.
+ (void)setInitialShortcut:(nullable APBShortcut *)shortcut forName:(NSString *)name;
+ (nullable APBShortcut *)shortcutForName:(NSString *)name;
/// Nil clears the shortcut, remembering that it was cleared rather than never
/// set, so the initial one never comes back.
+ (void)setShortcut:(nullable APBShortcut *)shortcut forName:(NSString *)name;
/// Runs `handler` when the shortcut's key is released.
+ (void)onKeyUpForName:(NSString *)name handler:(void (^)(void))handler;
/// Suspends every hot key, so a recorder can capture one that is in use.
+ (void)setPaused:(BOOL)paused;

@end

/// A field that records a shortcut when clicked, like the one in the system's
/// own Keyboard settings. Its clear button removes the shortcut.
@interface APBShortcutRecorder : NSSearchField

- (instancetype)initWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
