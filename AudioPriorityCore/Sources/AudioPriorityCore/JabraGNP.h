#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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

// MARK: - Management collection

/// Vendor usage page carrying the management byte stream.
FOUNDATION_EXPORT const NSInteger APBGNPUsagePage;
FOUNDATION_EXPORT const NSInteger APBGNPUsage;
/// Canonical GNP report number. The physical HID report ID is discovered
/// from the descriptor and is not guaranteed to equal this value, so nothing
/// here may hard-code it.
FOUNDATION_EXPORT const uint8_t APBGNPCanonicalReportID;
/// Largest physical report length, including the report ID byte.
FOUNDATION_EXPORT const NSInteger APBGNPMaximumFrameLength;

// MARK: - Framing

FOUNDATION_EXPORT const uint8_t APBGNPHostAddress;
FOUNDATION_EXPORT const uint8_t APBGNPDongleAddress;
FOUNDATION_EXPORT const uint8_t APBGNPKindMask;
FOUNDATION_EXPORT const uint8_t APBGNPLengthMask;
FOUNDATION_EXPORT const uint8_t APBGNPQueryKind;
FOUNDATION_EXPORT const uint8_t APBGNPReplyKind;
/// Unsolicited notifications carry a zero kind and are never replies.
FOUNDATION_EXPORT const uint8_t APBGNPEventKind;
/// Canonical header bytes preceding the arguments.
FOUNDATION_EXPORT const NSInteger APBGNPHeaderLength;

// MARK: - Pairing database

FOUNDATION_EXPORT const uint8_t APBGNPPairingGroup;
/// Reads one remembered-device record. Its reply carries both the connection
/// state and the cursor for the next record, so the companion name opcode
/// 0x32 is not needed for link detection.
FOUNDATION_EXPORT const uint8_t APBGNPRecordOp;
/// The dongle announces a remembered device connecting or disconnecting
/// without being asked, about 100ms after it happens. Used only as a trigger
/// to re-read the pairing database, so nothing depends on the layout of its
/// payload.
FOUNDATION_EXPORT const uint8_t APBGNPConnectionEventOp;
/// Record state byte meaning "this remembered device is connected".
FOUNDATION_EXPORT const uint8_t APBGNPConnectedState;
FOUNDATION_EXPORT const NSInteger APBGNPCursorLength;
/// Cursor value that terminates a database walk.
FOUNDATION_EXPORT NSData *APBGNPEndCursor(void);
/// Both database types must terminate before "nothing connected" is proven,
/// because a device may populate only one of them.
FOUNDATION_EXPORT NSData *APBGNPBluetoothTypes(void);
/// Upper bound on records per database, guarding against a runaway walk.
FOUNDATION_EXPORT const NSInteger APBGNPRecordCap;
/// A record reply must be long enough to carry cursor, state and address.
FOUNDATION_EXPORT const NSInteger APBGNPRecordMinimumLength;
FOUNDATION_EXPORT const NSInteger APBGNPRecordStateIndex;

// MARK: - Headset battery

/// The headset behind a dongle, as a GNP address.
FOUNDATION_EXPORT const uint8_t APBGNPHeadsetAddress;
FOUNDATION_EXPORT const uint8_t APBGNPStatusGroup;
/// Answered with `[flags, percent, ...]`, and also sent unasked when the
/// level changes, per jabridge.
FOUNDATION_EXPORT const uint8_t APBGNPBatteryOp;

typedef NS_ENUM(NSInteger, APBGNPDirection) {
    APBGNPDirectionInput,
    APBGNPDirectionOutput,
};

/// One candidate management element, as read from a HID descriptor.
@interface APBGNPElement : NSObject

@property (nonatomic, readonly) APBGNPDirection direction;
@property (nonatomic, readonly) uint8_t reportID;
/// Total width of the element in bits.
@property (nonatomic, readonly) NSInteger bits;

+ (instancetype)elementWithDirection:(APBGNPDirection)direction reportID:(uint8_t)reportID bits:(NSInteger)bits;

