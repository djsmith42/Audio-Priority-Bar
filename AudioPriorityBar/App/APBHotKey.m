#import "APBHotKey.h"
#import <Carbon/Carbon.h>

NSNotificationName const APBHotKeyDidChangeNotification = @"APBHotKeyDidChange";

static NSString *DefaultsKey(NSString *name) {
    return [@"KeyboardShortcuts_" stringByAppendingString:name];
}

static NSString *SpecialKeyName(NSInteger keyCode) {
    static NSDictionary<NSNumber *, NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
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
    return names[@(keyCode)];
}

/// The character a key types with no modifiers on the current ASCII-capable
/// layout.
static NSString *KeyCharacter(NSInteger keyCode) {
    TISInputSourceRef source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
    if (!source) return nil;
    CFDataRef layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
    NSString *result = nil;
    if (layoutData) {
        const UCKeyboardLayout *layout = (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);
        UInt32 deadKeyState = 0;
        UniChar characters[4];
        UniCharCount length = 0;
        OSStatus status = UCKeyTranslate(layout, (UInt16)keyCode, kUCKeyActionDisplay, 0, LMGetKbdType(),
                                         kUCKeyTranslateNoDeadKeysBit, &deadKeyState, 4, &length, characters);
        if (status == noErr && length > 0) {
            NSString *string = [NSString stringWithCharacters:characters length:length];
            // One user-perceived character only.
            if ([string rangeOfComposedCharacterSequenceAtIndex:0].length == string.length) result = string;
        }
    }
    CFRelease(source);
    return result;
}

@implementation APBShortcut

- (instancetype)initWithCarbonKeyCode:(NSInteger)keyCode carbonModifiers:(NSInteger)modifiers {
    self = [super init];
    if (self) {
        _carbonKeyCode = keyCode;
        _carbonModifiers = modifiers & (cmdKey | optionKey | controlKey | shiftKey);
    }
    return self;
}

+ (NSInteger)carbonModifiersFromFlags:(NSEventModifierFlags)flags {
    NSInteger modifiers = 0;
    if (flags & NSEventModifierFlagCommand) modifiers |= cmdKey;
    if (flags & NSEventModifierFlagOption) modifiers |= optionKey;
    if (flags & NSEventModifierFlagControl) modifiers |= controlKey;
    if (flags & NSEventModifierFlagShift) modifiers |= shiftKey;
    return modifiers;
}

+ (instancetype)shortcutWithEvent:(NSEvent *)event {
    NSInteger modifiers = [self carbonModifiersFromFlags:event.modifierFlags];
    BOOL isFunctionKey = event.keyCode >= kVK_F1 && SpecialKeyName(event.keyCode).length > 1
        && [SpecialKeyName(event.keyCode) hasPrefix:@"F"];
    // A global shortcut needs a modifier other than Shift alone, except for
    // the function keys, which type nothing.
    if (!isFunctionKey && (modifiers & ~shiftKey) == 0) return nil;
    return [[self alloc] initWithCarbonKeyCode:event.keyCode carbonModifiers:modifiers];
}

+ (instancetype)optionShiftM {
    for (NSInteger keyCode = 0; keyCode < 128; keyCode++) {
        if (SpecialKeyName(keyCode)) continue;
        if ([KeyCharacter(keyCode).uppercaseString isEqualToString:@"M"]) {
            return [[self alloc] initWithCarbonKeyCode:keyCode carbonModifiers:optionKey | shiftKey];
        }
    }
    return nil;
}

- (NSString *)displayString {
    NSMutableString *string = [NSMutableString string];
    if (_carbonModifiers & controlKey) [string appendString:@"⌃"];
    if (_carbonModifiers & optionKey) [string appendString:@"⌥"];
    if (_carbonModifiers & shiftKey) [string appendString:@"⇧"];
    if (_carbonModifiers & cmdKey) [string appendString:@"⌘"];
    NSString *key = SpecialKeyName(_carbonKeyCode) ?: KeyCharacter(_carbonKeyCode).capitalizedString ?: @"�";
    [string appendString:key];
    return string;
}

