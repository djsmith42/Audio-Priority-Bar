#import "APBJabraHIDMonitor.h"
#import <IOKit/hid/IOHIDLib.h>
#import "APBJabra.h"

static const NSTimeInterval DownDebounce = 3;
static const NSTimeInterval PollInterval = 2;
/// The dongle's false "linked" claim lands about 1.8s after enumeration, so
/// positive legacy claims inside this window are not evidence.
static const NSTimeInterval EnumerationSuppression = 3;
/// A completed walk costs about 0.4s when nothing is connected, so the
/// safety-net refresh is slow. Real transitions do not wait for it: the dongle
/// announces them and that triggers a walk immediately. This only covers an
/// announcement being missed entirely.
static const NSTimeInterval VendorRefreshInterval = 10;
/// A settled dongle answers in about 4ms, but for roughly 265ms after
/// enumeration it silently drops requests instead of queueing them. So the
/// per-request wait is short and a dropped request is simply re-sent, keeping
/// the overall budget for a first answer near 1.5s.
static const NSTimeInterval QueryTimeout = 0.5;
static const NSInteger MaximumAttempts = 3;

static NSTimeInterval Uptime(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

static NSNumber *DeviceKey(IOHIDDeviceRef device) {
    return @((uintptr_t)device);
}

#pragma mark - Interfaces and dongles

/// One HID interface. A dongle may expose several.
@interface APBJabraInterface : NSObject
@property (nonatomic, readonly) IOHIDDeviceRef device;
@property (nonatomic, readonly, nullable) APBJabraProfile *profile;
@property (nonatomic) IOHIDElementRef legacyElement;
@property (nonatomic) BOOL hasManagement;
@property (nonatomic) APBGNPLayout management;
@property (nonatomic) IOHIDElementRef managementOutput;
@property (nonatomic, readonly) APBGNPReassembler *reassembler;
@property (nonatomic) uint8_t *buffer;
@property (nonatomic) CFIndex bufferSize;
@end

@implementation APBJabraInterface

- (instancetype)initWithDevice:(IOHIDDeviceRef)device profile:(APBJabraProfile *)profile {
    self = [super init];
    if (self) {
        _device = (IOHIDDeviceRef)CFRetain(device);
        _profile = profile;
        _reassembler = [[APBGNPReassembler alloc] init];
    }
    return self;
}

- (void)setLegacyElement:(IOHIDElementRef)element {
    if (element) CFRetain(element);
    if (_legacyElement) CFRelease(_legacyElement);
    _legacyElement = element;
}

- (void)setManagementOutput:(IOHIDElementRef)element {
    if (element) CFRetain(element);
    if (_managementOutput) CFRelease(_managementOutput);
    _managementOutput = element;
}

- (void)dealloc {
    free(_buffer);
    if (_legacyElement) CFRelease(_legacyElement);
    if (_managementOutput) CFRelease(_managementOutput);
    CFRelease(_device);
}

@end

/// One in-flight pairing-database walk.
@interface APBJabraQuery : NSObject
@property (nonatomic, readonly) APBGNPPairingWalk *walk;
@property (nonatomic) uint8_t sequence;
@property (nonatomic, nullable) dispatch_block_t timeout;
/// Request in flight, kept so a dropped one can be re-sent.
@property (nonatomic, copy) NSData *cursor;
@property (nonatomic) uint8_t bluetoothType;
@property (nonatomic) NSInteger attempt;
@property (nonatomic, readonly) NSInteger generation;
@property (nonatomic, readonly) APBJabraInterface *interface;
@end

@implementation APBJabraQuery

- (instancetype)initWithGeneration:(NSInteger)generation interface:(APBJabraInterface *)interface {
    self = [super init];
    if (self) {
        _walk = [[APBGNPPairingWalk alloc] init];
        _generation = generation;
        _interface = interface;
        _cursor = [NSData data];
    }
    return self;
}

- (void)cancelTimeout {
    if (_timeout) dispatch_block_cancel(_timeout);
    _timeout = nil;
}

@end

/// One physical dongle, identified by serial so two dongles of the same model
/// never contaminate each other's state.
@interface APBJabraDongle : NSObject
@property (nonatomic, readonly, copy) NSString *key;
@property (nonatomic, readonly, copy, nullable) NSString *serial;
@property (nonatomic) APBJabraProfileID profileID;
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, APBJabraInterface *> *interfaces;
/// Bumped whenever membership changes, so asynchronous work that completes
/// late cannot update a replacement dongle.
@property (nonatomic) NSInteger generation;
@property (nonatomic) NSTimeInterval attachedAt;
@property (nonatomic, readonly) APBDebouncedLinkState *legacy;
@property (nonatomic, nullable) dispatch_block_t pendingDown;
@property (nonatomic) APBGNPEvidence vendor;
@property (nonatomic) APBTriState resolved;
/// Last state published to the model. Tracked as a link state rather than a
/// boolean so leaving `Checking` still notifies even when the underlying
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
@end

@implementation APBJabraDongle

- (instancetype)initWithKey:(NSString *)key serial:(NSString *)serial attachedAt:(NSTimeInterval)attachedAt {
    self = [super init];
    if (self) {
        _key = [key copy];
        _serial = [serial copy];
        _interfaces = [NSMutableDictionary dictionary];
        _attachedAt = attachedAt;
        _legacy = [[APBDebouncedLinkState alloc] init];
        _lastQueryAt = -DBL_MAX;
        _awaitingFirstAnswer = YES;
    }
    return self;
}

- (APBJabraInterface *)managementInterface {
    for (APBJabraInterface *interface in _interfaces.allValues) {
        if (interface.hasManagement) return interface;
    }
    return nil;
}

- (void)cancelPendingDown {
    if (_pendingDown) dispatch_block_cancel(_pendingDown);
    _pendingDown = nil;
}

@end

#pragma mark - Monitor

/// How an audio device binds to the dongles we monitor.
typedef NS_ENUM(NSInteger, APBJabraBindingKind) {
    APBJabraBindingUnmonitored,
    APBJabraBindingOne,
    /// Known to be a Jabra we would monitor, but not bindable to exactly one
    /// dongle, so it must fail open rather than borrow another's state.
    APBJabraBindingUnidentified,
};

static void MatchCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device);
static void RemovalCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device);
static void ValueCallback(void *context, IOReturn result, void *sender, IOHIDValueRef value);
static void ReportCallback(void *context, IOReturn result, void *sender, IOHIDReportType type,
                           uint32_t reportID, uint8_t *report, CFIndex length);

