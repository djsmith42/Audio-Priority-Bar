#import "JabraHIDMonitor.h"
#import <IOKit/hid/IOHIDLib.h>

static const NSTimeInterval DownDebounce = 3;
static const NSTimeInterval PollInterval = 2;
/// The dongle's false "linked" claim lands about 1.8s after enumeration, so
/// positive legacy claims inside this window are not evidence.
static const NSTimeInterval EnumerationSuppression = 3;
/// A completed walk costs about 0.4s when nothing is connected, so the
/// safety-net refresh is slow. Real transitions do not wait for it: the
/// dongle announces them and that triggers a walk immediately. This only
/// covers an announcement being missed entirely.
static const NSTimeInterval VendorRefreshInterval = 10;
/// A settled dongle answers in about 4ms, but for roughly 265ms after
/// enumeration it silently drops requests instead of queueing them. So the
/// per-request wait is short and a dropped request is simply re-sent,
/// keeping the overall budget for a first answer near 1.5s.
static const NSTimeInterval QueryTimeout = 0.5;
static const NSInteger MaximumAttempts = 3;
/// The headset also reports a changed level on its own, so asking is only
/// the backstop.
static const NSTimeInterval BatteryRefreshInterval = 60;

static NSTimeInterval Uptime(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

/// Keys IOHID objects by identity, retaining them.
static NSMapTable *IdentityMap(void) {
    return [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
                                 valueOptions:NSPointerFunctionsStrongMemory];
}

/// One HID interface. A dongle may expose several.
@interface APBJabraInterface : NSObject
@property (nonatomic, readonly) IOHIDDeviceRef device;
@property (nonatomic, readonly, nullable) APBJabraProfile *profile;
@property (nonatomic, nullable) IOHIDElementRef legacyElement;
@property (nonatomic, nullable) APBGNPLayout *management;
@property (nonatomic, nullable) IOHIDElementRef managementOutput;
@property (nonatomic, readonly) APBGNPReassembler *reassembler;
@property (nonatomic, nullable) uint8_t *buffer;
@property (nonatomic) CFIndex bufferSize;
@end

@implementation APBJabraInterface {
    id _deviceObject;
    id _legacyObject;
    id _outputObject;
}

- (instancetype)initWithDevice:(IOHIDDeviceRef)device profile:(APBJabraProfile *)profile {
    if ((self = [super init])) {
        _deviceObject = (__bridge id)device;
        _device = device;
        _profile = profile;
        _reassembler = [[APBGNPReassembler alloc] init];
    }
    return self;
}

- (void)setLegacyElement:(IOHIDElementRef)element {
    _legacyObject = (__bridge id)element;
    _legacyElement = element;
}

- (void)setManagementOutput:(IOHIDElementRef)element {
    _outputObject = (__bridge id)element;
    _managementOutput = element;
}

- (void)dealloc {
    free(_buffer);
}

@end

/// One in-flight pairing-database walk.
@interface APBJabraQuery : NSObject
@property (nonatomic, readonly) APBGNPPairingWalk *walk;
@property (nonatomic) uint8_t sequence;
@property (nonatomic, copy, nullable) dispatch_block_t timeout;
/// Request in flight, kept so a dropped one can be re-sent.
@property (nonatomic, copy) NSData *cursor;
@property (nonatomic) uint8_t bluetoothType;
@property (nonatomic) NSInteger attempt;
@property (nonatomic, readonly) NSInteger generation;
@property (nonatomic, readonly) APBJabraInterface *interface;
@end

@implementation APBJabraQuery

- (instancetype)initWithGeneration:(NSInteger)generation interface:(APBJabraInterface *)interface {
    if ((self = [super init])) {
        _walk = [[APBGNPPairingWalk alloc] init];
        _cursor = [NSData data];
        _generation = generation;
        _interface = interface;
    }
    return self;
}

@end

/// One physical dongle, identified by serial so two dongles of the same model
/// never contaminate each other's state.
@interface APBJabraDongle : NSObject
@property (nonatomic, readonly, copy) NSString *key;
@property (nonatomic, readonly, copy, nullable) NSString *serial;
@property (nonatomic) APBJabraProfileID profileID;
/// IOHIDDevice to APBJabraInterface.
@property (nonatomic, readonly) NSMapTable *interfaces;
/// Bumped whenever membership changes, so asynchronous work that completes
/// late cannot update a replacement dongle.
@property (nonatomic) NSInteger generation;
@property (nonatomic) NSTimeInterval attachedAt;
@property (nonatomic, readonly) APBDebouncedLinkState *legacy;
@property (nonatomic, copy, nullable) dispatch_block_t pendingDown;
@property (nonatomic) APBGNPEvidence vendor;
@property (nonatomic, nullable) NSNumber *resolved;
/// Last state published to the model. Tracked as a link state rather than a
/// boolean so leaving `checking` still notifies even when the underlying
/// value happens to be unchanged.
@property (nonatomic) APBLinkState reported;
@property (nonatomic, nullable) APBJabraQuery *query;
@property (nonatomic) NSTimeInterval lastQueryAt;
/// True until the first query for this attachment settles. Until then the
/// legacy bit is not trustworthy, because the dongle lies right after
/// enumeration.
@property (nonatomic) BOOL awaitingFirstAnswer;
/// Set when the dongle announced a change while a walk was already running.
/// Announcements arrive in pairs about 100ms apart, so that walk may have
/// read its records before the change landed and another has to follow it.
@property (nonatomic) BOOL requeryWhenIdle;
/// The headset's battery percentage, nil until it answers.
@property (nonatomic, nullable) NSNumber *battery;
@property (nonatomic) NSTimeInterval lastBatteryQueryAt;
@end

@implementation APBJabraDongle

- (instancetype)initWithKey:(NSString *)key serial:(NSString *)serial attachedAt:(NSTimeInterval)attachedAt {
    if ((self = [super init])) {
        _key = [key copy];
        _serial = [serial copy];
        _attachedAt = attachedAt;
        _interfaces = IdentityMap();
        _legacy = [[APBDebouncedLinkState alloc] init];
        _lastQueryAt = -DBL_MAX;
        _awaitingFirstAnswer = YES;
        _lastBatteryQueryAt = -DBL_MAX;
    }
    return self;
}

- (APBJabraInterface *)managementInterface {
    for (APBJabraInterface *interface in _interfaces.objectEnumerator) {
        if (interface.management) return interface;
    }
    return nil;
}

@end

typedef NS_ENUM(NSInteger, APBBindingKind) {
    APBBindingUnmonitored,
    APBBindingOne,
    /// Known to be a Jabra we would monitor, but not bindable to exactly one
    /// dongle, so it must fail open rather than borrow another's state.
    APBBindingUnidentified,
};

static void MatchCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device);
static void RemovalCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device);
static void ValueCallback(void *context, IOReturn result, void *sender, IOHIDValueRef value);
static void ReportCallback(void *context, IOReturn result, void *sender, IOHIDReportType type,
                           uint32_t reportID, uint8_t *report, CFIndex length);