- (NSString *)JSONString {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{
        @"carbonKeyCode": @(_carbonKeyCode),
        @"carbonModifiers": @(_carbonModifiers),
    } options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (instancetype)shortcutWithJSONString:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![object isKindOfClass:NSDictionary.class]) return nil;
    NSNumber *keyCode = object[@"carbonKeyCode"];
    NSNumber *modifiers = object[@"carbonModifiers"];
    if (![keyCode isKindOfClass:NSNumber.class] || ![modifiers isKindOfClass:NSNumber.class]) return nil;
    return [[self alloc] initWithCarbonKeyCode:keyCode.integerValue carbonModifiers:modifiers.integerValue];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBShortcut.class]) return NO;
    APBShortcut *other = object;
    return _carbonKeyCode == other->_carbonKeyCode && _carbonModifiers == other->_carbonModifiers;
}

- (NSUInteger)hash {
    return (NSUInteger)(_carbonKeyCode << 16 | _carbonModifiers);
}

@end

#pragma mark - Hot key

static const OSType HotKeySignature = 'APBk';
static NSMutableDictionary<NSNumber *, APBHotKey *> *RegisteredHotKeys;
static UInt32 NextHotKeyID = 1;

static OSStatus HotKeyHandler(EventHandlerCallRef next, EventRef event, void *context) {
    EventHotKeyID hotKeyID;
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof hotKeyID, NULL, &hotKeyID) != noErr
        || hotKeyID.signature != HotKeySignature) {
        return eventNotHandledErr;
    }
    APBHotKey *hotKey = RegisteredHotKeys[@(hotKeyID.id)];
    if (GetEventKind(event) == kEventHotKeyReleased && hotKey.onKeyUp && !hotKey.isPaused) hotKey.onKeyUp();
    return noErr;
}

@implementation APBHotKey {
    EventHotKeyRef _registration;
    UInt32 _identifier;
}

+ (void)installHandlerIfNeeded {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        RegisteredHotKeys = [NSMutableDictionary dictionary];
        EventTypeSpec types[] = {
            { kEventClassKeyboard, kEventHotKeyPressed },
            { kEventClassKeyboard, kEventHotKeyReleased },
        };
        InstallApplicationEventHandler(HotKeyHandler, 2, types, NULL, NULL);
    });
}

- (instancetype)initWithName:(NSString *)name initial:(APBShortcut *)initial {
    self = [super init];
    if (self) {
        [APBHotKey installHandlerIfNeeded];
        _name = [name copy];
        _identifier = NextHotKeyID++;
        RegisteredHotKeys[@(_identifier)] = self;
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if (initial && [defaults objectForKey:DefaultsKey(name)] == nil) {
            [defaults setObject:initial.JSONString forKey:DefaultsKey(name)];
        }
        [self registerCurrent];
    }
    return self;
}

- (void)dealloc {
    [self unregister];
}

- (APBShortcut *)shortcut {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:DefaultsKey(_name)];
    return [stored isKindOfClass:NSString.class] ? [APBShortcut shortcutWithJSONString:stored] : nil;
}

- (void)setShortcut:(APBShortcut *)shortcut {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (shortcut) {
        [defaults setObject:shortcut.JSONString forKey:DefaultsKey(_name)];
    } else {
        // `false` rather than removal, so the initial shortcut never returns.
        [defaults setBool:NO forKey:DefaultsKey(_name)];
    }
    [self registerCurrent];
    [NSNotificationCenter.defaultCenter postNotificationName:APBHotKeyDidChangeNotification object:self];
}

- (void)setPaused:(BOOL)paused {
    if (_paused == paused) return;
    _paused = paused;
    [self registerCurrent];
}

- (void)registerCurrent {
    [self unregister];
    APBShortcut *shortcut = self.shortcut;
    if (!shortcut || _paused) return;
    EventHotKeyID hotKeyID = { HotKeySignature, _identifier };
    RegisterEventHotKey((UInt32)shortcut.carbonKeyCode, (UInt32)shortcut.carbonModifiers, hotKeyID,
                        GetApplicationEventTarget(), 0, &_registration);
}

- (void)unregister {
    if (!_registration) return;
    UnregisterEventHotKey(_registration);
    _registration = NULL;
}

