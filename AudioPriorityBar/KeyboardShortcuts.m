#import "KeyboardShortcuts.h"
#import <Carbon/Carbon.h>

NSString *const APBToggleMicrophoneMuteShortcut = @"toggleMicrophoneMute";
NSNotificationName const APBShortcutDidChangeNotification = @"APBShortcutDidChangeNotification";

static NSString *const DefaultsPrefix = @"KeyboardShortcuts_";

static NSInteger CarbonModifiers(NSEventModifierFlags flags) {
    NSInteger carbon = 0;
    if (flags & NSEventModifierFlagCommand) carbon |= cmdKey;
    if (flags & NSEventModifierFlagOption) carbon |= optionKey;
    if (flags & NSEventModifierFlagControl) carbon |= controlKey;
    if (flags & NSEventModifierFlagShift) carbon |= shiftKey;
    return carbon;
}

static NSEventModifierFlags ModifierFlags(NSInteger carbon) {
    NSEventModifierFlags flags = 0;
    if (carbon & cmdKey) flags |= NSEventModifierFlagCommand;
    if (carbon & optionKey) flags |= NSEventModifierFlagOption;
    if (carbon & controlKey) flags |= NSEventModifierFlagControl;
    if (carbon & shiftKey) flags |= NSEventModifierFlagShift;
    return flags;
}

static NSString *SymbolicModifiers(NSEventModifierFlags flags) {
    NSMutableString *description = [NSMutableString string];
    if (flags & NSEventModifierFlagControl) [description appendString:@"⌃"];
    if (flags & NSEventModifierFlagOption) [description appendString:@"⌥"];
    if (flags & NSEventModifierFlagShift) [description appendString:@"⇧"];
    if (flags & NSEventModifierFlagCommand) [description appendString:@"⌘"];
    return description;
}

/// Keys drawn as a symbol or name rather than the character they type.
static NSDictionary<NSNumber *, NSString *> *SpecialKeys(void) {
    static NSDictionary *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @{
            @(kVK_Return): @"↩", @(kVK_Delete): @"⌫", @(kVK_ForwardDelete): @"⌦",
            @(kVK_End): @"↘", @(kVK_Escape): @"⎋", @(kVK_Help): @"?⃝", @(kVK_Home): @"↖",
            @(kVK_Space): @"Space", @(kVK_Tab): @"⇥", @(kVK_PageUp): @"⇞", @(kVK_PageDown): @"⇟",
            @(kVK_UpArrow): @"↑", @(kVK_RightArrow): @"→", @(kVK_DownArrow): @"↓", @(kVK_LeftArrow): @"←",
            @(kVK_F1): @"F1", @(kVK_F2): @"F2", @(kVK_F3): @"F3", @(kVK_F4): @"F4", @(kVK_F5): @"F5",
            @(kVK_F6): @"F6", @(kVK_F7): @"F7", @(kVK_F8): @"F8", @(kVK_F9): @"F9", @(kVK_F10): @"F10",
            @(kVK_F11): @"F11", @(kVK_F12): @"F12", @(kVK_F13): @"F13", @(kVK_F14): @"F14",
            @(kVK_F15): @"F15", @(kVK_F16): @"F16", @(kVK_F17): @"F17", @(kVK_F18): @"F18",
            @(kVK_F19): @"F19", @(kVK_F20): @"F20",
            @(kVK_ANSI_Keypad0): @"0⃣", @(kVK_ANSI_Keypad1): @"1⃣", @(kVK_ANSI_Keypad2): @"2⃣",
            @(kVK_ANSI_Keypad3): @"3⃣", @(kVK_ANSI_Keypad4): @"4⃣", @(kVK_ANSI_Keypad5): @"5⃣",
            @(kVK_ANSI_Keypad6): @"6⃣", @(kVK_ANSI_Keypad7): @"7⃣", @(kVK_ANSI_Keypad8): @"8⃣",
            @(kVK_ANSI_Keypad9): @"9⃣", @(kVK_ANSI_KeypadClear): @"⌧", @(kVK_ANSI_KeypadDecimal): @".⃣",
            @(kVK_ANSI_KeypadDivide): @"/⃣", @(kVK_ANSI_KeypadEnter): @"⌅", @(kVK_ANSI_KeypadEquals): @"=⃣",
            @(kVK_ANSI_KeypadMinus): @"-⃣", @(kVK_ANSI_KeypadMultiply): @"*⃣", @(kVK_ANSI_KeypadPlus): @"+⃣",
        };
    });
    return keys;
}