@interface APBJabraHIDMonitor ()
@property (nonatomic, readonly) BOOL isRunning;
@end

@implementation APBJabraHIDMonitor {
    IOHIDManagerRef _manager;
    NSTimer *_pollTimer;
    NSMutableDictionary<NSString *, APBJabraDongle *> *_dongles;
    /// IOHIDDevice to dongle key.
    NSMapTable *_interfaceKeys;
    uint8_t _sequence;
}

- (instancetype)init {
    if ((self = [super init])) {
        _dongles = [NSMutableDictionary dictionary];
        _interfaceKeys = IdentityMap();
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Lifecycle

- (void)start {
    if (_manager) return;
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    _manager = manager;
    _isRunning = YES;
    IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)@{
        @kIOHIDVendorIDKey: @(APBJabraLink.vendorID),
    });
    void *context = (__bridge void *)self;
    IOHIDManagerRegisterDeviceMatchingCallback(manager, MatchCallback, context);
    IOHIDManagerRegisterDeviceRemovalCallback(manager, RemovalCallback, context);
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    if (IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        _isRunning = NO;
        CFRelease(manager);
        _manager = NULL;
        return;
    }
    NSSet *matched = CFBridgingRelease(IOHIDManagerCopyDevices(manager));
    for (id device in matched) [self attach:(__bridge IOHIDDeviceRef)device];
}