@implementation APBJabraHIDMonitor {
    IOHIDManagerRef _manager;
    NSTimer *_pollTimer;
    NSMutableDictionary<NSString *, APBJabraDongle *> *_dongles;
    NSMutableDictionary<NSNumber *, NSString *> *_interfaceKeys;
    uint8_t _sequence;
    BOOL _isRunning;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _dongles = [NSMutableDictionary dictionary];
        _interfaceKeys = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

#pragma mark Lifecycle

- (void)start {
    if (_manager) return;
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, 0);
    _manager = manager;
    _isRunning = YES;
    IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)@{ @kIOHIDVendorIDKey: @(APBJabraLink.vendorID) });
    void *context = (__bridge void *)self;
    IOHIDManagerRegisterDeviceMatchingCallback(manager, MatchCallback, context);
    IOHIDManagerRegisterDeviceRemovalCallback(manager, RemovalCallback, context);
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    if (IOHIDManagerOpen(manager, 0) != kIOReturnSuccess) {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        _isRunning = NO;
        CFRelease(manager);
        _manager = NULL;
        return;
    }
    NSSet *matched = (__bridge_transfer NSSet *)IOHIDManagerCopyDevices(manager);
    for (id device in matched) [self attach:(__bridge IOHIDDeviceRef)device];
}