@end

/// Physical transport parameters for one device's management collection.
@interface APBGNPLayout : NSObject

@property (nonatomic, readonly) uint8_t inputReportID;
@property (nonatomic, readonly) uint8_t outputReportID;
/// Body bytes per frame, excluding the report ID.
@property (nonatomic, readonly) NSInteger inputFrameLength;
@property (nonatomic, readonly) NSInteger outputFrameLength;

- (instancetype)initWithInputReportID:(uint8_t)inputReportID
                       outputReportID:(uint8_t)outputReportID
                     inputFrameLength:(NSInteger)inputFrameLength
                    outputFrameLength:(NSInteger)outputFrameLength;

@end

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
                          arguments:(NSData *)arguments;

@end

/// Accumulates physical frames into canonical bodies.
@interface APBGNPReassembler : NSObject

/// Feeds one frame with the report ID already removed, returning a canonical
/// body once it is complete.
- (nullable NSData *)feed:(NSData *)chunk;
- (void)reset;

@end

typedef NS_ENUM(NSInteger, APBGNPEvidence) {
    APBGNPEvidenceNone = 0,
    APBGNPEvidenceConnected,
    APBGNPEvidenceDisconnected,
    /// Evidence was incomplete, so neither state is proven.
    APBGNPEvidenceInconclusive,
};

/// What a pairing walk wants next: another record query, or its verdict.
@interface APBGNPStep : NSObject

@property (nonatomic, readonly) BOOL isFinished;
@property (nonatomic, readonly, copy, nullable) NSData *cursor;
@property (nonatomic, readonly) uint8_t bluetoothType;
@property (nonatomic, readonly) APBGNPEvidence evidence;

+ (instancetype)queryWithCursor:(NSData *)cursor bluetoothType:(uint8_t)bluetoothType;
+ (instancetype)finished:(APBGNPEvidence)evidence;

@end

/// Walks a dongle's remembered-device databases to decide whether anything
/// is connected to it.
///
/// `connected` may short-circuit on the first connected record, but
/// `disconnected` requires every database to terminate cleanly. A timeout,
/// malformed record, repeated cursor or cap exhaustion yields `inconclusive`,
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

@interface APBJabraGNP : NSObject

/// Arguments for a record query. The cursor is treated as opaque bytes: the
/// dongle's byte order for this field disagrees with jabridge's
/// little-endian encode and decode, which cancel out only because they are
/// applied symmetrically. Echoing the received bytes avoids the question.
+ (NSData *)recordArgumentsWithCursor:(NSData *)cursor bluetoothType:(uint8_t)bluetoothType;

/// Chooses the management layout from the device's FF00:0001 elements.
/// Returns nil when no usable pair exists, or when either direction is
/// ambiguous, so an unrecognised device falls back instead of guessing.
+ (nullable APBGNPLayout *)selectLayout:(NSArray<APBGNPElement *> *)elements;

/// Builds the body of one query, zero padded to a single frame.
///
/// Returns nil when the arguments would not fit. Every command this app
/// sends is a few bytes, so overflow is a programming error rather than a
/// reason to fragment writes. Replies are reassembled generically because
/// their length is not under our control.
+ (nullable NSData *)encodeQueryWithDestination:(uint8_t)destination
                                       sequence:(uint8_t)sequence
                                          group:(uint8_t)group
                                             op:(uint8_t)op
                                      arguments:(NSData *)arguments
                                    frameLength:(NSInteger)frameLength;
/// A query addressed to the dongle.
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

/// The headset's battery percentage, from its answer to a battery query or
/// from an update it sent unasked. Nil for any other message.
+ (nullable NSNumber *)batteryLevel:(APBGNPMessage *)message;

/// Resolves the value a dongle should report. Complete GNP evidence wins;
/// otherwise the legacy bit is the fallback. Nil means unknown.
+ (nullable NSNumber *)resolveVendor:(APBGNPEvidence)vendor legacy:(nullable NSNumber *)legacy;

@end

NS_ASSUME_NONNULL_END
