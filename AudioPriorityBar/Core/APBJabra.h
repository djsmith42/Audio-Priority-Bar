#import <Foundation/Foundation.h>
#import "APBModels.h"

NS_ASSUME_NONNULL_BEGIN

/// A Boolean that may be unknown.
typedef NS_ENUM(NSInteger, APBTriState) {
    APBTriStateUnknown,
    APBTriStateNo,
    APBTriStateYes,
};

static inline APBTriState APBTriStateFromBool(BOOL value) {
    return value ? APBTriStateYes : APBTriStateNo;
}

#pragma mark - GNP

/// Jabra GNP vendor messaging, used to read a dongle's real Bluetooth
/// connection state.
///
/// The telephony "link" bit in `APBJabraLink` cannot be trusted on its own:
/// the dongle asserts a false "connected" roughly 1.8s after USB enumeration,
/// identically whether a headset is on or off, and never corrects it. Asking
/// the dongle over GNP is the only way to learn the truth, so `APBJabraLink`
/// survives only as a fallback for devices that do not answer.
///
/// The framing and pairing-record query are based on jabridge (Apache-2.0,
/// https://github.com/Watchdog0x/jabridge), verified locally against a Jabra
/// Link 380 (PID 0x24ca) paired with an Evolve2 85.

/// Vendor usage page carrying the management byte stream.
static const NSInteger APBGNPUsagePage = 0xff00;
static const NSInteger APBGNPUsage = 0x01;
/// Canonical GNP report number. The physical HID report ID is discovered from
/// the descriptor and is not guaranteed to equal this value, so nothing here
/// may hard-code it.
static const uint8_t APBGNPCanonicalReportID = 0x05;
/// Largest physical report length, including the report ID byte.
static const NSInteger APBGNPMaximumFrameLength = 65;

static const uint8_t APBGNPHostAddress = 0x00;
static const uint8_t APBGNPDongleAddress = 0x01;
static const uint8_t APBGNPKindMask = 0xc0;
static const uint8_t APBGNPLengthMask = 0x3f;
static const uint8_t APBGNPQueryKind = 0x40;
static const uint8_t APBGNPReplyKind = 0xc0;
/// Unsolicited notifications carry a zero kind and are never replies.
static const uint8_t APBGNPEventKind = 0x00;
/// Canonical header bytes preceding the arguments.
static const NSInteger APBGNPHeaderLength = 6;

static const uint8_t APBGNPPairingGroup = 0x0d;
/// Reads one remembered-device record. Its reply carries both the connection
/// state and the cursor for the next record, so the companion name opcode
/// 0x32 is not needed for link detection.
static const uint8_t APBGNPRecordOp = 0x28;
/// The dongle announces a remembered device connecting or disconnecting
/// without being asked, about 100ms after it happens. Used only as a trigger
/// to re-read the pairing database, so nothing depends on the layout of its
/// payload.
static const uint8_t APBGNPConnectionEventOp = 0x26;
/// Record state byte meaning "this remembered device is connected".
static const uint8_t APBGNPConnectedState = 0x03;
static const NSInteger APBGNPCursorLength = 2;
/// Upper bound on records per database, guarding against a runaway walk.
static const NSInteger APBGNPRecordCap = 256;
/// A record reply must be long enough to carry cursor, state and address.
static const NSInteger APBGNPRecordMinimumLength = 12;
static const NSInteger APBGNPRecordStateIndex = 2;

typedef NS_ENUM(NSInteger, APBGNPEvidence) {
    /// No evidence at all.
    APBGNPEvidenceNone,
    APBGNPEvidenceConnected,
    APBGNPEvidenceDisconnected,
    /// Evidence was incomplete, so neither state is proven.
    APBGNPEvidenceInconclusive,
};

/// One candidate management element, as read from a HID descriptor.
typedef struct {
    BOOL isOutput;
    uint8_t reportID;
    /// Total width of the element in bits.
    NSInteger bits;
} APBGNPElement;

/// Physical transport parameters for one device's management collection.
typedef struct {
    uint8_t inputReportID;
    uint8_t outputReportID;
    /// Body bytes per frame, excluding the report ID.
    NSInteger inputFrameLength;
    NSInteger outputFrameLength;
} APBGNPLayout;