- (void)stop {
    if (!_manager) return;
    _isRunning = NO;
    [_pollTimer invalidate];
    _pollTimer = nil;
    for (APBJabraDongle *dongle in _dongles.allValues) {
        dongle.generation += 1;
        [dongle cancelPendingDown];
        [dongle.query cancelTimeout];
        dongle.query = nil;
        for (APBJabraInterface *interface in dongle.interfaces.allValues) [self tearDown:interface];
    }
    [_dongles removeAllObjects];
    [_interfaceKeys removeAllObjects];
    IOHIDManagerRegisterDeviceMatchingCallback(_manager, NULL, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(_manager, NULL, NULL);
    IOHIDManagerUnscheduleFromRunLoop(_manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    IOHIDManagerClose(_manager, 0);
    CFRelease(_manager);
    _manager = NULL;
}

#pragma mark Queries from the model

- (APBLinkState)linkStateForDevice:(APBAudioDevice *)device {
    APBJabraDongle *dongle = nil;
    switch ([self bindingForDevice:device dongle:&dongle]) {
        case APBJabraBindingUnmonitored: return APBLinkStateUnknown;
        case APBJabraBindingUnidentified: return APBLinkStateMonitoringUnavailable;
        case APBJabraBindingOne: return [self stateOfDongle:dongle];
    }
}

- (BOOL)isUsable:(APBAudioDevice *)device {
    BOOL isSupported = [self bindingForDevice:device dongle:NULL] != APBJabraBindingUnmonitored;
    return [APBJabraLink allowsSelectionWhenSupported:isSupported state:[self linkStateForDevice:device]];
}

- (APBLinkState)monitoredStateForDevice:(APBAudioDevice *)device {
    if ([self bindingForDevice:device dongle:NULL] == APBJabraBindingUnmonitored) return APBLinkStateNone;
    return [self linkStateForDevice:device];
}

/// Binds an audio device to at most one physical dongle. The USB serial in the
/// CoreAudio UID is preferred because it is exact; the product name is only
/// consulted when the serial cannot identify anything, and then only when the
/// answer is unambiguous.
- (APBJabraBindingKind)bindingForDevice:(APBAudioDevice *)device dongle:(APBJabraDongle **)bound {
    APBJabraProfile *profile = [APBJabraLink profileMatching:device.name];
    NSString *serial = [APBJabraLink serialFromAudioUID:device.uid];
    NSMutableArray<APBJabraDongle *> *matches = [NSMutableArray array];
    if (serial) {
        for (APBJabraDongle *dongle in _dongles.allValues) {
            if (dongle.serial && [APBJabraLink serial:dongle.serial matches:serial]) [matches addObject:dongle];
        }
        if (matches.count == 1) {
            if (bound) *bound = matches[0];
            return APBJabraBindingOne;
        }
        if (matches.count > 1) return APBJabraBindingUnidentified;
        return profile ? APBJabraBindingUnidentified : APBJabraBindingUnmonitored;
    }
    if (!profile) return APBJabraBindingUnmonitored;
    for (APBJabraDongle *dongle in _dongles.allValues) {
        if (dongle.profileID == profile.profileID) [matches addObject:dongle];
    }
    if (matches.count == 1) {
        if (bound) *bound = matches[0];
        return APBJabraBindingOne;
    }
    return APBJabraBindingUnidentified;
}

#pragma mark Attach and detach

- (void)attach:(IOHIDDeviceRef)device {
    if (!_isRunning || _interfaceKeys[DeviceKey(device)]) return;
    NSString *name = (__bridge NSString *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    // Restrict monitoring to dongles. A directly connected Jabra headset or
    // speakerphone can expose the same management collection, and reporting
    // its empty pairing list as a down link would make a working device
    // unselectable.
    if (![name isKindOfClass:NSString.class] || ![APBJabraLink isDongleProduct:name]) return;
    APBJabraProfile *profile = [APBJabraLink profileMatching:name];
    APBGNPLayout layout;
    IOHIDElementRef managementOutput = NULL;
    BOOL hasManagement = [APBJabraHIDMonitor managementLayout:device layout:&layout output:&managementOutput];
    // Among dongles, capability rather than a model allow-list decides.
    if (!hasManagement && !profile) return;
    if (IOHIDDeviceOpen(device, 0) != kIOReturnSuccess) return;

    APBJabraInterface *interface = [[APBJabraInterface alloc] initWithDevice:device profile:profile];
    interface.hasManagement = hasManagement;
    if (hasManagement) {
        interface.management = layout;
        interface.managementOutput = managementOutput;
    }

    NSString *serial = nil;
    NSString *key = [APBJabraHIDMonitor identityOfDevice:device serial:&serial];
    APBJabraDongle *dongle = _dongles[key];
    if (dongle) {
        dongle.generation += 1;
    } else {
        dongle = [[APBJabraDongle alloc] initWithKey:key serial:serial attachedAt:Uptime()];
        _dongles[key] = dongle;
    }
    if (dongle.profileID == APBJabraProfileIDNone) dongle.profileID = profile.profileID;

    void *context = (__bridge void *)self;
    BOOL needsReportCallback = hasManagement;

    if (profile.signalKind == APBJabraSignalKindElement) {
        NSDictionary *match = @{
            @kIOHIDElementUsagePageKey: @(profile.page),
            @kIOHIDElementUsageKey: @(profile.usage),
        };
        NSArray *elements = (__bridge_transfer NSArray *)IOHIDDeviceCopyMatchingElements(device, (__bridge CFDictionaryRef)match, 0);
        IOHIDElementRef element = (__bridge IOHIDElementRef)elements.firstObject;
        if (element) {
            interface.legacyElement = element;
            IOHIDDeviceRegisterInputValueCallback(device, ValueCallback, context);
            APBTriState linked = [APBJabraHIDMonitor readLinkedDevice:device element:element linkedValue:profile.linkedValue];
            if (linked != APBTriStateUnknown) [dongle.legacy seed:linked == APBTriStateYes];
        }
    }

    if (profile.signalKind == APBJabraSignalKindReport) {
        needsReportCallback = YES;
        APBTriState linked = [APBJabraHIDMonitor readReportLinkedDevice:device profile:profile bufferSize:64];
        if (linked != APBTriStateUnknown) [dongle.legacy seed:linked == APBTriStateYes];
    }

    if (needsReportCallback) {
        // A device supports only one input-report callback, so management
        // frames and legacy reports share it and are routed by report ID.
        NSNumber *maximum = (__bridge NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDMaxInputReportSizeKey));
        CFIndex size = MAX([maximum isKindOfClass:NSNumber.class] ? maximum.integerValue : 64,
                           (hasManagement ? layout.inputFrameLength : 0) + 1);
        interface.buffer = calloc((size_t)size, 1);
        interface.bufferSize = size;
        IOHIDDeviceRegisterInputReportCallback(device, interface.buffer, size, ReportCallback, context);
    }

    dongle.interfaces[DeviceKey(device)] = interface;
    _interfaceKeys[DeviceKey(device)] = key;
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    [self updatePollTimer];
    // Start the query before publishing anything, so the first state the model
    // ever sees for this attachment is `Checking` rather than the dongle's
    // untrustworthy post-enumeration claim.
    [self requestQuery:dongle];
    [self refresh:dongle];
}

- (void)detach:(IOHIDDeviceRef)device {
    NSNumber *deviceKey = DeviceKey(device);
    NSString *key = _interfaceKeys[deviceKey];
    APBJabraDongle *dongle = key ? _dongles[key] : nil;
    APBJabraInterface *interface = dongle.interfaces[deviceKey];
    if (!interface) return;
    [_interfaceKeys removeObjectForKey:deviceKey];
    [dongle.interfaces removeObjectForKey:deviceKey];
    // Invalidate anything still referring to this dongle's membership.
    dongle.generation += 1;
    [dongle.query cancelTimeout];
    dongle.query = nil;
    [self tearDown:interface];
    if (dongle.interfaces.count == 0) {
        [dongle cancelPendingDown];
        BOOL wasKnown = dongle.resolved != APBTriStateUnknown;
        [_dongles removeObjectForKey:key];
        [self updatePollTimer];
        if (wasKnown) [self notifyLinkChange];
        return;
    }
    [self updatePollTimer];
    [self refresh:dongle];
}

- (void)tearDown:(APBJabraInterface *)interface {
    if (interface.legacyElement) IOHIDDeviceRegisterInputValueCallback(interface.device, NULL, NULL);
    if (interface.buffer) {
        IOHIDDeviceRegisterInputReportCallback(interface.device, interface.buffer, interface.bufferSize, NULL, NULL);
    }
    IOHIDDeviceUnscheduleFromRunLoop(interface.device, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    IOHIDDeviceClose(interface.device, 0);
}

#pragma mark Resolution

- (APBLinkState)stateOfDongle:(APBJabraDongle *)dongle {
    // A query is only pending before the first answer while the legacy bit is
    // still untrustworthy, so the model is told to wait rather than act.
    if (dongle.awaitingFirstAnswer && dongle.query) return APBLinkStateChecking;
    switch (dongle.resolved) {
        case APBTriStateUnknown: return APBLinkStateUnknown;
        case APBTriStateYes: return APBLinkStateUp;
        case APBTriStateNo: return APBLinkStateDown;
    }
}

/// Recomputes the dongle's reported value. Complete GNP evidence wins over the
/// legacy bit; the two are never averaged or aggregated as peers.
- (void)refresh:(APBJabraDongle *)dongle {
    dongle.resolved = [APBJabraGNP resolveVendor:dongle.vendor legacy:dongle.legacy.effective];
    APBLinkState state = [self stateOfDongle:dongle];
    if (state == dongle.reported) return;
    dongle.reported = state;
    [self notifyLinkChange];
}

- (void)notifyLinkChange {
    if (_isRunning && _onLinkChange) _onLinkChange();
}

- (void)observeLegacy:(APBJabraDongle *)dongle linked:(BOOL)linked {
    APBTriState previous = dongle.legacy.observed;
    // A change in the raw bit means something really happened, which is the
    // cheapest moment to confirm it authoritatively.
    BOOL changed = previous != APBTriStateFromBool(linked);
    // A positive claim right after enumeration is the dongle's known lie. A
    // negative claim is never spurious, so it is always accepted.
    if (!(linked && Uptime() - dongle.attachedAt < EnumerationSuppression)) {
        switch ([dongle.legacy observe:linked]) {
            case APBLinkTransitionUnchanged:
                break;
            case APBLinkTransitionChanged:
                [dongle cancelPendingDown];
                [self refresh:dongle];
                break;
            case APBLinkTransitionCancelDown:
                [dongle cancelPendingDown];
                break;
            case APBLinkTransitionScheduleDown:
                [self scheduleLegacyDown:dongle];
                break;
        }
    }
    if (changed) [self requestQuery:dongle];
}

- (void)scheduleLegacyDown:(APBJabraDongle *)dongle {
    [dongle cancelPendingDown];
    NSString *key = dongle.key;
    NSInteger generation = dongle.generation;
    __weak typeof(self) weakSelf = self;
    dispatch_block_t work = dispatch_block_create(0, ^{
        typeof(self) self = weakSelf;
        if (!self || !self->_isRunning) return;
        APBJabraDongle *current = self->_dongles[key];
        if (!current || current.generation != generation) return;
        current.pendingDown = nil;
        if ([current.legacy commitDown]) [self refresh:current];
    });
    dongle.pendingDown = work;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DownDebounce * NSEC_PER_SEC)), dispatch_get_main_queue(), work);
}