- (void)stop {
    IOHIDManagerRef manager = _manager;
    if (!manager) return;
    _isRunning = NO;
    [_pollTimer invalidate];
    _pollTimer = nil;
    for (APBJabraDongle *dongle in _dongles.allValues) {
        dongle.generation += 1;
        if (dongle.pendingDown) dispatch_block_cancel(dongle.pendingDown);
        dongle.pendingDown = nil;
        if (dongle.query.timeout) dispatch_block_cancel(dongle.query.timeout);
        dongle.query = nil;
        for (APBJabraInterface *interface in dongle.interfaces.objectEnumerator) [self tearDown:interface];
    }
    [_dongles removeAllObjects];
    [_interfaceKeys removeAllObjects];
    IOHIDManagerRegisterDeviceMatchingCallback(manager, NULL, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(manager, NULL, NULL);
    IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
    CFRelease(manager);
    _manager = NULL;
}

#pragma mark - Queries from the model

- (APBLinkState)linkStateForDevice:(APBAudioDevice *)device {
    APBJabraDongle *dongle = nil;
    switch ([self bindingFor:device dongle:&dongle]) {
        case APBBindingUnmonitored: return APBLinkStateUnknown;
        case APBBindingUnidentified: return APBLinkStateMonitoringUnavailable;
        case APBBindingOne: return [self.class stateOf:dongle];
    }
}

- (BOOL)isUsable:(APBAudioDevice *)device {
    BOOL isSupported = [self bindingFor:device dongle:NULL] != APBBindingUnmonitored;
    return [APBJabraLink allowsSelectionIsSupported:isSupported state:[self linkStateForDevice:device]];
}

- (APBLinkState)monitoredStateForDevice:(APBAudioDevice *)device {
    if ([self bindingFor:device dongle:NULL] == APBBindingUnmonitored) return APBLinkStateNone;
    return [self linkStateForDevice:device];
}

- (NSNumber *)batteryLevelForDevice:(APBAudioDevice *)device {
    APBJabraDongle *dongle = nil;
    if ([self bindingFor:device dongle:&dongle] != APBBindingOne
        || [self.class stateOf:dongle] != APBLinkStateUp) {
        return nil;
    }
    return dongle.battery;
}

/// Binds an audio device to at most one physical dongle. The USB serial in
/// the CoreAudio UID is preferred because it is exact; the product name is
/// only consulted when the serial cannot identify anything, and then only
/// when the answer is unambiguous.
- (APBBindingKind)bindingFor:(APBAudioDevice *)device dongle:(APBJabraDongle **)bound {
    APBJabraProfile *profile = [APBJabraLink profileMatching:device.name];
    NSString *serial = [APBJabraLink serialFromAudioUID:device.uid];
    if (serial) {
        NSMutableArray<APBJabraDongle *> *matches = [NSMutableArray array];
        for (APBJabraDongle *dongle in _dongles.allValues) {
            if (dongle.serial && [APBJabraLink serial:dongle.serial matches:serial]) [matches addObject:dongle];
        }
        if (matches.count == 1) {
            if (bound) *bound = matches[0];
            return APBBindingOne;
        }
        if (matches.count > 1) return APBBindingUnidentified;
        return profile ? APBBindingUnidentified : APBBindingUnmonitored;
    }
    if (!profile) return APBBindingUnmonitored;
    NSMutableArray<APBJabraDongle *> *candidates = [NSMutableArray array];
    for (APBJabraDongle *dongle in _dongles.allValues) {
        if (dongle.profileID == profile.identifier) [candidates addObject:dongle];
    }
    if (candidates.count == 1) {
        if (bound) *bound = candidates[0];
        return APBBindingOne;
    }
    return APBBindingUnidentified;
}

#pragma mark - Attach and detach

- (void)attach:(IOHIDDeviceRef)device {
    if (!_isRunning || [_interfaceKeys objectForKey:(__bridge id)device]) return;
    NSString *name = (__bridge NSString *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    // Restrict monitoring to dongles. A directly connected Jabra headset or
    // speakerphone can expose the same management collection, and reporting
    // its empty pairing list as a down link would make a working device
    // unselectable.
    if (![name isKindOfClass:NSString.class] || ![APBJabraLink isDongleProduct:name]) return;
    APBJabraProfile *profile = [APBJabraLink profileMatching:name];
    IOHIDElementRef managementOutput = NULL;
    APBGNPLayout *management = [self.class managementLayout:device output:&managementOutput];
    // Among dongles, capability rather than a model allow-list decides.
    if (!management && !profile) return;
    if (IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone) != kIOReturnSuccess) return;

    APBJabraInterface *interface = [[APBJabraInterface alloc] initWithDevice:device profile:profile];
    interface.management = management;
    interface.managementOutput = managementOutput;

    NSString *serial = nil;
    NSString *key = [self.class identityOf:device serial:&serial];
    APBJabraDongle *dongle = _dongles[key];
    if (!dongle) {
        dongle = [[APBJabraDongle alloc] initWithKey:key serial:serial attachedAt:Uptime()];
        _dongles[key] = dongle;
    } else {
        dongle.generation += 1;
    }
    if (dongle.profileID == APBJabraProfileIDNone && profile) dongle.profileID = profile.identifier;

    void *context = (__bridge void *)self;
    BOOL needsReportCallback = management != nil;
    APBJabraSignal *signal = profile.signal;

    if (signal.kind == APBJabraSignalKindElement) {
        NSDictionary *match = @{
            @kIOHIDElementUsagePageKey: @(signal.page),
            @kIOHIDElementUsageKey: @(signal.usage),
        };
        NSArray *elements = CFBridgingRelease(IOHIDDeviceCopyMatchingElements(device, (__bridge CFDictionaryRef)match, kIOHIDOptionsTypeNone));
        IOHIDElementRef element = (__bridge IOHIDElementRef)elements.firstObject;
        if (element) {
            interface.legacyElement = element;
            IOHIDDeviceRegisterInputValueCallback(device, ValueCallback, context);
            NSNumber *linked = [self.class readLinkedDevice:device element:element linkedValue:signal.linkedValue];
            if (linked) [dongle.legacy seed:linked.boolValue];
        }
    }

    if (signal.kind == APBJabraSignalKindReport) {
        needsReportCallback = YES;
        NSNumber *linked = [self.class readReportLinkedDevice:device
                                                     reportID:signal.reportID
                                                    byteIndex:signal.byteIndex
                                                      bitMask:signal.bitMask
                                                   bufferSize:64];
        if (linked) [dongle.legacy seed:linked.boolValue];
    }

    if (needsReportCallback) {
        // A device supports only one input-report callback, so management
        // frames and legacy reports share it and are routed by report ID.
        NSNumber *maximum = (__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDMaxInputReportSizeKey));
        CFIndex reported = [maximum isKindOfClass:NSNumber.class] ? maximum.integerValue : 64;
        CFIndex size = MAX(reported, management.inputFrameLength + 1);
        interface.buffer = calloc((size_t)size, 1);
        interface.bufferSize = size;
        IOHIDDeviceRegisterInputReportCallback(device, interface.buffer, size, ReportCallback, context);
    }

    [dongle.interfaces setObject:interface forKey:(__bridge id)device];
    [_interfaceKeys setObject:key forKey:(__bridge id)device];
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    [self updatePollTimer];
    // Start the query before publishing anything, so the first state the
    // model ever sees for this attachment is `checking` rather than the
    // dongle's untrustworthy post-enumeration claim.
    [self requestQuery:dongle];
    [self refresh:dongle];
}