@interface APBGNPMessage : NSObject
@property (nonatomic, readonly) uint8_t destination;
@property (nonatomic, readonly) uint8_t source;
@property (nonatomic, readonly) uint8_t sequence;
@property (nonatomic, readonly) uint8_t kind;
@property (nonatomic, readonly) uint8_t group;
@property (nonatomic, readonly) uint8_t op;
@property (nonatomic, readonly, copy) NSData *arguments;
- (instancetype)initWithDestination:(uint8_t)destination
                             source:(uint8_t)source
                           sequence:(uint8_t)sequence
                               kind:(uint8_t)kind
                              group:(uint8_t)group
                                 op:(uint8_t)op
                          arguments:(NSData *)arguments NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface APBJabraGNP : NSObject

/// Cursor value that terminates a database walk.
@property (class, nonatomic, readonly) NSData *endCursor;
/// Both database types must terminate before "nothing connected" is proven,
/// because a device may populate only one of them.
@property (class, nonatomic, readonly) NSData *bluetoothTypes;

/// Arguments for a record query. The cursor is treated as opaque bytes: the
/// dongle's byte order for this field disagrees with jabridge's little-endian
/// encode and decode, which cancel out only because they are applied
/// symmetrically. Echoing the received bytes avoids the question.
+ (NSData *)recordArgumentsWithCursor:(NSData *)cursor bluetoothType:(uint8_t)bluetoothType;

/// Chooses the management layout from the device's FF00:0001 elements.
/// Returns NO when no usable pair exists, or when either direction is
/// ambiguous, so an unrecognised device falls back instead of guessing.
+ (BOOL)selectLayoutFromElements:(const APBGNPElement *)elements
                           count:(NSUInteger)count
                          layout:(APBGNPLayout *)layout;

/// Builds the body of one query, zero padded to a single frame.
///
/// Returns nil when the arguments would not fit. Every command this app sends
/// is a few bytes, so overflow is a programming error rather than a reason to
/// fragment writes. Replies are reassembled generically because their length
/// is not under our control.
+ (nullable NSData *)encodeQueryToDestination:(uint8_t)destination
                                     sequence:(uint8_t)sequence
                                        group:(uint8_t)group
                                           op:(uint8_t)op
                                    arguments:(NSData *)arguments
                                  frameLength:(NSInteger)frameLength;
/// Addressed to the dongle.
+ (nullable NSData *)encodeQueryWithSequence:(uint8_t)sequence
                                       group:(uint8_t)group
                                          op:(uint8_t)op
                                   arguments:(NSData *)arguments
                                 frameLength:(NSInteger)frameLength;

/// Decodes a canonical body, meaning a frame with the report ID removed.
+ (nullable APBGNPMessage *)decode:(NSData *)body;

/// Whether `message` is the specific reply being awaited. Every field is
/// checked so stale replies and unsolicited events cannot be mistaken for an
/// answer.
+ (BOOL)isReply:(APBGNPMessage *)message
       sequence:(uint8_t)sequence
          group:(uint8_t)group
             op:(uint8_t)op
         source:(uint8_t)source;
/// From the dongle.
+ (BOOL)isReply:(APBGNPMessage *)message sequence:(uint8_t)sequence group:(uint8_t)group op:(uint8_t)op;

/// True for the dongle's unsolicited announcement that a remembered device
/// connected or disconnected. It carries a state byte, which is deliberately
/// ignored: the announcement only says something changed, and a pairing walk
/// is what establishes what.
+ (BOOL)isConnectionEvent:(APBGNPMessage *)message;

/// Resolves the value a dongle should report. Complete GNP evidence wins;
/// otherwise the legacy bit is the fallback.
+ (APBTriState)resolveVendor:(APBGNPEvidence)vendor legacy:(APBTriState)legacy;

@end

/// Accumulates physical frames into canonical bodies.
@interface APBGNPReassembler : NSObject
/// Feeds one frame with the report ID already removed, returning a canonical
/// body once it is complete.
- (nullable NSData *)feed:(NSData *)chunk;
- (void)reset;
@end