#pragma mark GNP transactions

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
        return;
    }
    query.cursor = step.cursor;
    query.bluetoothType = step.bluetoothType;
    query.attempt = 0;
    [self transmit:dongle query:query];
}

- (void)transmit:(APBJabraDongle *)dongle query:(APBJabraQuery *)query {
    query.attempt += 1;
    APBJabraInterface *interface = query.interface;
    NSData *body = nil;
    IOHIDValueRef value = NULL;
    if (interface.hasManagement && interface.managementOutput) {
        body = [APBJabraGNP encodeQueryWithSequence:[self nextSequence]
                                              group:APBGNPPairingGroup
                                                 op:APBGNPRecordOp
                                          arguments:[APBJabraGNP recordArgumentsWithCursor:query.cursor
                                                                             bluetoothType:query.bluetoothType]
                                        frameLength:interface.management.outputFrameLength];
    }
    if (body) {
        value = IOHIDValueCreateWithBytes(kCFAllocatorDefault, interface.managementOutput, 0, body.bytes, (CFIndex)body.length);
    }
    if (!value) {
        [self finish:dongle query:query evidence:APBGNPEvidenceInconclusive];
        return;
    }
    // Record the awaited sequence and arm the timeout before writing, so a fast
    // reply cannot arrive against unprepared state.
    query.sequence = ((const uint8_t *)body.bytes)[2];
    [interface.reassembler reset];
    [self armTimeout:dongle query:query];
    IOReturn status = IOHIDDeviceSetValue(interface.device, interface.managementOutput, value);
    CFRelease(value);
    if (status != kIOReturnSuccess) {
        [self finish:dongle query:query evidence:APBGNPEvidenceInconclusive];
    }
}