- (void)detach:(IOHIDDeviceRef)device {
    NSString *key = [_interfaceKeys objectForKey:(__bridge id)device];
    if (!key) return;
    [_interfaceKeys removeObjectForKey:(__bridge id)device];
    APBJabraDongle *dongle = _dongles[key];
    APBJabraInterface *interface = [dongle.interfaces objectForKey:(__bridge id)device];
    if (!dongle || !interface) return;
    [dongle.interfaces removeObjectForKey:(__bridge id)device];
    // Invalidate anything still referring to this dongle's membership.
    dongle.generation += 1;
    if (dongle.query.timeout) dispatch_block_cancel(dongle.query.timeout);
    dongle.query = nil;
    [self tearDown:interface];
    if (dongle.interfaces.count == 0) {
        if (dongle.pendingDown) dispatch_block_cancel(dongle.pendingDown);
        dongle.pendingDown = nil;
        BOOL wasKnown = dongle.resolved != nil;
        [_dongles removeObjectForKey:key];
        [self updatePollTimer];
        if (wasKnown) [self notifyLinkChange];
        return;
    }
    [self updatePollTimer];
    [self refresh:dongle];
}

- (void)tearDown:(APBJabraInterface *)interface {
    if (interface.legacyElement) {
        IOHIDDeviceRegisterInputValueCallback(interface.device, NULL, NULL);
    }
    if (interface.buffer) {
        IOHIDDeviceRegisterInputReportCallback(interface.device, interface.buffer, interface.bufferSize, NULL, NULL);
    }
    IOHIDDeviceUnscheduleFromRunLoop(interface.device, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    IOHIDDeviceClose(interface.device, kIOHIDOptionsTypeNone);
}

#pragma mark - Resolution

+ (APBLinkState)stateOf:(APBJabraDongle *)dongle {
    // A query is only pending before the first answer while the legacy bit
    // is still untrustworthy, so the model is told to wait rather than act.
    if (dongle.awaitingFirstAnswer && dongle.query) return APBLinkStateChecking;
    if (!dongle.resolved) return APBLinkStateUnknown;
    return dongle.resolved.boolValue ? APBLinkStateUp : APBLinkStateDown;
}

/// Recomputes the dongle's reported value. Complete GNP evidence wins over
/// the legacy bit; the two are never averaged or aggregated as peers.
- (void)refresh:(APBJabraDongle *)dongle {
    dongle.resolved = [APBJabraGNP resolveVendor:dongle.vendor legacy:dongle.legacy.effective];
    APBLinkState state = [self.class stateOf:dongle];
    if (state == dongle.reported) return;
    dongle.reported = state;
    [self notifyLinkChange];
}

- (void)notifyLinkChange {
    if (!_isRunning) return;
    if (_onLinkChange) _onLinkChange();
}

- (void)observeLegacy:(APBJabraDongle *)dongle linked:(BOOL)linked {
    NSNumber *previous = dongle.legacy.observed;
    // A change in the raw bit means something really happened, which is the
    // cheapest moment to confirm it authoritatively.
    BOOL changed = previous == nil || previous.boolValue != linked;
    [self applyLegacy:dongle linked:linked];
    if (changed) [self requestQuery:dongle];
}

- (void)applyLegacy:(APBJabraDongle *)dongle linked:(BOOL)linked {
    // A positive claim right after enumeration is the dongle's known lie. A
    // negative claim is never spurious, so it is always accepted.
    if (linked && Uptime() - dongle.attachedAt < EnumerationSuppression) return;
    switch ([dongle.legacy observe:linked]) {
        case APBLinkTransitionUnchanged:
            return;
        case APBLinkTransitionChanged:
            if (dongle.pendingDown) dispatch_block_cancel(dongle.pendingDown);
            dongle.pendingDown = nil;
            [self refresh:dongle];
            return;
        case APBLinkTransitionCancelDown:
            if (dongle.pendingDown) dispatch_block_cancel(dongle.pendingDown);
            dongle.pendingDown = nil;
            return;
        case APBLinkTransitionScheduleDown:
            [self scheduleLegacyDown:dongle];
            return;
    }
}

- (void)scheduleLegacyDown:(APBJabraDongle *)dongle {
    if (dongle.pendingDown) dispatch_block_cancel(dongle.pendingDown);
    NSString *key = dongle.key;
    NSInteger generation = dongle.generation;
    __weak typeof(self) weakSelf = self;
    dispatch_block_t work = dispatch_block_create(0, ^{
        APBJabraHIDMonitor *monitor = weakSelf;
        APBJabraDongle *current = monitor ? monitor->_dongles[key] : nil;
        if (!monitor || !monitor.isRunning || !current || current.generation != generation) return;
        current.pendingDown = nil;
        if ([current.legacy commitDown]) [monitor refresh:current];
    });
    dongle.pendingDown = work;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DownDebounce * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), work);
}