/// One step of a pairing walk: either a query to send or a verdict.
@interface APBGNPStep : NSObject
@property (nonatomic, readonly) BOOL isFinished;
@property (nonatomic, readonly) APBGNPEvidence evidence;
@property (nonatomic, readonly, copy, nullable) NSData *cursor;
@property (nonatomic, readonly) uint8_t bluetoothType;
+ (instancetype)queryWithCursor:(NSData *)cursor bluetoothType:(uint8_t)bluetoothType;
+ (instancetype)finished:(APBGNPEvidence)evidence;
@end

/// Walks a dongle's remembered-device databases to decide whether anything is
/// connected to it.
///
/// `Connected` may short-circuit on the first connected record, but
/// `Disconnected` requires every database to terminate cleanly. A timeout,
/// malformed record, repeated cursor or cap exhaustion yields `Inconclusive`,
/// so automatic switching never acts on partial evidence.
@interface APBGNPPairingWalk : NSObject
- (instancetype)init;
- (instancetype)initWithBluetoothTypes:(NSData *)bluetoothTypes cap:(NSInteger)cap NS_DESIGNATED_INITIALIZER;
- (APBGNPStep *)start;
/// Accepts the arguments of one record reply.
- (APBGNPStep *)acceptRecord:(NSData *)arguments;
/// Records a missing, malformed or timed-out reply.
- (APBGNPStep *)fail;
@end

#pragma mark - Link

typedef NS_ENUM(NSInteger, APBJabraProfileID) {
    APBJabraProfileIDNone,
    APBJabraProfileIDLink380,
    APBJabraProfileIDLink390,
};

typedef NS_ENUM(NSInteger, APBJabraSignalKind) {
    APBJabraSignalKindElement,
    APBJabraSignalKindReport,
};

@interface APBJabraProfile : NSObject
@property (nonatomic, readonly) APBJabraProfileID profileID;
@property (nonatomic, readonly, copy) NSString *product;
@property (nonatomic, readonly) APBJabraSignalKind signalKind;
/// For an element signal.
@property (nonatomic, readonly) NSInteger page;
@property (nonatomic, readonly) NSInteger usage;
@property (nonatomic, readonly) NSInteger linkedValue;
/// For a report signal.
@property (nonatomic, readonly) NSInteger reportID;
@property (nonatomic, readonly) NSInteger byteIndex;
@property (nonatomic, readonly) uint8_t bitMask;
@end

@interface APBJabraLink : NSObject

@property (class, nonatomic, readonly) NSInteger vendorID;
@property (class, nonatomic, readonly) NSArray<APBJabraProfile *> *profiles;

+ (nullable APBJabraProfile *)profileMatching:(NSString *)name;
/// Only a Link dongle can publish an audio device whose headset is absent. A
/// Jabra headset or speakerphone plugged in directly is present whenever
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
+ (APBTriState)snapshotValue:(NSInteger)value timestamp:(uint64_t)timestamp linkedValue:(NSInteger)linkedValue;
+ (APBTriState)decodeReportID:(NSInteger)reportID
                   expectedID:(NSInteger)expectedID
                        bytes:(NSData *)bytes
                    byteIndex:(NSInteger)byteIndex
                      bitMask:(uint8_t)bitMask;
+ (BOOL)allowsSelectionWhenSupported:(BOOL)isSupported state:(APBLinkState)state;

@end

typedef NS_ENUM(NSInteger, APBLinkTransition) {
    APBLinkTransitionUnchanged,
    APBLinkTransitionChanged,
    APBLinkTransitionScheduleDown,
    APBLinkTransitionCancelDown,
};

@interface APBDebouncedLinkState : NSObject
@property (nonatomic, readonly) APBTriState observed;
@property (nonatomic, readonly) APBTriState effective;
- (instancetype)init;
- (instancetype)initWithObserved:(APBTriState)observed effective:(APBTriState)effective NS_DESIGNATED_INITIALIZER;
- (BOOL)seed:(BOOL)linked;
- (APBLinkTransition)observe:(BOOL)linked;
- (BOOL)commitDown;
@end

NS_ASSUME_NONNULL_END