static NSSet<NSNumber *> *FunctionKeys(void) {
    return [NSSet setWithArray:@[
        @(kVK_F1), @(kVK_F2), @(kVK_F3), @(kVK_F4), @(kVK_F5), @(kVK_F6), @(kVK_F7), @(kVK_F8),
        @(kVK_F9), @(kVK_F10), @(kVK_F11), @(kVK_F12), @(kVK_F13), @(kVK_F14), @(kVK_F15),
        @(kVK_F16), @(kVK_F17), @(kVK_F18), @(kVK_F19), @(kVK_F20),
    ]];
}

/// The character the key types with no modifiers on the current layout.
static NSString *KeyCharacter(NSInteger keyCode) {
    TISInputSourceRef source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
    if (!source) return nil;
    CFDataRef layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
    NSString *result = nil;
    if (layoutData) {
        const UCKeyboardLayout *layout = (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);
        UInt32 deadKeyState = 0;
        UniChar characters[4] = {0};
        UniCharCount length = 0;
        OSStatus status = UCKeyTranslate(layout, (UInt16)keyCode, kUCKeyActionDisplay, 0, LMGetKbdType(),
                                         kUCKeyTranslateNoDeadKeysMask, &deadKeyState, 4, &length, characters);
        if (status == noErr) {
            NSString *string = [NSString stringWithCharacters:characters length:length];
            // One user-perceived character, as Swift's `Character` required.
            NSRange first = string.length ? [string rangeOfComposedCharacterSequenceAtIndex:0] : NSMakeRange(0, 0);
            if (string.length > 0 && first.length == string.length) result = string;
        }
    }
    CFRelease(source);
    return result;
}

@implementation APBShortcut

- (instancetype)initWithCarbonKeyCode:(NSInteger)keyCode carbonModifiers:(NSInteger)modifiers {
    if ((self = [super init])) {
        _carbonKeyCode = keyCode;
        // Through AppKit's flags and back, dropping unsupported bits.
        _carbonModifiers = CarbonModifiers(ModifierFlags(modifiers));
    }
    return self;
}

- (instancetype)initWithKeyCode:(NSInteger)keyCode modifierFlags:(NSEventModifierFlags)flags {
    return [self initWithCarbonKeyCode:keyCode carbonModifiers:CarbonModifiers(flags)];
}

+ (instancetype)shortcutWithEvent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown && event.type != NSEventTypeKeyUp) return nil;
    // Recorders do not support Fn shortcuts, so it is stripped.
    return [[self alloc] initWithKeyCode:event.keyCode
                           modifierFlags:event.modifierFlags & ~NSEventModifierFlagFunction];
}

+ (instancetype)optionShiftM {
    for (NSInteger keyCode = 0; keyCode < 128; keyCode++) {
        APBShortcut *plain = [[self alloc] initWithCarbonKeyCode:keyCode carbonModifiers:0];
        if ([plain.displayString isEqualToString:@"M"]) {
            return [[self alloc] initWithKeyCode:keyCode
                                   modifierFlags:NSEventModifierFlagOption | NSEventModifierFlagShift];
        }
    }
    return nil;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSEventModifierFlags)modifierFlags {
    return ModifierFlags(_carbonModifiers);
}

- (BOOL)isFunctionKey {
    return [FunctionKeys() containsObject:@(_carbonKeyCode)];
}

- (NSString *)displayString {
    NSString *modifiers = SymbolicModifiers(self.modifierFlags);
    NSString *special = SpecialKeys()[@(_carbonKeyCode)];
    if (special) return [modifiers stringByAppendingString:special];
    NSString *character = KeyCharacter(_carbonKeyCode) ?: @"�";
    return [modifiers stringByAppendingString:character.capitalizedString];
}

- (NSString *)storageString {
    NSDictionary *object = @{@"carbonKeyCode": @(_carbonKeyCode), @"carbonModifiers": @(_carbonModifiers)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:NULL];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (instancetype)shortcutWithStorageString:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![object isKindOfClass:NSDictionary.class]) return nil;
    id keyCode = object[@"carbonKeyCode"], modifiers = object[@"carbonModifiers"];
    if (![keyCode isKindOfClass:NSNumber.class] || ![modifiers isKindOfClass:NSNumber.class]) return nil;
    return [[self alloc] initWithCarbonKeyCode:[keyCode integerValue] carbonModifiers:[modifiers integerValue]];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBShortcut.class]) return NO;
    APBShortcut *other = object;
    return _carbonKeyCode == other.carbonKeyCode && _carbonModifiers == other.carbonModifiers;
}

- (NSUInteger)hash {
    return (NSUInteger)(_carbonKeyCode << 16 | _carbonModifiers);
}