#pragma mark - GNP transactions

- (uint8_t)nextSequence {
    _sequence += 1;
    return _sequence;
}

/// Starts a walk unless one is already running for this dongle. Queries are
/// serialized per dongle so replies can never be attributed to the wrong
/// request.
- (void)requestQuery:(APBJabraDongle *)dongle {
    APBJabraInterface *interface = dongle.managementInterface;
    if (!_isRunning || dongle.query || !interface) return;
    APBJabraQuery *query = [[APBJabraQuery alloc] initWithGeneration:dongle.generation interface:interface];
    dongle.query = query;
    dongle.lastQueryAt = Uptime();
    [self advance:dongle query:query step:[query.walk start]];
}

- (void)advance:(APBJabraDongle *)dongle query:(APBJabraQuery *)query step:(APBGNPStep *)step {
    if (step.isFinished) {
        [self finish:dongle query:query evidence:step.evidence];
    } else {
        query.cursor = step.cursor;
        query.bluetoothType = step.bluetoothType;
        query.attempt = 0;
        [self transmit:dongle query:query];
    }
}

- (void)transmit:(APBJabraDongle *)dongle query:(APBJabraQuery *)query {
    query.attempt += 1;
    APBGNPLayout *layout = query.interface.management;
    IOHIDElementRef output = query.interface.managementOutput;
    NSData *body = layout && output
        ? [APBJabraGNP encodeQueryWithSequence:[self nextSequence]
                                         group:APBGNPPairingGroup
                                            op:APBGNPRecordOp
                                     arguments:[APBJabraGNP recordArgumentsWithCursor:query.cursor
                                                                        bluetoothType:query.bluetoothType]
                                   frameLength:layout.outputFrameLength]
        : nil;
    IOHIDValueRef value = body
        ? IOHIDValueCreateWithBytes(kCFAllocatorDefault, output, 0, body.bytes, (CFIndex)body.length)
        : NULL;
    if (!value) {
        [self finish:dongle query:query evidence:APBGNPEvidenceInconclusive];
        return;
    }
    // Record the awaited sequence and arm the timeout before writing, so a
    // fast reply cannot arrive against unprepared state.
    query.sequence = ((const uint8_t *)body.bytes)[2];
    [query.interface.reassembler reset];
    [self armTimeout:dongle query:query];
    IOReturn status = IOHIDDeviceSetValue(query.interface.device, output, value);
    CFRelease(value);
    if (status != kIOReturnSuccess) {
        [self finish:dongle query:query evidence:APBGNPEvidenceInconclusive];
    }
}