- (void)armTimeout:(APBJabraDongle *)dongle query:(APBJabraQuery *)query {
    [query cancelTimeout];
    NSString *key = dongle.key;
    __weak typeof(self) weakSelf = self;
    __weak APBJabraQuery *weakQuery = query;
    dispatch_block_t work = dispatch_block_create(0, ^{
        typeof(self) self = weakSelf;
        APBJabraQuery *query = weakQuery;
        if (!self || !self->_isRunning || !query) return;
        APBJabraDongle *current = self->_dongles[key];
        if (!current || current.generation != query.generation || current.query != query) return;
        query.timeout = nil;
        // A request the dongle dropped while still booting is not an answer,
        // so re-send it before concluding anything.
        if (query.attempt < MaximumAttempts) {
            [self transmit:current query:query];
            return;
        }
        APBGNPStep *step = [query.walk fail];
        if (step.isFinished) [self finish:current query:query evidence:step.evidence];
    });
    query.timeout = work;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(QueryTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), work);
}

- (void)finish:(APBJabraDongle *)dongle query:(APBJabraQuery *)query evidence:(APBGNPEvidence)evidence {
    if (dongle.query != query) return;
    [query cancelTimeout];
    dongle.query = nil;
    dongle.awaitingFirstAnswer = NO;
    // Incomplete evidence must not linger as authoritative, otherwise a single
    // failed cycle would freeze a stale verdict in place.
    dongle.vendor = evidence == APBGNPEvidenceInconclusive ? APBGNPEvidenceNone : evidence;
    [self refresh:dongle];
    if (dongle.requeryWhenIdle) {
        dongle.requeryWhenIdle = NO;
        [self requestQuery:dongle];
    }
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
    if (interface.hasManagement && reportID == interface.management.inputReportID) {
        // IOKit prefixes the buffer with the physical report ID; the canonical
        // GNP body starts after it.
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
        APBJabraQuery *query = dongle.query;
        if (!query || query.generation != dongle.generation
            || ![APBJabraGNP isReply:message sequence:query.sequence group:APBGNPPairingGroup op:APBGNPRecordOp]) {
            return;
        }
        [query cancelTimeout];
        [self advance:dongle query:query step:[query.walk acceptRecord:message.arguments]];
        return;
    }
    APBJabraProfile *profile = interface.profile;
    if (profile.signalKind != APBJabraSignalKindReport) return;
    APBTriState linked = [APBJabraLink decodeReportID:reportID
                                           expectedID:profile.reportID
                                                bytes:bytes
                                            byteIndex:profile.byteIndex
                                              bitMask:profile.bitMask];
    if (linked == APBTriStateUnknown) return;
    [self observeLegacy:dongle linked:linked == APBTriStateYes];
}