- (NSString *)description {
    return self.displayString;
}

@end

#pragma mark - Registration

static const OSType HotKeySignature = 'APBK';

/// One registered name: its handlers and, while active, its Carbon hot key.
@interface APBHotKeyEntry : NSObject
@property (nonatomic, readonly) UInt32 identifier;
@property (nonatomic, readonly) NSMutableArray<void (^)(void)> *handlers;
@property (nonatomic) EventHotKeyRef hotKey;
@end

@implementation APBHotKeyEntry

- (instancetype)initWithIdentifier:(UInt32)identifier {
    if ((self = [super init])) {
        _identifier = identifier;
        _handlers = [NSMutableArray array];
    }
    return self;
}

@end

static NSMutableDictionary<NSString *, APBHotKeyEntry *> *Entries(void) {
    static NSMutableDictionary *entries;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ entries = [NSMutableDictionary dictionary]; });
    return entries;
}

static BOOL IsPaused;

static OSStatus HandleHotKey(EventHandlerCallRef next, EventRef event, void *context) {
    EventHotKeyID hotKeyID;
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL,
                          sizeof hotKeyID, NULL, &hotKeyID) != noErr
        || hotKeyID.signature != HotKeySignature) {
        return eventNotHandledErr;
    }
    for (APBHotKeyEntry *entry in Entries().allValues) {
        if (entry.identifier != hotKeyID.id) continue;
        for (void (^handler)(void) in [entry.handlers copy]) handler();
        return noErr;
    }
    return eventNotHandledErr;
}

static void InstallHandlerIfNeeded(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        EventTypeSpec released = {kEventClassKeyboard, kEventHotKeyReleased};
        InstallEventHandler(GetEventDispatcherTarget(), HandleHotKey, 1, &released, NULL, NULL);
    });
}

@implementation APBKeyboardShortcuts

+ (NSString *)keyForName:(NSString *)name {
    return [DefaultsPrefix stringByAppendingString:name];
}

+ (void)setInitialShortcut:(APBShortcut *)shortcut forName:(NSString *)name {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *key = [self keyForName:name];
    if (!shortcut || [defaults objectForKey:key] != nil) return;
    [defaults setObject:shortcut.storageString forKey:key];
}

+ (APBShortcut *)shortcutForName:(NSString *)name {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:[self keyForName:name]];
    if (![stored isKindOfClass:NSString.class]) return nil;
    return [APBShortcut shortcutWithStorageString:stored];
}

+ (void)setShortcut:(APBShortcut *)shortcut forName:(NSString *)name {
    [self unregister:name];
    NSString *key = [self keyForName:name];
    if (shortcut) {
        [NSUserDefaults.standardUserDefaults setObject:shortcut.storageString forKey:key];
    } else {
        // False rather than removed, so an initial shortcut stays cleared.
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:key];
    }
    [self registerIfNeeded:name];
    [NSNotificationCenter.defaultCenter postNotificationName:APBShortcutDidChangeNotification object:name];
}

+ (void)onKeyUpForName:(NSString *)name handler:(void (^)(void))handler {
    InstallHandlerIfNeeded();
    APBHotKeyEntry *entry = Entries()[name];
    if (!entry) {
        static UInt32 nextIdentifier = 1;
        entry = [[APBHotKeyEntry alloc] initWithIdentifier:nextIdentifier++];
        Entries()[name] = entry;
    }
    [entry.handlers addObject:[handler copy]];
    [self registerIfNeeded:name];
}

+ (void)setPaused:(BOOL)paused {
    if (IsPaused == paused) return;
    IsPaused = paused;
    for (NSString *name in Entries().allKeys) {
        if (paused) {
            [self unregister:name];
        } else {
            [self registerIfNeeded:name];
        }
    }
}

+ (void)registerIfNeeded:(NSString *)name {
    APBHotKeyEntry *entry = Entries()[name];
    APBShortcut *shortcut = [self shortcutForName:name];
    if (IsPaused || !entry || entry.hotKey || entry.handlers.count == 0 || !shortcut) return;
    EventHotKeyID hotKeyID = {HotKeySignature, entry.identifier};
    EventHotKeyRef hotKey = NULL;
    if (RegisterEventHotKey((UInt32)shortcut.carbonKeyCode, (UInt32)shortcut.carbonModifiers, hotKeyID,
                            GetEventDispatcherTarget(), 0, &hotKey) == noErr) {
        entry.hotKey = hotKey;
    }
}