- (void)armTimeout:(APBJabraDongle *)dongle query:(APBJabraQuery *)query {
    if (query.timeout) dispatch_block_cancel(query.timeout);
    NSString *key = dongle.key;
    __weak typeof(self) weakSelf = self;
    __weak APBJabraQuery *weakQuery = query;
    dispatch_block_t work = dispatch_block_create(0, ^{
        APBJabraHIDMonitor *monitor = weakSelf;
        APBJabraQuery *pending = weakQuery;
        APBJabraDongle *current = monitor ? monitor->_dongles[key] : nil;
        if (!monitor || !monitor.isRunning || !current || !pending
            || current.generation != pending.generation || current.query != pending) {
            return;
        }
        pending.timeout = nil;
        // A request the dongle dropped while still booting is not an answer,
        // so re-send it before concluding anything.
        if (pending.attempt < MaximumAttempts) {
            [monitor transmit:current query:pending];
            return;
        }
        APBGNPStep *step = [pending.walk fail];
        if (step.isFinished) [monitor finish:current query:pending evidence:step.evidence];
    });
    query.timeout = work;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(QueryTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), work);
}

- (void)finish:(APBJabraDongle *)dongle query:(APBJabraQuery *)query evidence:(APBGNPEvidence)evidence {
    if (dongle.query != query) return;
    if (query.timeout) dispatch_block_cancel(query.timeout);
    query.timeout = nil;
    dongle.query = nil;
    dongle.awaitingFirstAnswer = NO;
    // Incomplete evidence must not linger as authoritative, otherwise a
    // single failed cycle would freeze a stale verdict in place.
    dongle.vendor = evidence == APBGNPEvidenceInconclusive ? APBGNPEvidenceNone : evidence;
    [self refresh:dongle];
    if (evidence == APBGNPEvidenceConnected) {
        [self requestBattery:dongle];
    } else if (evidence == APBGNPEvidenceDisconnected) {
        // The next headset to connect may not be this one.
        dongle.lastBatteryQueryAt = -DBL_MAX;
        [self updateBattery:dongle level:nil];
    }
    if (dongle.requeryWhenIdle) {
        dongle.requeryWhenIdle = NO;
        [self requestQuery:dongle];
    }
}

/// Asks the headset for its battery without waiting: the answer is picked up
/// like an unasked update, and a lost one is retried a minute later.
- (void)requestBattery:(APBJabraDongle *)dongle {
    NSTimeInterval now = Uptime();
    APBJabraInterface *interface = dongle.managementInterface;
    APBGNPLayout *layout = interface.management;
    IOHIDElementRef output = interface.managementOutput;
    if (now - dongle.lastBatteryQueryAt < BatteryRefreshInterval || !layout || !output) return;
    NSData *body = [APBJabraGNP encodeQueryWithDestination:APBGNPHeadsetAddress
                                                  sequence:[self nextSequence]
                                                     group:APBGNPStatusGroup
                                                        op:APBGNPBatteryOp
                                                 arguments:[NSData data]
                                               frameLength:layout.outputFrameLength];
    if (!body) return;
    IOHIDValueRef value = IOHIDValueCreateWithBytes(kCFAllocatorDefault, output, 0, body.bytes, (CFIndex)body.length);
    if (!value) return;
    dongle.lastBatteryQueryAt = now;
    IOHIDDeviceSetValue(interface.device, output, value);
    CFRelease(value);
}

- (void)updateBattery:(APBJabraDongle *)dongle level:(NSNumber *)level {
    if (dongle.battery == level || [dongle.battery isEqual:level]) return;
    dongle.battery = level;
    if (_isRunning && _onBatteryChange) _onBatteryChange();
}

/// The dongle announced that a remembered device connected or disconnected.
/// Ask it what the pairing database now says, since the announcement is a
/// trigger rather than an answer.
- (void)noteAnnouncedChange:(APBJabraDongle *)dongle {
    if (dongle.query) {
        dongle.requeryWhenIdle = YES;
        return;
    }
    [self requestQuery:dongle];
}

