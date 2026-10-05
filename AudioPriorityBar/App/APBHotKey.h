#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A physical key and Carbon modifiers, stored the way the KeyboardShortcuts
/// package stored them so a shortcut set before survives.
@interface APBShortcut : NSObject

@property (nonatomic, readonly) NSInteger carbonKeyCode;
@property (nonatomic, readonly) NSInteger carbonModifiers;
/// What the shortcut types on the current layout, like `⌥⇧M`.
@property (nonatomic, readonly) NSString *displayString;

- (instancetype)initWithCarbonKeyCode:(NSInteger)keyCode carbonModifiers:(NSInteger)modifiers NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
/// Nil when the event has no modifier that makes a usable global shortcut.
+ (nullable instancetype)shortcutWithEvent:(NSEvent *)event;

/// Shortcuts store a physical key, so this looks up the key that types M on
/// the current layout, a different key on AZERTY than on QWERTY.
+ (nullable instancetype)optionShiftM;

+ (NSInteger)carbonModifiersFromFlags:(NSEventModifierFlags)flags;

@end

/// One global shortcut, registered with Carbon while it has a value. Stored
/// under `KeyboardShortcuts_<name>`: JSON while set, `false` once cleared.
@interface APBHotKey : NSObject

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, nullable) APBShortcut *shortcut;
/// Called on key up, matching KeyboardShortcuts' `onKeyUp`.
@property (nonatomic, copy, nullable) dispatch_block_t onKeyUp;

/// Stores `initial` the first time, so a cleared shortcut stays cleared.
- (instancetype)initWithName:(NSString *)name initial:(nullable APBShortcut *)initial;
- (instancetype)init NS_UNAVAILABLE;

/// While recording, the hotkey must not fire for the keys being pressed.
@property (nonatomic, getter=isPaused) BOOL paused;

@end

FOUNDATION_EXPORT NSNotificationName const APBHotKeyDidChangeNotification;

/// A field that records a shortcut when clicked, like the KeyboardShortcuts
/// recorder: Escape cancels, Delete clears, and the clear button resets.
@interface APBShortcutRecorder : NSView
- (instancetype)initWithHotKey:(APBHotKey *)hotKey;
@end

NS_ASSUME_NONNULL_END