+ (void)unregister:(NSString *)name {
    APBHotKeyEntry *entry = Entries()[name];
    if (!entry.hotKey) return;
    UnregisterEventHotKey(entry.hotKey);
    entry.hotKey = NULL;
}

@end

#pragma mark - Recorder

static NSString *const IdlePlaceholder = @"Record Shortcut";
static NSString *const RecordingPlaceholder = @"Press Shortcut";

@interface APBShortcutRecorder () <NSSearchFieldDelegate>
@end

@implementation APBShortcutRecorder {
    NSString *_name;
    id _monitor;
    BOOL _isRecording;
}

- (instancetype)initWithName:(NSString *)name {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 130, 22)])) {
        _name = [name copy];
        self.delegate = self;
        self.placeholderString = IdlePlaceholder;
        self.alignment = NSTextAlignmentCenter;
        self.sendsWholeSearchString = YES;
        NSSearchFieldCell *cell = self.cell;
        cell.searchButtonCell = nil;
        cell.cancelButtonCell.target = self;
        cell.cancelButtonCell.action = @selector(clear:);
        [self.widthAnchor constraintEqualToConstant:130].active = YES;
        self.accessibilityLabel = @"Keyboard shortcut";
        [self showShortcut];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(shortcutDidChange:)
                                                   name:APBShortcutDidChangeNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self stopMonitoring];
}

- (void)shortcutDidChange:(NSNotification *)notification {
    if ([notification.object isEqual:_name] && !_isRecording) [self showShortcut];
}

- (void)showShortcut {
    self.stringValue = [APBKeyboardShortcuts shortcutForName:_name].displayString ?: @"";
}

- (BOOL)becomeFirstResponder {
    BOOL became = [super becomeFirstResponder];
    // Only a click on the field or tabbing into it starts recording, not the
    // window picking a first responder as it opens.
    NSEvent *event = NSApp.currentEvent;
    BOOL isClick = event.type == NSEventTypeLeftMouseDown && event.window == self.window
        && NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
    BOOL isTab = event.type == NSEventTypeKeyDown && event.keyCode == kVK_Tab && event.window == self.window;
    if (became && (isClick || isTab)) [self startRecording];
    return became;
}

- (void)mouseDown:(NSEvent *)event {
    [super mouseDown:event];
    if (!_isRecording && self.currentEditor) [self startRecording];
}

- (void)startRecording {
    if (_isRecording) return;
    _isRecording = YES;
    self.placeholderString = RecordingPlaceholder;
    self.stringValue = @"";
    [APBKeyboardShortcuts setPaused:YES];
    __weak typeof(self) weakSelf = self;
    _monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
                                                     handler:^NSEvent *(NSEvent *event) {
        return [weakSelf handleRecordingEvent:event];
    }];
}

- (NSEvent *)handleRecordingEvent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) {
        BOOL inside = event.window == self.window
            && NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
        if (!inside) [self endRecording];
        return event;
    }
    NSEventModifierFlags modifiers = event.modifierFlags
        & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift);
    if (modifiers == 0 && event.keyCode == kVK_Escape) {
        [self endRecording];
        return nil;
    }
    if (modifiers == 0 && (event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete)) {
        [APBKeyboardShortcuts setShortcut:nil forName:_name];
        [self endRecording];
        return nil;
    }
    if (modifiers == 0 && event.keyCode == kVK_Tab) {
        [self endRecording];
        return event;
    }
    APBShortcut *shortcut = [APBShortcut shortcutWithEvent:event];
    // Without Command, Option or Control a key would fire while typing.
    if (!shortcut || ((modifiers & ~NSEventModifierFlagShift) == 0 && !shortcut.isFunctionKey)) {
        NSBeep();
        return nil;
    }
    [APBKeyboardShortcuts setShortcut:shortcut forName:_name];
    [self endRecording];
    return nil;
}

- (void)stopMonitoring {
    if (_monitor) [NSEvent removeMonitor:_monitor];
    _monitor = nil;
}

- (void)endRecording {
    if (!_isRecording) return;
    _isRecording = NO;
    [self stopMonitoring];
    [APBKeyboardShortcuts setPaused:NO];
    self.placeholderString = IdlePlaceholder;
    [self showShortcut];
    if (self.window.firstResponder == self.currentEditor) [self.window makeFirstResponder:nil];
}

- (void)clear:(id)sender {
    [APBKeyboardShortcuts setShortcut:nil forName:_name];
    [self endRecording];
    [self showShortcut];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    // Typing never edits the field; only a recorded shortcut changes it.
    if (_isRecording) {
        self.stringValue = @"";
    } else {
        [self showShortcut];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    [self endRecording];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) [self endRecording];
}

@end