#pragma mark Polling

- (void)updatePollTimer {
    BOOL needsPolling = NO;
    for (APBJabraDongle *dongle in _dongles.allValues) {
        if (dongle.managementInterface) needsPolling = YES;
        for (APBJabraInterface *interface in dongle.interfaces.allValues) {
            if (interface.profile.signalKind == APBJabraSignalKindReport) needsPolling = YES;
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
    for (APBJabraDongle *dongle in _dongles.allValues.copy) {
        for (APBJabraInterface *interface in dongle.interfaces.allValues.copy) {
            if (interface.profile.signalKind != APBJabraSignalKindReport) continue;
            APBTriState linked = [APBJabraHIDMonitor readReportLinkedDevice:interface.device
                                                                    profile:interface.profile
                                                                 bufferSize:interface.bufferSize];
            if (linked != APBTriStateUnknown) [self observeLegacy:dongle linked:linked == APBTriStateYes];
        }
        if (uptime - dongle.lastQueryAt >= VendorRefreshInterval) [self requestQuery:dongle];
    }
}

#pragma mark Device inspection

+ (NSString *)identityOfDevice:(IOHIDDeviceRef)device serial:(NSString **)serial {
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
            [productID isKindOfClass:NSNumber.class] ? productID.longValue : -1,
            [location isKindOfClass:NSNumber.class] ? location.longValue : -1];
}

+ (BOOL)managementLayout:(IOHIDDeviceRef)device layout:(APBGNPLayout *)layout output:(IOHIDElementRef *)output {
    NSDictionary *match = @{
        @kIOHIDElementUsagePageKey: @(APBGNPUsagePage),
        @kIOHIDElementUsageKey: @(APBGNPUsage),
    };
    NSArray *elements = (__bridge_transfer NSArray *)IOHIDDeviceCopyMatchingElements(device, (__bridge CFDictionaryRef)match, 0);
    if (!elements) return NO;

    NSMutableData *descriptors = [NSMutableData data];
    NSMutableArray *outputs = [NSMutableArray array];
    for (id object in elements) {
        IOHIDElementRef element = (__bridge IOHIDElementRef)object;
        // IOKit reports an element's full width in reportSize, while
        // reportCount is the item count, so the two must not be multiplied.
        NSInteger bits = IOHIDElementGetReportSize(element);
        uint8_t reportID = (uint8_t)IOHIDElementGetReportID(element);
        IOHIDElementType type = IOHIDElementGetType(element);
        if (type == kIOHIDElementTypeFeature || type == kIOHIDElementTypeCollection) continue;
        BOOL isOutput = type == kIOHIDElementTypeOutput;
        APBGNPElement descriptor = { .isOutput = isOutput, .reportID = reportID, .bits = bits };
        [descriptors appendBytes:&descriptor length:sizeof descriptor];
        if (isOutput) [outputs addObject:@[ object, @(reportID), @(bits / 8) ]];
    }
    APBGNPLayout selected;
    if (![APBJabraGNP selectLayoutFromElements:descriptors.bytes
                                         count:descriptors.length / sizeof(APBGNPElement)
                                        layout:&selected]) {
        return NO;
    }
    for (NSArray *candidate in outputs) {
        if ([candidate[1] unsignedCharValue] == selected.outputReportID
            && [candidate[2] integerValue] == selected.outputFrameLength) {
            *layout = selected;
            *output = (__bridge IOHIDElementRef)candidate[0];
            return YES;
        }
    }
    return NO;
}

+ (APBTriState)readLinkedDevice:(IOHIDDeviceRef)device element:(IOHIDElementRef)element linkedValue:(NSInteger)linkedValue {
    IOHIDValueRef value = NULL;
    if (IOHIDDeviceGetValue(device, element, &value) != kIOReturnSuccess || !value) return APBTriStateUnknown;
    return [APBJabraLink snapshotValue:IOHIDValueGetIntegerValue(value)
                             timestamp:IOHIDValueGetTimeStamp(value)
                           linkedValue:linkedValue];
}

+ (APBTriState)readReportLinkedDevice:(IOHIDDeviceRef)device profile:(APBJabraProfile *)profile bufferSize:(CFIndex)bufferSize {
    CFIndex length = MAX(bufferSize, profile.byteIndex + 1);
    NSMutableData *bytes = [NSMutableData dataWithLength:(NSUInteger)length];
    IOReturn status = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, profile.reportID, bytes.mutableBytes, &length);
    if (status != kIOReturnSuccess || length <= profile.byteIndex) return APBTriStateUnknown;
    // IOHIDDeviceGetReport already selects reportID. Upstream Link 390 hardware
    // research indexes the returned payload directly.
    return APBTriStateFromBool((((const uint8_t *)bytes.bytes)[profile.byteIndex] & profile.bitMask) != 0);
}

