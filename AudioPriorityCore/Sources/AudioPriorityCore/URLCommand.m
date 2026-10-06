#import "URLCommand.h"

NSString *const APBURLCommandScheme = @"audioprioritybar";

NSArray<NSNumber *> *APBURLCommandAllCases(void) {
    return @[
        @(APBURLCommandToggleMicMute),
        @(APBURLCommandMuteMic),
        @(APBURLCommandUnmuteMic),
    ];
}

NSString *APBURLCommandRawValue(APBURLCommand command) {
    switch (command) {
        case APBURLCommandToggleMicMute: return @"toggle-mic-mute";
        case APBURLCommandMuteMic: return @"mute-mic";
        case APBURLCommandUnmuteMic: return @"unmute-mic";
        case APBURLCommandNone: return nil;
    }
    return nil;
}

APBURLCommand APBURLCommandFromRawValue(NSString *rawValue) {
    for (NSNumber *command in APBURLCommandAllCases()) {
        if ([rawValue isEqualToString:APBURLCommandRawValue(command.integerValue)]) {
            return command.integerValue;
        }
    }
    return APBURLCommandNone;
}

APBURLCommand APBURLCommandFromURL(NSURL *url) {
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url
                                        resolvingAgainstBaseURL:NO];
    if (!parts
        || ![parts.scheme.lowercaseString isEqualToString:APBURLCommandScheme]
        || parts.path.length > 0
        || parts.query != nil
        || parts.fragment != nil
        || parts.user != nil
        || parts.password != nil
        || parts.port != nil
        || parts.host == nil) {
        return APBURLCommandNone;
    }
    return APBURLCommandFromRawValue(parts.host.lowercaseString);
}
