#import "LaunchAtLoginController.h"

@implementation APBLaunchAtLoginController {
    SMAppServiceStatus (^_status)(void);
    BOOL (^_register)(NSError **);
    BOOL (^_unregister)(NSError **);
}

- (instancetype)init {
    return [self initWithStatus:^SMAppServiceStatus {
        return SMAppService.mainAppService.status;
    } register:^BOOL(NSError **error) {
        return [SMAppService.mainAppService registerAndReturnError:error];
    } unregister:^BOOL(NSError **error) {
        return [SMAppService.mainAppService unregisterAndReturnError:error];
    }];
}

- (instancetype)initWithStatus:(SMAppServiceStatus (^)(void))status
                      register:(BOOL (^)(NSError **))registerService
                    unregister:(BOOL (^)(NSError **))unregisterService {
    if ((self = [super init])) {
        _status = [status copy];
        _register = [registerService copy];
        _unregister = [unregisterService copy];
        [self refresh];
    }
    return self;
}

- (void)refresh {
    SMAppServiceStatus current = _status();
    _isEnabled = current == SMAppServiceStatusEnabled || current == SMAppServiceStatusRequiresApproval;
    _requiresApproval = current == SMAppServiceStatusRequiresApproval;
    _errorMessage = nil;
    if (_onChange) _onChange();
}

- (void)setEnabled:(BOOL)enabled {
    NSError *error = nil;
    BOOL succeeded = enabled ? _register(&error) : _unregister(&error);
    if (!succeeded) {
        [self refresh];
        _errorMessage = error.localizedDescription ?: @"Unknown error";
        if (_onChange) _onChange();
        return;
    }
    if (enabled) {
        [self refresh];
    } else {
        _isEnabled = NO;
        _requiresApproval = NO;
        _errorMessage = nil;
        if (_onChange) _onChange();
    }
}

@end