#pragma mark Callback plumbing

/// Resolves a device back to the dongle that currently owns it, so work
/// arriving after a detach or replug is dropped.
- (APBJabraDongle *)dongleForDevice:(IOHIDDeviceRef)device interface:(APBJabraInterface **)interface {
    NSNumber *deviceKey = DeviceKey(device);
    NSString *key = _interfaceKeys[deviceKey];
    APBJabraDongle *dongle = key ? _dongles[key] : nil;
    APBJabraInterface *found = dongle.interfaces[deviceKey];
    if (!found) return nil;
    *interface = found;
    return dongle;
}

- (void)handleValue:(IOHIDValueRef)value {
    IOHIDElementRef element = IOHIDValueGetElement(value);
    APBJabraInterface *interface = nil;
    APBJabraDongle *dongle = [self dongleForDevice:IOHIDElementGetDevice(element) interface:&interface];
    if (!dongle || !interface.legacyElement
        || IOHIDElementGetCookie(interface.legacyElement) != IOHIDElementGetCookie(element)
        || interface.profile.signalKind != APBJabraSignalKindElement) {
        return;
    }
    [self observeLegacy:dongle
                 linked:[APBJabraLink decodeElementValue:IOHIDValueGetIntegerValue(value)
                                             linkedValue:interface.profile.linkedValue]];
}