@end

#pragma mark - Recorder

@interface APBShortcutRecorder () <NSSearchFieldDelegate>
@end

@implementation APBShortcutRecorder {
    APBHotKey *_hotKey;
    NSSearchField *_field;
    id _monitor;
    BOOL _isRecording;
}

- (instancetype)initWithHotKey:(APBHotKey *)hotKey {
    self = [super initWithFrame:NSMakeRect(0, 0, 130, 24)];
    if (self) {
        _hotKey = hotKey;
        _field = [[NSSearchField alloc] initWithFrame:self.bounds];
        _field.translatesAutoresizingMaskIntoConstraints = NO;
        _field.alignment = NSTextAlignmentCenter;
        _field.delegate = self;
        _field.placeholderString = @"Record Shortcut";
        _field.focusRingType = NSFocusRingTypeDefault;
        // The search glyph means nothing here; only the clear button stays.
        NSSearchFieldCell *cell = _field.cell;
        cell.searchButtonCell = nil;
        cell.cancelButtonCell.target = self;
        cell.cancelButtonCell.action = @selector(clear:);
        _field.editable = NO;
        _field.selectable = NO;
        [self addSubview:_field];
        [NSLayoutConstraint activateConstraints:@[
            [_field.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_field.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_field.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_field.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.widthAnchor constraintEqualToConstant:130],
        ]];
        NSClickGestureRecognizer *click = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(startRecording)];
        [_field addGestureRecognizer:click];
        [self setAccessibilityElement:YES];
        [self setAccessibilityRole:NSAccessibilityButtonRole];
        [self setAccessibilityLabel:@"Record shortcut"];
        [self show];
    }
    return self;
}

- (void)dealloc {
    [self stopRecording];
}

- (void)show {
    APBShortcut *shortcut = _hotKey.shortcut;
    _field.stringValue = _isRecording ? @"" : shortcut.displayString ?: @"";
    _field.placeholderString = _isRecording ? @"Press Shortcut" : @"Record Shortcut";
    [self setAccessibilityValue:shortcut.displayString ?: @"None"];
}

- (BOOL)accessibilityPerformPress {
    [self startRecording];
    return YES;
}

- (void)clear:(id)sender {
    [self stopRecording];
    _hotKey.shortcut = nil;
    [self show];
}

- (void)startRecording {
    if (_isRecording) return;
    _isRecording = YES;
    _hotKey.paused = YES;
    [self.window makeFirstResponder:_field];
    [self show];
    __weak typeof(self) weakSelf = self;
    _monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskLeftMouseDown
                                                     handler:^NSEvent *(NSEvent *event) {
        return [weakSelf handle:event];
    }];
}

- (NSEvent *)handle:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        if (event.window != self.window || !NSPointInRect(point, self.bounds)) [self stopRecording];
        return event;
    }
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL hasModifiers = (flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption
                                  | NSEventModifierFlagControl | NSEventModifierFlagShift)) != 0;
    if (!hasModifiers && event.keyCode == kVK_Escape) {
        [self stopRecording];
        return nil;
    }
    if (!hasModifiers && (event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete)) {
        [self clear:nil];
        return nil;
    }
    if (!hasModifiers && event.keyCode == kVK_Tab) {
        [self stopRecording];
        return event;
    }
    APBShortcut *shortcut = [APBShortcut shortcutWithEvent:event];
    if (!shortcut) {
        NSBeep();
        return nil;
    }
    [self stopRecording];
    _hotKey.shortcut = shortcut;
    [self show];
    return nil;
}

- (void)stopRecording {
    if (!_isRecording) return;
    _isRecording = NO;
    if (_monitor) [NSEvent removeMonitor:_monitor];
    _monitor = nil;
    _hotKey.paused = NO;
    if (self.window.firstResponder == _field || self.window.firstResponder == _field.currentEditor) {
        [self.window makeFirstResponder:nil];
    }
    [self show];
}

- (void)viewWillMoveToWindow:(NSWindow *)window {
    if (!window) [self stopRecording];
    [super viewWillMoveToWindow:window];
}

@end