- (void)handleReport:(APBJabraDongle *)dongle
           interface:(APBJabraInterface *)interface
            reportID:(uint8_t)reportID
               bytes:(NSData *)bytes {
    APBGNPLayout *layout = interface.management;
    if (layout && reportID == layout.inputReportID) {
        // IOKit prefixes the buffer with the physical report ID; the
        // canonical GNP body starts after it.
        NSData *chunk = bytes;
        if (chunk.length > 0 && ((const uint8_t *)chunk.bytes)[0] == reportID) {
            chunk = [chunk subdataWithRange:NSMakeRange(1, chunk.length - 1)];
        }
        NSData *body = [interface.reassembler feed:chunk];
        APBGNPMessage *message = body ? [APBJabraGNP decode:body] : nil;
        if (!message) return;
        if ([APBJabraGNP isConnectionEvent:message]) {
            [self noteAnnouncedChange:dongle];
            return;
        }
        NSNumber *level = [APBJabraGNP batteryLevel:message];
        if (level) {
            [self updateBattery:dongle level:level];
            return;
        }
        APBJabraQuery *query = dongle.query;
        if (!query || query.generation != dongle.generation
            || ![APBJabraGNP isReply:message sequence:query.sequence group:APBGNPPairingGroup op:APBGNPRecordOp]) {
            return;
        }
        if (query.timeout) dispatch_block_cancel(query.timeout);
        query.timeout = nil;
        [self advance:dongle query:query step:[query.walk acceptRecord:message.arguments]];
        return;
    }
    APBJabraSignal *signal = interface.profile.signal;
    if (signal.kind != APBJabraSignalKindReport) return;
    NSNumber *linked = [APBJabraLink decodeReportID:reportID
                                         expectedID:signal.reportID
                                              bytes:bytes
                                          byteIndex:signal.byteIndex
                                            bitMask:signal.bitMask];
    if (linked) [self observeLegacy:dongle linked:linked.boolValue];
}

#pragma mark - Polling

- (void)updatePollTimer {
    BOOL needsPolling = NO;
    for (APBJabraDongle *dongle in _dongles.allValues) {
        if (dongle.managementInterface) needsPolling = YES;
        for (APBJabraInterface *interface in dongle.interfaces.objectEnumerator) {
            if (interface.profile.signal.kind == APBJabraSignalKindReport) needsPolling = YES;
        }
    }
    if (!needsPolling) {
        [_pollTimer invalidate];
        _pollTimer = nil;
        return;
    }
    if (_pollTimer) return;
    __weak typeof(self) weakSelf = self;
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:PollInterval repeats:YES block:^(NSTimer *timer) {
        [weakSelf poll];
    }];
}

- (void)poll {
    if (!_isRunning) return;
    NSTimeInterval uptime = Uptime();
    for (APBJabraDongle *dongle in _dongles.allValues) {
        for (APBJabraInterface *interface in [dongle.interfaces.objectEnumerator allObjects]) {
            APBJabraSignal *signal = interface.profile.signal;
            if (signal.kind != APBJabraSignalKindReport) continue;
            NSNumber *linked = [self.class readReportLinkedDevice:interface.device
                                                         reportID:signal.reportID
                                                        byteIndex:signal.byteIndex
                                                          bitMask:signal.bitMask
                                                       bufferSize:interface.bufferSize];
            if (linked) [self observeLegacy:dongle linked:linked.boolValue];
        }
        if (uptime - dongle.lastQueryAt >= VendorRefreshInterval) [self requestQuery:dongle];
    }
}

#pragma mark - Device inspection

+ (NSString *)identityOf:(IOHIDDeviceRef)device serial:(NSString **)serial {
    NSString *number = (__bridge NSString *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDSerialNumberKey));
    if ([number isKindOfClass:NSString.class] && number.length > 0) {
        *serial = number;
        return [@"serial:" stringByAppendingString:number.lowercaseString];
    }
    // Without a serial, fall back to the USB position. Two dongles still stay
    // distinct, they just cannot be matched by UID.
    NSNumber *productID = (__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey));
    NSNumber *location = (__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDLocationIDKey));
    *serial = nil;
    return [NSString stringWithFormat:@"product:%ld/location:%ld",
            [productID isKindOfClass:NSNumber.class] ? productID.longValue : -1L,
            [location isKindOfClass:NSNumber.class] ? location.longValue : -1L];
}

+ (APBGNPLayout *)managementLayout:(IOHIDDeviceRef)device output:(IOHIDElementRef *)outputElement {
    NSDictionary *match = @{
        @kIOHIDElementUsagePageKey: @(APBGNPUsagePage),
        @kIOHIDElementUsageKey: @(APBGNPUsage),
    };
    NSArray *elements = CFBridgingRelease(IOHIDDeviceCopyMatchingElements(device, (__bridge CFDictionaryRef)match, kIOHIDOptionsTypeNone));
    if (!elements) return nil;

    NSMutableArray<APBGNPElement *> *descriptors = [NSMutableArray array];
    NSMutableArray *outputs = [NSMutableArray array];
    for (id object in elements) {
        IOHIDElementRef element = (__bridge IOHIDElementRef)object;
        // IOKit reports an element's full width in reportSize, while
        // reportCount is the item count, so the two must not be multiplied.
        NSInteger bits = (NSInteger)IOHIDElementGetReportSize(element);
        uint8_t reportID = (uint8_t)IOHIDElementGetReportID(element);
        switch (IOHIDElementGetType(element)) {
            case kIOHIDElementTypeOutput:
                [descriptors addObject:[APBGNPElement elementWithDirection:APBGNPDirectionOutput reportID:reportID bits:bits]];
                [outputs addObject:object];
                break;
            case kIOHIDElementTypeFeature:
            case kIOHIDElementTypeCollection:
                break;
            default:
                [descriptors addObject:[APBGNPElement elementWithDirection:APBGNPDirectionInput reportID:reportID bits:bits]];
                break;
        }
    }
    APBGNPLayout *layout = [APBJabraGNP selectLayout:descriptors];
    if (!layout) return nil;
    for (id object in outputs) {
        IOHIDElementRef element = (__bridge IOHIDElementRef)object;
        if ((uint8_t)IOHIDElementGetReportID(element) == layout.outputReportID
            && (NSInteger)IOHIDElementGetReportSize(element) / 8 == layout.outputFrameLength) {
            *outputElement = element;
            return layout;
        }
    }
    return nil;
}