- (void)handleReportFrom:(IOHIDDeviceRef)device reportID:(uint32_t)reportID bytes:(NSData *)bytes {
    APBJabraInterface *interface = nil;
    APBJabraDongle *dongle = [self dongleForDevice:device interface:&interface];
    if (!dongle) return;
    [self handleReport:dongle interface:interface reportID:(uint8_t)reportID bytes:bytes];
}

// IOKit delivers every callback on the main run loop, where the manager and
// devices are scheduled, so they run on the main thread already.

static void MatchCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    APBJabraHIDMonitor *monitor = (__bridge APBJabraHIDMonitor *)context;
    if (monitor->_isRunning) [monitor attach:device];
}

static void RemovalCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    APBJabraHIDMonitor *monitor = (__bridge APBJabraHIDMonitor *)context;
    if (monitor->_isRunning) [monitor detach:device];
}

static void ValueCallback(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
    APBJabraHIDMonitor *monitor = (__bridge APBJabraHIDMonitor *)context;
    if (monitor->_isRunning) [monitor handleValue:value];
}

static void ReportCallback(void *context, IOReturn result, void *sender, IOHIDReportType type,
                           uint32_t reportID, uint8_t *report, CFIndex length) {
    if (!sender || length <= 0) return;
    APBJabraHIDMonitor *monitor = (__bridge APBJabraHIDMonitor *)context;
    if (!monitor->_isRunning) return;
    // GNP needs the whole frame, so the buffer is never truncated here.
    [monitor handleReportFrom:(IOHIDDeviceRef)sender reportID:reportID bytes:[NSData dataWithBytes:report length:(NSUInteger)length]];
}

@end
