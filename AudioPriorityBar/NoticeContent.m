#import "NoticeContent.h"

@implementation APBNoticeLine

+ (instancetype)lineWithIcon:(NSString *)icon text:(NSString *)text {
    APBNoticeLine *line = [[self alloc] init];
    line->_icon = [icon copy];
    line->_text = [text copy];
    return line;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBNoticeLine.class]) return NO;
    APBNoticeLine *other = object;
    return [_icon isEqualToString:other.icon] && [_text isEqualToString:other.text];
}

- (NSUInteger)hash {
    return _icon.hash ^ _text.hash;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@>", _icon, _text];
}

@end

@implementation APBNoticeContent

- (instancetype)initWithLines:(NSArray<APBNoticeLine *> *)lines announcement:(NSString *)announcement {
    if ((self = [super init])) {
        _lines = [lines copy];
        _announcement = [announcement copy];
    }
    return self;
}

+ (APBNoticeContent *)mutedWhileRecording {
    static APBNoticeContent *content;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        content = [[APBNoticeContent alloc] initWithLines:@[[APBNoticeLine lineWithIcon:@"mic.slash.fill"
                                                                                   text:@"Microphone muted"]]
                                             announcement:@"Microphone muted"];
    });
    return content;
}

+ (APBNoticeContent *)currentWithSwitchNotice:(APBNoticeContent *)switchNotice
                           showsMutedReminder:(BOOL)showsMutedReminder
                                 isSuppressed:(BOOL)isSuppressed {
    if (isSuppressed) return nil;
    return switchNotice ?: (showsMutedReminder ? self.mutedWhileRecording : nil);
}

+ (APBNoticeContent *)switchedTo:(NSArray<APBAudioDevice *> *)devices
                            icon:(NSString *(^)(APBAudioDevice *))icon {
    if (devices.count == 2 && [devices[0].name isEqualToString:devices[1].name]) {
        return [[APBNoticeContent alloc]
            initWithLines:@[[APBNoticeLine lineWithIcon:icon(devices[0]) text:devices[0].name]]
             announcement:[NSString stringWithFormat:@"Output and microphone: %@", devices[0].name]];
    }
    NSMutableArray *lines = [NSMutableArray array], *spoken = [NSMutableArray array];
    for (APBAudioDevice *device in devices) {
        [lines addObject:[APBNoticeLine lineWithIcon:icon(device) text:device.name]];
        [spoken addObject:[NSString stringWithFormat:@"%@: %@",
                           device.role == APBDeviceRoleInput ? @"Microphone" : @"Output", device.name]];
    }
    return [[APBNoticeContent alloc] initWithLines:lines announcement:[spoken componentsJoinedByString:@", "]];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBNoticeContent.class]) return NO;
    APBNoticeContent *other = object;
    return [_lines isEqualToArray:other.lines] && [_announcement isEqualToString:other.announcement];
}

- (NSUInteger)hash {
    return _announcement.hash;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<notice %@ \"%@\">", _lines, _announcement];
}

@end

@implementation APBMutedReminderState

- (BOOL)updateApplies:(BOOL)applies {
    if (!applies) _isDismissed = NO;
    return applies && !_isDismissed;
}

- (void)dismiss {
    _isDismissed = YES;
}

@end