+ (NSNumber *)readLinkedDevice:(IOHIDDeviceRef)device element:(IOHIDElementRef)element linkedValue:(NSInteger)linkedValue {
    IOHIDValueRef value = NULL;
    if (IOHIDDeviceGetValue(device, element, &value) != kIOReturnSuccess || !value) return nil;
    return [APBJabraLink snapshotValue:IOHIDValueGetIntegerValue(value)
                             timestamp:IOHIDValueGetTimeStamp(value)
                           linkedValue:linkedValue];
}

+ (NSNumber *)readReportLinkedDevice:(IOHIDDeviceRef)device
                            reportID:(NSInteger)reportID
                           byteIndex:(NSInteger)byteIndex
                             bitMask:(uint8_t)bitMask
                          bufferSize:(CFIndex)bufferSize {
    CFIndex length = MAX(bufferSize, (CFIndex)byteIndex + 1);
    NSMutableData *bytes = [NSMutableData dataWithLength:(NSUInteger)length];
    IOReturn status = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, reportID, bytes.mutableBytes, &length);
    if (status != kIOReturnSuccess || length <= byteIndex) return nil;
    // IOHIDDeviceGetReport already selects reportID. Upstream Link 390
    // hardware research indexes the returned payload directly.
    return @((((const uint8_t *)bytes.bytes)[byteIndex] & bitMask) != 0);
}

#pragma mark - Callback plumbing

/// Resolves a device back to the dongle that currently owns it, so work
/// arriving after a detach or replug is dropped.
- (APBJabraDongle *)dongleFor:(IOHIDDeviceRef)device interface:(APBJabraInterface **)interface {
    NSString *key = [_interfaceKeys objectForKey:(__bridge id)device];
    APBJabraDongle *dongle = key ? _dongles[key] : nil;
    APBJabraInterface *found = [dongle.interfaces objectForKey:(__bridge id)device];
    if (!found) return nil;
    *interface = found;
    return dongle;
}

static APBJabraHIDMonitor *Monitor(void *context) {
    APBJabraHIDMonitor *monitor = (__bridge APBJabraHIDMonitor *)context;
    return monitor.isRunning ? monitor : nil;
}

static void MatchCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    [Monitor(context) attach:device];
}

static void RemovalCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    [Monitor(context) detach:device];
}

static void ValueCallback(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
    APBJabraHIDMonitor *monitor = Monitor(context);
    if (!monitor) return;
    IOHIDElementRef element = IOHIDValueGetElement(value);
    IOHIDDeviceRef device = IOHIDElementGetDevice(element);
    APBJabraInterface *interface = nil;
    APBJabraDongle *dongle = [monitor dongleFor:device interface:&interface];
    APBJabraSignal *signal = interface.profile.signal;
    if (!dongle || !interface.legacyElement
        || IOHIDElementGetCookie(interface.legacyElement) != IOHIDElementGetCookie(element)
        || signal.kind != APBJabraSignalKindElement) {
        return;
    }
    [monitor observeLegacy:dongle
                    linked:[APBJabraLink decodeElementValue:IOHIDValueGetIntegerValue(value)
                                                linkedValue:signal.linkedValue]];
}

static void ReportCallback(void *context, IOReturn result, void *sender, IOHIDReportType type,
                           uint32_t reportID, uint8_t *report, CFIndex length) {
    if (!sender || length <= 0) return;
    APBJabraHIDMonitor *monitor = Monitor(context);
    if (!monitor) return;
    // GNP needs the whole frame, so the buffer is never truncated here.
    NSData *bytes = [NSData dataWithBytes:report length:(NSUInteger)length];
    APBJabraInterface *interface = nil;
    APBJabraDongle *dongle = [monitor dongleFor:(IOHIDDeviceRef)sender interface:&interface];
    if (!dongle) return;
    [monitor handleReport:dongle interface:interface reportID:(uint8_t)reportID bytes:bytes];
}

@end
